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

  /// How [fullyAdapted] was decided, for the "Why wasn't this picked?" tool.
  String? adaptationNote;

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

  /// MAL's end date for a manga is often its last volume's release, months
  /// after the final chapter, so an anime that ended up to this long before
  /// still counts as covering it.
  static const adaptationSlack = Duration(days: 183);

  /// True if an anime ending on [animeEnd] can cover a source that ended on
  /// [sourceEnd].
  static bool coversSource(DateTime animeEnd, DateTime sourceEnd) =>
      !animeEnd.isBefore(sourceEnd.subtract(adaptationSlack));

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
      final (full, note) = await _isFullyAdapted(franchise);
      franchise.fullyAdapted = full;
      franchise.adaptationNote = note;
    }
    return franchise;
  }

  /// Heuristic for "the anime has adapted all of its source":
  /// - an anime original (nothing left to adapt), or
  /// - its source manga / light novel has finished, and the anime's last
  ///   main entry ended on or after the source's last release.
  /// Unknown or unreachable sources count as not fully adapted.
  /// Returns the verdict and a short note on how it was reached.
  Future<(bool, String)> _isFullyAdapted(Franchise f) async {
    final mains = f.mainByDate;
    if (mains.isEmpty) return (false, 'No main entries to compare.');
    final animeEnd = f.latestMainEnd;
    if (animeEnd == null) return (false, 'No end date on MAL.');
    if (mains.first.source == 'original') {
      return (true, 'Anime original (MAL), so nothing is left to adapt.');
    }

    String verdict(bool finished, DateTime? sourceEnd, String what) {
      if (!finished) return '$what is still running.';
      if (sourceEnd == null) return '$what has no end date.';
      return coversSource(animeEnd, sourceEnd)
          ? '$what ended ${_ymd(sourceEnd)}; the anime finished '
              '${_ymd(animeEnd)}, close enough to cover it.'
          : '$what ended ${_ymd(sourceEnd)}, well after the anime '
              '(${_ymd(animeEnd)}).';
    }

    // The work an anime adapts, judged against the anime's last episode.
    Future<(bool, String)?> judgeMalSources(Set<int> ids, String via) async {
      try {
        final sources = [
          for (final s in await Future.wait(
            ids.take(4).map((id) => _store.get(id, anime: false)),
          ))
            if (s != null) s,
        ];
        if (sources.isEmpty) return null;
        // The original work started first (an LN before its manga).
        sources.sort((a, b) => a.sortDate.compareTo(b.sortDate));
        final original = sources.first;
        final end = original.endedOn;
        final full =
            original.isFinished && end != null && coversSource(animeEnd, end);
        return (full, 'Source "${original.title}" ($via): '
            '${verdict(original.isFinished, end, 'it')}');
      } catch (_) {
        return null;
      }
    }

    // 1. MAL API adaptation links (often missing for anime).
    final apiIds = <int>{for (final m in mains) ...m.adaptedFrom};
    if (apiIds.isNotEmpty) {
      final r = await judgeMalSources(apiIds, 'MAL');
      if (r != null) return r;
    }

    // 2. AniList.
    final ani = await _store.aniListSource(mains.first.malId);
    if (ani != null) {
      if (ani.sourceType == 'ORIGINAL') {
        return (true, 'Anime original (AniList), so nothing is left to adapt.');
      }
      if (ani.hasSourceWork) {
        final full = ani.sourceFinished &&
            ani.sourceEnd != null &&
            coversSource(animeEnd, ani.sourceEnd!);
        return (full, 'Source "${ani.sourceTitle ?? '?'}" (AniList): '
            '${verdict(ani.sourceFinished, ani.sourceEnd, 'it')}');
      }
    }

    // 3. The "Adaptation" entry on the MAL anime page.
    final scraped = await _store.scrapeAdaptations(mains.first.malId);
    if (scraped.isNotEmpty) {
      final r = await judgeMalSources(scraped.toSet(), 'MAL page');
      if (r != null) return r;
    }

    return (false, 'Couldn\'t find the source work on MAL or AniList'
        '${ani == null ? ' (AniList unreachable)' : ' (source type: ${ani.sourceType ?? 'unknown'})'}.');
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';


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

  /// Manga only: checks whether the user has completed a finished anime
  /// that fully adapts [mangaId]: the manga has finished and the anime's
  /// last main entry ended no more than [adaptationSlack] before it.
  Future<AdaptationCheck> watchedFullAdaptation(
    int mangaId, {
    required bool Function(int animeMalId) completed,
  }) async {
    final adaptations = await _store.animeAdaptationsOf(mangaId);
    if (adaptations.isEmpty) {
      return const AdaptationCheck(null, 'No anime adaptation found.');
    }
    // Cheap check first: has the user completed any of them?
    final seen = [for (final id in adaptations) if (completed(id)) id];
    if (seen.isEmpty) {
      return AdaptationCheck(null, 'Has ${adaptations.length} anime '
          'adaptation${adaptations.length == 1 ? '' : 's'}, none completed '
          'by you.');
    }

    final manga = await _store.get(mangaId, anime: false);
    if (manga == null) {
      return const AdaptationCheck(null, 'MAL has no details for the manga.');
    }
    if (!manga.isFinished) {
      return const AdaptationCheck(null, 'The manga is still running, so no '
          'anime can cover all of it.');
    }
    final mangaEnd = manga.endedOn;
    if (mangaEnd == null) {
      return const AdaptationCheck(null, 'The manga has no end date on MAL.');
    }

    final notes = <String>[];
    for (final id in seen.take(3)) {
      final chain = await chainOf(id, anime: true);
      if (chain == null) continue;
      final mains = chain.mainByDate.where((m) => m.isReleased).toList();
      if (mains.isEmpty) continue;
      final name = mains.first.title;
      if (!mains.every((m) => m.isFinished)) {
        notes.add('"$name" is still airing.');
        continue;
      }
      final missing = mains.where((m) => !completed(m.malId)).toList();
      if (missing.isNotEmpty) {
        notes.add('You haven\'t completed "${missing.first.title}".');
        continue;
      }
      final animeEnd = chain.latestMainEnd;
      if (animeEnd == null) continue;
      if (!coversSource(animeEnd, mangaEnd)) {
        notes.add('"$name" ended ${_ymd(animeEnd)}, well before the manga '
            '(${_ymd(mangaEnd)}).');
        continue;
      }
      return AdaptationCheck(name, '"$name" ended ${_ymd(animeEnd)}; the '
          'manga ended ${_ymd(mangaEnd)}.');
    }
    return AdaptationCheck(
        null, notes.isEmpty ? 'Couldn\'t check the anime.' : notes.join(' '));
  }

  /// Manga only: combined runtime of every anime adapting [mangaId],
  /// including each one's sequels/prequels, released or announced. Stops
  /// adding once it reaches [stopAt] minutes.
  Future<AdaptationRuntime> adaptationRuntime(int mangaId,
      {int stopAt = 1 << 30}) async {
    final adaptations = await _store.animeAdaptationsOf(mangaId);
    if (adaptations.isEmpty) {
      return const AdaptationRuntime(0, 'No anime adaptation found.');
    }
    final counted = <int>{};
    final parts = <String>[];
    var total = 0;
    for (final id in adaptations.take(6)) {
      if (counted.contains(id)) continue;
      final chain = await chainOf(id, anime: true);
      if (chain == null) continue;
      for (final m in chain.members) {
        if (!counted.add(m.malId)) continue;
        final mins = m.estimatedMinutes;
        if (mins <= 0) continue;
        total += mins;
        parts.add('${m.title} (${m.mediaType.toUpperCase()}, '
            '${m.runtimeEstimated ? '~' : ''}$mins min)');
      }
      if (total >= stopAt) break;
    }
    final shown = parts.take(4).join(', ');
    final more = parts.length > 4 ? ' and ${parts.length - 4} more' : '';
    return AdaptationRuntime(
      total,
      parts.isEmpty
          ? 'Adaptations are only music videos, commercials or promos.'
          : '$shown$more',
    );
  }
}

class AdaptationRuntime {
  final int minutes;
  final String note;
  const AdaptationRuntime(this.minutes, this.note);
}

class AdaptationCheck {
  /// Title of the completed anime that covers the manga, if any.
  final String? coveredBy;
  final String note;
  const AdaptationCheck(this.coveredBy, this.note);
}
