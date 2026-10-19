import '../models/title_detail.dart';
import 'detail_store.dart';
import 'settings_store.dart';

/// A franchise: every title linked to the starting one through MAL
/// sequel/prequel relations. Spin-offs and side stories are not part of it.
class Franchise {
  final List<TitleDetail> members;
  const Franchise(this.members);

  /// Stable id for "have we shown this franchise already?": the lowest MAL id.
  int get key => members.map((m) => m.malId).reduce((a, b) => a < b ? a : b);

  /// Release status of the whole chain:
  /// anything still airing/publishing or announced → ongoing,
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
    return hiatus ? Completion.hiatus : Completion.completed;
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
    return members.isEmpty ? null : Franchise(members);
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
