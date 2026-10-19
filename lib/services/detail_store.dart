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
  static const _version = 2;
  static const _malBase = 'https://api.myanimelist.net/v2';
  static const _maxParallel = 3;

  final http.Client _client = http.Client();
  final CatalogApi _aniList = CatalogApi();

  final Map<String, TitleDetail> _details = {};
  final Map<String, AniListInfo> _aniInfo = {};
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
        'status,start_date,end_date,${anime ? 'related_anime' : 'related_manga'}';
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
}
