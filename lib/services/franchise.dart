import '../models/title_detail.dart';
import 'detail_store.dart';
import 'settings_store.dart';

/// A franchise: every title linked to the starting one through MAL
/// sequel/prequel relations. Spin-offs and side stories are not part of it.
class Franchise {
  final List<TitleDetail> members;
  Franchise(this.members);

  /// Set by [FranchiseResolver]: the anime has fully adapted its source
  /// (or is an anime original), so a recent ending doesn't mean more is
  /// coming.
  bool fullyAdapted = false;

  /// Stable id for "have we shown this franchise already?": the lowest MAL id.
  int get key => members.map((m) => m.malId).reduce((a, b) => a < b ? a : b);

  /// An anime franchise whose latest main entry ended this recently counts
  /// as ongoing, since a sequel is likely even if none is announced yet.
  static const recentEndWindow = Duration(days: 6 * 365 + 2);

  /// Formats that don't count as "the latest entry" for that rule.
  static const _minorTypes = {'special', 'tv_special', 'music', 'cm', 'pv'};

  /// Release status of the whole chain:
  /// anything still airing/publishing or announced → ongoing,
  /// otherwise (anime) the latest entry ended within 6 years and the source
  /// isn't fully adapted → ongoing,
  /// otherwise anything on hiatus/discontinued → hiatus,
  /// otherwise → completed.
  Completion get completion {
    var hiatus = false;
    for (final m in members) {
      switch (m.releaseStatus) {
        case 'currently_airing':
        case 'currently_publishing':
        case 'not_yet_aired':
        case 'not_yet_published':
          return Completion.ongoing;
        case 'on_hiatus':
        case 'discontinued':
          hiatus = true;
      }
    }
    if (endedRecently && !fullyAdapted) return Completion.ongoing;
    return hiatus ? Completion.hiatus : Completion.completed;
  }

  /// True for anime whose latest TV/ONA/movie/OVA entry ended in the last
  /// 6 years.
  bool get endedRecently {
    if (members.isEmpty || !members.first.isAnime) return false;
    final latest = latestMainEnd;
    if (latest == null) return false;
    return DateTime.now().difference(latest) < recentEndWindow;
  }

  /// Main entries (no recaps/specials/music), earliest first.
  List<TitleDetail> get mainByDate =>
      [for (final m in members) if (!_minorTypes.contains(m.mediaType)) m]
        ..sort((a, b) => a.sortDate.compareTo(b.sortDate));

  /// When the last main entry ended.
  DateTime? get latestMainEnd {
    DateTime? latest;
    for (final m in mainByDate) {
      final end = m.endedOn;
      if (end != null && (latest == null || end.isAfter(latest))) {
        latest = end;
      }
    }
    return latest;
  }

  /// Released members, earliest first.
  List<TitleDetail> get releasedByDate =>
      [for (final m in members) if (m.isReleased) m]
        ..sort((a, b) => a.sortDate.compareTo(b.sortDate));
}

class FranchiseResolver {
  static const _chainTypes = {'sequel', 'prequel'};

  /// Formats that count as extras rather than main entries.
  static const extraTypes = {
    'movie', 'ova', 'special', 'tv_special', 'music', 'cm', 'pv',
  };

  /// Links from an extra to the series it belongs to (everything except
  /// sequel/prequel, and "character", which only means shared characters).
  static const _belongsToTypes = {
    'parent_story', 'side_story', 'spin_off', 'alternative_version',
    'alternative_setting', 'summary', 'full_story', 'other',
  };

  /// Largest chain we'll walk; long-running franchises fit comfortably.
  static const _maxMembers = 60;

  final DetailStore _store;
  FranchiseResolver([DetailStore? store])
      : _store = store ?? DetailStore.instance;

  /// Walks sequel/prequel links out from [id], one "ring" at a time.
  Future<Franchise?> chainOf(int id, {required bool anime}) async {
    final seen = <int>{id};
    final members = <TitleDetail>[];
    var frontier = [id];
    while (frontier.isNotEmpty && members.length < _maxMembers) {
      final fetched = await Future.wait(
        frontier.map((i) => _store.get(i, anime: anime)),
      );
      final next = <int>[];
      for (final d in fetched) {
        if (d == null) continue;
        members.add(d);
        for (final r in d.relatedOfType(_chainTypes)) {
          if (seen.add(r)) next.add(r);
        }
      }
      frontier = next;
    }
    if (members.isEmpty) return null;
    final franchise = Franchise(members);
    if (franchise.endedRecently) {
      franchise.fullyAdapted = await _isFullyAdapted(franchise);
    }
    return franchise;
  }

  /// Heuristic for "the anime has adapted all of its source":
  /// - an anime original (nothing left to adapt), or
  /// - its source manga / light novel has finished, and the anime's last
  ///   main entry ended on or after the source's last release.
  /// Unknown or unreachable sources count as not fully adapted.
  Future<bool> _isFullyAdapted(Franchise f) async {
    final mains = f.mainByDate;
    if (mains.isEmpty) return false;
    if (mains.first.source == 'original') return true;

    final sourceIds = <int>{for (final m in mains) ...m.adaptedFrom};
    if (sourceIds.isEmpty) return false;

    try {
      final sources = [
        for (final s in await Future.wait(
          sourceIds.take(4).map((id) => _store.get(id, anime: false)),
        ))
          if (s != null) s,
      ];
      if (sources.isEmpty) return false;
      // The original work is the one that started first (an LN before its
      // manga adaptation, for example).
      sources.sort((a, b) => a.sortDate.compareTo(b.sortDate));
      final original = sources.first;
      if (!original.isFinished) return false;

      final sourceEnd = original.endedOn;
      final animeEnd = f.latestMainEnd;
      if (sourceEnd == null || animeEnd == null) return false;
      return !animeEnd.isBefore(sourceEnd);
    } catch (_) {
      return false;
    }
  }

  /// Like [chainOf], but if the chain is a side story (e.g. an OVA whose
  /// parent lists it as a side story), returns the parent's chain instead.
  /// Spin-offs stay their own franchise.
  Future<Franchise?> mainChainOf(int id, {required bool anime}) async {
    final chain = await chainOf(id, anime: anime);
    if (chain == null) return null;

    final ids = {for (final m in chain.members) m.malId};
    for (final m in chain.members) {
      for (final parentId in m.relatedOfType({'parent_story'})) {
        if (ids.contains(parentId)) continue;
        final parent = await _store.get(parentId, anime: anime);
        if (parent == null) continue;
        final isSideStory = parent.relations.any(
          (r) => r.id == m.malId && r.type == 'side_story',
        );
        if (isSideStory) {
          return await chainOf(parentId, anime: anime) ?? chain;
        }
      }
    }
    return chain;
  }

  /// True for a movie / OVA / special that isn't a sequel or prequel of a
  /// main entry (its own sequel/prequel chain is all extras), when the user
  /// has already completed or is watching a main entry it belongs to.
  /// [chain] is the title's sequel/prequel chain if already known.
  Future<bool> isExtraOfWatchedSeries(
    int id, {
    required bool anime,
    required bool Function(int malId) watched,
    Franchise? chain,
  }) async {
    final own = chain ?? await chainOf(id, anime: anime);
    if (own == null) return false;
    final self = own.members.where((m) => m.malId == id).firstOrNull;
    if (self == null || !extraTypes.contains(self.mediaType)) return false;

    // A sequel/prequel of a main entry is part of the main story: keep it.
    if (own.members.any((m) => !extraTypes.contains(m.mediaType))) {
      return false;
    }

    final ownIds = {for (final m in own.members) m.malId};
    final related = <int>{
      for (final m in own.members)
        for (final r in m.relatedOfType(_belongsToTypes))
          if (!ownIds.contains(r)) r,
    };
    for (final r in related.take(6)) {
      final series = await chainOf(r, anime: anime);
      if (series == null) continue;
      final mains = series.members
          .where((m) => !extraTypes.contains(m.mediaType));
      if (mains.any((m) => watched(m.malId))) return true;
    }
    return false;
  }
}
