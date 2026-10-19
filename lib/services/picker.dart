import 'dart:math';

import '../models/catalog_title.dart';
import '../models/list_entry.dart';
import '../models/title_detail.dart';
import 'catalog_store.dart';
import 'detail_store.dart';
import 'franchise.dart';
import 'library_store.dart';
import 'mal_api.dart';
import 'settings_store.dart';

/// What one tap produced.
class PickResult {
  final CatalogTitle? title;

  /// How many candidate titles the settings allowed.
  final int poolSize;

  /// When nothing could be picked: why.
  final String? emptyReason;

  const PickResult(this.title, this.poolSize, [this.emptyReason]);
}

/// Picks one title according to the settings.
///
/// 1. Builds the candidate list (catalog + planned titles, minus anything
///    already on the user's list, filtered by format/status/score).
/// 2. Orders it by the pick mode: best score first, weighted-random order
///    by (score − 5)⁴, or a plain shuffle.
/// 3. Walks that order, checking each candidate's franchise (strict
///    "completed", first major entry, Plan to Watch/Read across the chain),
///    and returns the first one that passes.
class Picker {
  Picker._();
  static final Picker instance = Picker._();

  /// Give up after this many candidates or this long.
  static const _maxTries = 80;
  static const _timeBudget = Duration(seconds: 40);

  final _rng = Random();
  final _resolver = FranchiseResolver();

  /// Shown this session, so "Pick another" moves on.
  final Set<int> _shownAnime = {};
  final Set<int> _shownManga = {};
  final Set<int> _shownFranchisesAnime = {};
  final Set<int> _shownFranchisesManga = {};

  /// (score − 5)⁴, zero at or below 5 and for unscored titles.
  static double weightFor(double? score) {
    if (score == null || score <= 5) return 0;
    final d = score - 5;
    return d * d * d * d;
  }

  Future<PickResult> pick() async {
    await DetailStore.instance.load();
    final first = await _pickOnce();
    if (first.title != null || !first.allShown) return first.result;
    // Everything eligible was already shown this session: start over.
    _shown(SettingsStore.instance.anime).clear();
    _shownFranchises(SettingsStore.instance.anime).clear();
    return (await _pickOnce()).result;
  }

  Set<int> _shown(bool anime) => anime ? _shownAnime : _shownManga;
  Set<int> _shownFranchises(bool anime) =>
      anime ? _shownFranchisesAnime : _shownFranchisesManga;

  Future<_Attempt> _pickOnce() async {
    final settings = SettingsStore.instance;
    final library = LibraryStore.instance;
    final catalog = CatalogStore.instance;
    final anime = settings.anime;
    final kindName = anime ? 'anime' : 'manga';

    final listed = {
      for (final e in (anime ? library.anime : library.manga)) e.malId: e,
    };
    final catalogById = {
      for (final t in (anime ? catalog.anime : catalog.manga)) t.malId: t,
    };

    // Pool: the catalog, plus planned titles that aren't in the top ranks.
    final pool = <CatalogTitle>[...catalogById.values];
    for (final e in listed.values) {
      if (e.userStatus == UserStatus.planned &&
          !catalogById.containsKey(e.malId)) {
        pool.add(_fromListEntry(e));
      }
    }
    if (pool.isEmpty) {
      return _Attempt.empty(
          'The catalog is still empty. Open Settings to check its progress.');
    }

    final active = settings.activeFormats;
    final types = {for (final f in active) ...f.malTypes};
    final allowDonghua = active.contains(TitleFormat.donghua);
    final firstOnly = settings.firstEntryOnly;
    final ctx = _Context(
      anime: anime,
      listed: listed,
      catalogById: catalogById,
      types: types,
      allowDonghua: allowDonghua,
      settings: settings,
    );

    // ---- 1. Candidates ----------------------------------------------------
    var current = pool;
    String? reason;
    void step(String name, bool Function(CatalogTitle) keep) {
      if (reason != null) return;
      current = current.where(keep).toList();
      if (current.isEmpty) reason = name;
    }

    step('Every $kindName left is already on your list', (t) {
      final s = listed[t.malId]?.userStatus;
      return s == null || s == UserStatus.planned;
    });

    if (settings.plannedOnly) {
      step('Nothing on your ${anime ? 'Plan to Watch' : 'Plan to Read'} list '
          'matches', (t) => listed[t.malId]?.userStatus == UserStatus.planned);
    }

    // With "first entry only", a planned title of a switched-off format can
    // still lead to its franchise's first entry, so it stays a candidate.
    step('No titles match the formats you have on', (t) {
      if (!allowDonghua && t.isDonghua) return false;
      if (types.contains(t.mediaType)) return true;
      return firstOnly && listed[t.malId]?.userStatus == UserStatus.planned;
    });

    // A franchise is at least as "unfinished" as each of its titles.
    step('No titles match the release status you picked', (t) {
      final own = _levelOf(t.releaseStatus);
      if (own == null) return false; // not released yet
      return settings.completion.any((c) => _level(c) >= own);
    });

    if (settings.pickMode != PickMode.random) {
      step('None of the matching titles have a MAL score yet',
          (t) => (t.malScore ?? 0) > 0);
    }
    if (reason != null) return _Attempt.empty('$reason.');

    // ---- 2. Order ---------------------------------------------------------
    final ordered = _order(current, settings.pickMode);

    // ---- 3. Check franchises in that order --------------------------------
    final shown = _shown(anime);
    final shownFranchises = _shownFranchises(anime);
    final tried = <int>{}; // franchises already rejected this tap
    final started = DateTime.now();
    var tries = 0;
    var skippedAsShown = 0;
    String? lastError;

    for (final cand in ordered) {
      if (tries >= _maxTries ||
          DateTime.now().difference(started) > _timeBudget) {
        break;
      }
      if (shown.contains(cand.malId)) {
        skippedAsShown++;
        continue;
      }
      tries++;
      try {
        final outcome = await _resolve(cand, ctx, tried);
        if (outcome.franchiseKey != null &&
            shownFranchises.contains(outcome.franchiseKey) &&
            firstOnly) {
          skippedAsShown++;
          continue;
        }
        final entry = outcome.entry;
        if (entry == null) {
          if (outcome.franchiseKey != null) tried.add(outcome.franchiseKey!);
          continue;
        }
        if (shown.contains(entry.malId)) {
          skippedAsShown++;
          continue;
        }
        shown.add(entry.malId);
        if (outcome.franchiseKey != null) {
          shownFranchises.add(outcome.franchiseKey!);
        }
        return _Attempt(PickResult(entry, current.length));
      } on MalException catch (e) {
        lastError = e.message;
        // One network hiccup shouldn't end the search; three in a row will.
        if (tries >= 3 && tried.isEmpty) break;
      }
    }

    if (lastError != null && tries > 0 && tried.isEmpty) {
      return _Attempt.empty(lastError);
    }
    return _Attempt.empty(
      tries == 0 || skippedAsShown > tries
          ? 'You\'ve seen every match this session.'
          : 'Checked $tries franchises and none fit all your settings. '
              'Your release status or Plan to Watch/Read settings may be '
              'very strict.',
      allShown: skippedAsShown > 0,
    );
  }

  /// Checks one candidate against the franchise rules.
  Future<_Outcome> _resolve(
    CatalogTitle cand,
    _Context ctx,
    Set<int> tried,
  ) async {
    final s = ctx.settings;
    final needStatus = s.completion.length < Completion.values.length;

    // ---- First entry off: the candidate itself is the pick ----------------
    if (!s.firstEntryOnly) {
      int? key;
      if (needStatus) {
        final chain = await _resolver.chainOf(cand.malId, anime: ctx.anime);
        if (chain == null) return const _Outcome(null, null);
        key = chain.key;
        if (!s.completion.contains(chain.completion)) {
          return _Outcome(null, key);
        }
      }
      if (!await _passesDonghua(cand, ctx)) return _Outcome(null, key);
      return _Outcome(await _withColor(cand, ctx), key);
    }

    // ---- First entry on: work out the franchise's entry ------------------
    final chain = await _resolver.mainChainOf(cand.malId, anime: ctx.anime);
    if (chain == null) return const _Outcome(null, null);
    final key = chain.key;
    if (tried.contains(key)) return _Outcome(null, key);

    if (!s.completion.contains(chain.completion)) return _Outcome(null, key);

    // Watching, on hold, or dropped anywhere in the franchise: skip it.
    UserStatus? statusOf(TitleDetail m) => ctx.listed[m.malId]?.userStatus;
    if (chain.members.any((m) {
      final st = statusOf(m);
      return st == UserStatus.current ||
          st == UserStatus.onHold ||
          st == UserStatus.dropped;
    })) {
      return _Outcome(null, key);
    }

    if (s.plannedOnly &&
        !chain.members.any((m) => statusOf(m) == UserStatus.planned)) {
      return _Outcome(null, key);
    }

    // Earliest released entry in a switched-on format that isn't completed.
    // Everything before it in that order is completed by construction.
    TitleDetail? entry;
    for (final m in chain.releasedByDate) {
      if (!ctx.types.contains(m.mediaType)) continue;
      if (statusOf(m) == UserStatus.completed) continue;
      entry = m;
      break;
    }
    if (entry == null) return _Outcome(null, key);

    final title = _fromDetail(entry, ctx);
    if (!await _passesDonghua(title, ctx)) return _Outcome(null, key);
    return _Outcome(await _withColor(title, ctx), key);
  }

  /// False if Donghua is switched off and this is Chinese animation.
  Future<bool> _passesDonghua(CatalogTitle t, _Context ctx) async {
    if (!ctx.anime || ctx.allowDonghua) return true;
    if (t.anilistChecked) return !t.isDonghua;
    final info = await DetailStore.instance.aniList(t.malId, anime: true);
    return info?.country != 'CN';
  }

  /// Adds AniList country/color for titles outside the catalog.
  Future<CatalogTitle> _withColor(CatalogTitle t, _Context ctx) async {
    if (t.anilistChecked) return t;
    final info = await DetailStore.instance.aniList(t.malId, anime: ctx.anime);
    if (info == null) return t;
    return t.withAniList(country: info.country, coverColor: info.coverColor);
  }

  CatalogTitle _fromDetail(TitleDetail d, _Context ctx) {
    final known = ctx.catalogById[d.malId];
    if (known != null) return known;
    return CatalogTitle(
      malId: d.malId,
      isAnime: d.isAnime,
      title: d.title,
      englishTitle: d.englishTitle,
      mediaType: d.mediaType,
      releaseStatus: d.releaseStatus,
      malScore: d.malScore,
      startDate: d.startDate,
      pictureUrl: d.pictureUrl,
    );
  }

  List<CatalogTitle> _order(List<CatalogTitle> list, PickMode mode) {
    switch (mode) {
      case PickMode.bestScore:
        return [...list]
          ..sort((a, b) => (b.malScore ?? 0).compareTo(a.malScore ?? 0));
      case PickMode.random:
        return [...list]..shuffle(_rng);
      case PickMode.weighted:
        // Weighted order without replacement (Efraimidis–Spirakis):
        // key = u^(1/w); sorting by key descending gives a random order in
        // which each title comes first with probability w / Σw.
        final keyed = <(double, CatalogTitle)>[];
        for (final t in list) {
          final w = weightFor(t.malScore);
          if (w <= 0) continue;
          final u = _rng.nextDouble();
          keyed.add((pow(u == 0 ? 1e-12 : u, 1 / w).toDouble(), t));
        }
        keyed.sort((a, b) => b.$1.compareTo(a.$1));
        return [for (final k in keyed) k.$2];
    }
  }

  /// completed 0 < hiatus 1 < ongoing 2; null if not released yet.
  static int? _levelOf(String status) {
    switch (status) {
      case 'finished_airing':
      case 'finished':
        return 0;
      case 'on_hiatus':
      case 'discontinued':
        return 1;
      case 'currently_airing':
      case 'currently_publishing':
        return 2;
      default:
        return null;
    }
  }

  static int _level(Completion c) => switch (c) {
        Completion.completed => 0,
        Completion.hiatus => 1,
        Completion.ongoing => 2,
      };

  static CatalogTitle _fromListEntry(ListEntry e) => CatalogTitle(
        malId: e.malId,
        isAnime: e.isAnime,
        title: e.title,
        mediaType: e.mediaType,
        releaseStatus: e.releaseStatus,
        malScore: e.malScore,
        startDate: e.startDate,
        pictureUrl: e.pictureUrl,
      );
}

class _Context {
  final bool anime;
  final Map<int, ListEntry> listed;
  final Map<int, CatalogTitle> catalogById;
  final Set<String> types;
  final bool allowDonghua;
  final SettingsStore settings;

  const _Context({
    required this.anime,
    required this.listed,
    required this.catalogById,
    required this.types,
    required this.allowDonghua,
    required this.settings,
  });
}

class _Outcome {
  final CatalogTitle? entry;
  final int? franchiseKey;
  const _Outcome(this.entry, this.franchiseKey);
}

class _Attempt {
  final PickResult result;
  final bool allShown;
  const _Attempt(this.result, {this.allShown = false});
  _Attempt.empty(String reason, {this.allShown = false})
      : result = PickResult(null, 0, reason);
  CatalogTitle? get title => result.title;
}

/// Friendly names for MAL's codes.
String formatLabel(String mediaType) => const {
      'tv': 'TV',
      'movie': 'Movie',
      'ova': 'OVA',
      'ona': 'ONA',
      'special': 'Special',
      'tv_special': 'TV Special',
      'music': 'Music',
      'manga': 'Manga',
      'one_shot': 'One-shot',
      'manhwa': 'Manhwa',
      'manhua': 'Manhua',
      'light_novel': 'Light novel',
      'novel': 'Novel',
      'doujinshi': 'Doujinshi',
      'oel': 'OEL',
    }[mediaType] ??
    mediaType;

String releaseLabel(String status) => const {
      'finished_airing': 'Finished airing',
      'currently_airing': 'Airing',
      'not_yet_aired': 'Not yet aired',
      'finished': 'Finished',
      'currently_publishing': 'Publishing',
      'on_hiatus': 'On hiatus',
      'discontinued': 'Discontinued',
      'not_yet_published': 'Not yet published',
    }[status] ??
    status;
