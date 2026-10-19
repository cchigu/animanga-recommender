import 'dart:math';

import '../models/catalog_title.dart';
import '../models/list_entry.dart';
import 'catalog_store.dart';
import 'library_store.dart';
import 'settings_store.dart';

/// What one tap produced.
class PickResult {
  final CatalogTitle? title;

  /// How many titles were eligible under the current settings.
  final int poolSize;

  /// When nothing was eligible: which filter emptied the pool.
  final String? emptyReason;

  const PickResult(this.title, this.poolSize, [this.emptyReason]);
}

/// Picks one title according to the settings.
///
/// Milestone 5 handles exclusions, Plan to Watch/Read, format filters,
/// release status of the title itself, and the three pick modes.
/// Milestone 6 adds franchise logic (strict "completed" across the whole
/// sequel/prequel chain, and first major entry).
class Picker {
  Picker._();
  static final Picker instance = Picker._();

  final _rng = Random();

  /// Titles already shown this session, so "Pick another" moves on
  /// (most noticeable in Best score mode, which would otherwise repeat).
  final Set<int> _shownAnime = {};
  final Set<int> _shownManga = {};

  /// (score − 5)⁴, zero at or below 5 and for unscored titles.
  static double weightFor(double? score) {
    if (score == null || score <= 5) return 0;
    final d = score - 5;
    return d * d * d * d;
  }

  PickResult pick() {
    final settings = SettingsStore.instance;
    final library = LibraryStore.instance;
    final catalog = CatalogStore.instance;
    final anime = settings.anime;
    final kindName = anime ? 'anime' : 'manga';

    // Everything on the user's list, by MAL id.
    final listed = {
      for (final e in (anime ? library.anime : library.manga)) e.malId: e,
    };

    // Pool: the catalog, plus planned titles that aren't in the top ranks.
    final pool = <CatalogTitle>[...(anime ? catalog.anime : catalog.manga)];
    final inCatalog = {for (final t in pool) t.malId};
    for (final e in listed.values) {
      if (e.userStatus == UserStatus.planned && !inCatalog.contains(e.malId)) {
        pool.add(_fromListEntry(e));
      }
    }
    if (pool.isEmpty) {
      return PickResult(
        null,
        0,
        'The catalog is still empty. Open Settings to check its progress.',
      );
    }

    // Each step narrows the pool; remember which one empties it.
    var current = pool;
    String? reason;
    void step(String name, bool Function(CatalogTitle) keep) {
      if (reason != null) return;
      current = current.where(keep).toList();
      if (current.isEmpty) reason = name;
    }

    // 7. Never anything already completed / watching / on hold / dropped.
    step('Every $kindName left is already on your list', (t) {
      final s = listed[t.malId]?.userStatus;
      return s == null || s == UserStatus.planned;
    });

    // 6. Plan to Watch / Read only.
    if (settings.plannedOnly) {
      step('Nothing on your ${anime ? 'Plan to Watch' : 'Plan to Read'} list '
          'matches', (t) => listed[t.malId]?.userStatus == UserStatus.planned);
    }

    // 4/5. Formats.
    final active = settings.activeFormats;
    final types = {for (final f in active) ...f.malTypes};
    final allowDonghua = active.contains(TitleFormat.donghua);
    step('No titles match the formats you have on',
        (t) => types.contains(t.mediaType) && (allowDonghua || !t.isDonghua));

    // 1. Release status (of this title; the whole chain comes in Milestone 6).
    step('No titles match the release status you picked', (t) {
      final c = _completionOf(t);
      return c != null && settings.completion.contains(c);
    });

    // Score-based modes need a score.
    if (settings.pickMode != PickMode.random) {
      step('None of the matching titles have a MAL score yet',
          (t) => (t.malScore ?? 0) > 0);
    }

    if (reason != null) return PickResult(null, 0, '$reason.');

    final eligible = current;
    final shown = anime ? _shownAnime : _shownManga;
    var fresh = [for (final t in eligible) if (!shown.contains(t.malId)) t];
    if (fresh.isEmpty) {
      // Shown everything once; start over.
      shown.clear();
      fresh = eligible;
    }

    final chosen = switch (settings.pickMode) {
      PickMode.bestScore => _best(fresh),
      PickMode.weighted => _weighted(fresh),
      PickMode.random => fresh[_rng.nextInt(fresh.length)],
    };
    shown.add(chosen.malId);
    return PickResult(chosen, eligible.length);
  }

  CatalogTitle _best(List<CatalogTitle> list) {
    var best = list.first;
    for (final t in list) {
      if ((t.malScore ?? 0) > (best.malScore ?? 0)) best = t;
    }
    return best;
  }

  CatalogTitle _weighted(List<CatalogTitle> list) {
    final weights = [for (final t in list) weightFor(t.malScore)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return list[_rng.nextInt(list.length)];
    var r = _rng.nextDouble() * total;
    for (var i = 0; i < list.length; i++) {
      r -= weights[i];
      if (r <= 0) return list[i];
    }
    return list.last;
  }

  /// Maps MAL's release status to the setting's three options.
  /// Not-yet-released titles return null and are never picked.
  static Completion? _completionOf(CatalogTitle t) {
    switch (t.releaseStatus) {
      case 'finished_airing':
      case 'finished':
        return Completion.completed;
      case 'currently_airing':
      case 'currently_publishing':
        return Completion.ongoing;
      case 'on_hiatus':
      case 'discontinued':
        return Completion.hiatus;
      default:
        return null;
    }
  }

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
