import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/title_detail.dart';
import '../secrets.dart';
import 'catalog_api.dart';
import 'mal_api.dart';

/// Fetches and caches MAL title details (with relations) and, for titles
/// outside the catalog, AniList country/color. Saved on the phone so each
/// franchise only has to be looked up once.
class DetailStore {
  DetailStore._();
  static final DetailStore instance = DetailStore._();

  static const _file = 'title_details.json';

  /// Bumped when the cached fields change; older caches are discarded.
  static const _version = 4;
  static const _malBase = 'https://api.myanimelist.net/v2';
  static const _maxParallel = 3;

  final http.Client _client = http.Client();
  final CatalogApi _aniList = CatalogApi();

  final Map<String, TitleDetail> _details = {};
  final Map<String, AniListInfo> _aniInfo = {};
  final Map<int, AniListSource> _aniSource = {};
  final Map<int, List<int>> _mangaAdaptations = {};
  final Map<String, List<int>> _otherVersions = {};
  final Map<String, Future<TitleDetail?>> _inFlight = {};

  int _running = 0;
  final List<Completer<void>> _waiting = [];
  Timer? _saveTimer;
  bool _loaded = false;

  static String _key(int id, bool anime) => '${anime ? 'a' : 'm'}$id';

  Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _path();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['v'] != _version) return; // older format: start fresh
      for (final e in (j['d'] as List? ?? const [])) {
        final d = TitleDetail.fromJson(e as Map<String, dynamic>);
        _details[_key(d.malId, d.isAnime)] = d;
      }
      final ver = j['ver'] as Map<String, dynamic>? ?? const {};
      ver.forEach((k, v) {
        _otherVersions[k] = [for (final x in v as List) x as int];
      });
      final madp = j['madp'] as Map<String, dynamic>? ?? const {};
      madp.forEach((k, v) {
        final id = int.tryParse(k);
        if (id != null) {
          _mangaAdaptations[id] = [for (final x in v as List) x as int];
        }
      });
      final src = j['srcv'] == 2
          ? j['src'] as Map<String, dynamic>? ?? const {}
          : const <String, dynamic>{};
      src.forEach((k, v) {
        final id = int.tryParse(k);
        if (id != null) {
          _aniSource[id] = AniListSource.fromJson(v as Map<String, dynamic>);
        }
      });
      final ani = j['al'] as Map<String, dynamic>? ?? const {};
      ani.forEach((k, v) {
        final m = v as Map<String, dynamic>;
        _aniInfo[k] = AniListInfo(m['cc'] as String?, m['col'] as int?);
      });
    } catch (_) {
      _details.clear();
      _aniInfo.clear();
    }
  }

  int get cachedCount => _details.length;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final f = await _path();
        await f.writeAsString(jsonEncode({
          'v': _version,
          'd': [for (final d in _details.values) d.toJson()],
          'ver': {
            for (final e in _otherVersions.entries) e.key: e.value,
          },
          'madp': {
            for (final e in _mangaAdaptations.entries) '${e.key}': e.value,
          },
          'srcv': 2,
          'src': {
            for (final e in _aniSource.entries) '${e.key}': e.value.toJson(),
          },
          'al': {
            for (final e in _aniInfo.entries)
              e.key: {'cc': e.value.country, 'col': e.value.coverColor},
          },
        }));
      } catch (_) {}
    });
  }

  Future<void> _acquire() async {
    if (_running < _maxParallel) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _running++;
  }

  void _release() {
    _running--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }

  /// Details for one title, from cache when fresh. Null if MAL doesn't have
  /// it. Throws [MalException] when MAL can't be reached.
  Future<TitleDetail?> get(int id, {required bool anime}) {
    final key = _key(id, anime);
    final cached = _details[key];
    if (cached != null && !cached.isStale) return Future.value(cached);
    return _inFlight[key] ??= _fetch(id, anime, cached).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<TitleDetail?> _fetch(int id, bool anime, TitleDetail? stale) async {
    final kind = anime ? 'anime' : 'manga';
    final fields = 'id,title,alternative_titles,main_picture,mean,media_type,'
        'status,start_date,end_date,'
        '${anime ? 'related_anime,related_manga,source,num_episodes,'
            'average_episode_duration' : 'related_manga'}';
    await _acquire();
    try {
      final res = await _client.get(
        Uri.parse('$_malBase/$kind/$id?fields=$fields'),
        headers: {'X-MAL-CLIENT-ID': kMalClientId.trim()},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        if (stale != null) return stale; // better old data than none
        throw MalException('MyAnimeList returned error ${res.statusCode} '
            'while checking a franchise.');
      }
      final d = TitleDetail.fromMal(
        jsonDecode(res.body) as Map<String, dynamic>,
        anime: anime,
      );
      _details[_key(id, anime)] = d;
      _scheduleSave();
      return d;
    } on MalException {
      rethrow;
    } catch (_) {
      if (stale != null) return stale;
      throw const MalException(
          'Couldn\'t reach MyAnimeList to check the franchise.');
    } finally {
      _release();
    }
  }

  /// AniList country/color for a title that isn't in the catalog.
  /// Returns null if AniList can't be reached; never throws.
  Future<AniListInfo?> aniList(int id, {required bool anime}) async {
    final key = _key(id, anime);
    final cached = _aniInfo[key];
    if (cached != null) return cached;
    try {
      final info = await _aniList.aniListBatchInfo([id], anime: anime);
      final found = info[id] ?? const AniListInfo(null, null);
      _aniInfo[key] = found;
      _scheduleSave();
      return found;
    } catch (_) {
      return null;
    }
  }

  /// What an anime adapts, according to AniList (cached). Null when AniList
  /// can't be reached; never throws.
  Future<AniListSource?> aniListSource(int animeMalId) async {
    final cached = _aniSource[animeMalId];
    if (cached != null) return cached;
    final found = await _aniList.aniListSource(animeMalId);
    if (found != null) {
      _aniSource[animeMalId] = found;
      _scheduleSave();
    }
    return found;
  }

  static final _mangaLink = RegExp(r'myanimelist\.net/manga/(\d+)');
  static final _animeLink = RegExp(r'myanimelist\.net/anime/(\d+)');

  /// Last resort for anime the API won't link to a source: reads the
  /// "Adaptation" entry off the anime's MAL page. Returns MAL manga ids
  /// (empty if none found); never throws.
  Future<List<int>> scrapeAdaptations(int animeMalId) => _scrapeAdaptationLinks(
        'https://myanimelist.net/anime/$animeMalId',
        _mangaLink,
      );

  /// MAL ids of the anime adapting a manga: AniList first, then the
  /// "Adaptation" entries on the MAL manga page. Cached; never throws.
  Future<List<int>> animeAdaptationsOf(int mangaMalId) async {
    final cached = _mangaAdaptations[mangaMalId];
    if (cached != null) return cached;
    var ids = await _aniList.aniListAnimeAdaptations(mangaMalId);
    final reachedAniList = ids != null;
    if (ids == null || ids.isEmpty) {
      final scraped = await _scrapeAdaptationLinks(
        'https://myanimelist.net/manga/$mangaMalId',
        _animeLink,
      );
      if (scraped.isNotEmpty) ids = scraped;
    }
    ids ??= const [];
    // Only remember an empty answer if AniList actually answered.
    if (ids.isNotEmpty || reachedAniList) {
      _mangaAdaptations[mangaMalId] = ids;
      _scheduleSave();
    }
    return ids;
  }

  /// Other versions of the same story in the same medium, per AniList.
  /// Cached; empty if AniList can't be reached; never throws.
  Future<List<int>> otherVersionsOf(int id, {required bool anime}) async {
    final key = _key(id, anime);
    final cached = _otherVersions[key];
    if (cached != null) return cached;
    final ids = await _aniList.aniListOtherVersions(id, anime: anime);
    if (ids == null) return const [];
    _otherVersions[key] = ids;
    _scheduleSave();
    return ids;
  }

  Future<List<int>> _scrapeAdaptationLinks(String url, RegExp link) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: MalApi.imageHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];
      final html = res.body;
      final ids = <int>{};
      var from = 0;
      while (true) {
        final at = html.indexOf('Adaptation', from);
        if (at < 0) break;
        from = at + 10;
        // The linked title sits right next to its "Adaptation" label, in
        // both MAL's tile layout and its older table layout.
        final start = (at - 900).clamp(0, html.length);
        final end = (at + 900).clamp(0, html.length);
        final window = html.substring(start, end);
        int? best;
        var bestDist = 1 << 30;
        for (final m in link.allMatches(window)) {
          final dist = ((start + m.start) - at).abs();
          if (dist < bestDist) {
            bestDist = dist;
            best = int.tryParse(m.group(1)!);
          }
        }
        if (best != null) ids.add(best);
        if (ids.length >= 6) break;
      }
      return ids.toList();
    } catch (_) {
      return const [];
    }
  }
}
