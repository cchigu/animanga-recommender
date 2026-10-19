import '../models/catalog_title.dart';
import '../models/list_entry.dart';
import '../models/title_detail.dart';
import 'catalog_store.dart';
import 'detail_store.dart';
import 'franchise.dart';
import 'library_store.dart';
import 'mal_api.dart';
import 'picker.dart';
import 'settings_store.dart';

/// One line of the "Why wasn't this picked?" report.
/// [ok]: true = passes, false = this is why it's skipped, null = just info.
class ExplainStep {
  final bool? ok;
  final String text;
  const ExplainStep(this.ok, this.text);
}

/// Walks one title through the same rules the picker uses, step by step.
class Explainer {
  final _resolver = FranchiseResolver();

  /// The franchise entry the last explanation said the app would show.
  int? _lastEntryId;

  /// Titles of the current kind (catalog + your list) matching [query].
  List<CatalogTitle> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final anime = SettingsStore.instance.anime;
    final catalog = anime ? CatalogStore.instance.anime : CatalogStore.instance.manga;
    final list = anime ? LibraryStore.instance.anime : LibraryStore.instance.manga;

    final byId = <int, CatalogTitle>{};
    for (final t in catalog) {
      if (t.title.toLowerCase().contains(q) ||
          (t.englishTitle?.toLowerCase().contains(q) ?? false)) {
        byId[t.malId] = t;
      }
    }
    for (final e in list) {
      if (!byId.containsKey(e.malId) && e.title.toLowerCase().contains(q)) {
        byId[e.malId] = CatalogTitle(
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
    }
    final results = byId.values.toList()
      ..sort((a, b) => (b.malScore ?? 0).compareTo(a.malScore ?? 0));
    return results.take(15).toList();
  }

  Future<List<ExplainStep>> explain(CatalogTitle t) async {
    await DetailStore.instance.load();
    final steps = <ExplainStep>[];
    void add(bool? ok, String text) => steps.add(ExplainStep(ok, text));
    _lastEntryId = null;

    final s = SettingsStore.instance;
    final anime = s.anime;
    final listed = {
      for (final e in (anime
          ? LibraryStore.instance.anime
          : LibraryStore.instance.manga))
        e.malId: e,
    };
    final catalogById = {
      for (final c in (anime
          ? CatalogStore.instance.anime
          : CatalogStore.instance.manga))
        c.malId: c,
    };
    final active = s.activeFormats;
    final types = {for (final f in active) ...f.malTypes};
    final allowDonghua = active.contains(TitleFormat.donghua);
    UserStatus? statusOf(int id) => listed[id]?.userStatus;
    String yourStatus(int id) =>
        statusOf(id)?.label(anime: anime) ?? 'not on your list';

    add(null,
        'Settings: ${s.anime ? 'Anime' : 'Manga'} · ${s.pickMode.label} · '
        'first entry ${s.firstEntryOnly ? 'on' : 'off'} · '
        'status: ${s.completion.map((c) => c.label).join(', ')}'
        '${s.plannedOnly ? ' · Plan to ${anime ? 'Watch' : 'Read'} only' : ''}');

    // --- As a candidate -----------------------------------------------------
    final known = catalogById[t.malId];
    final st = statusOf(t.malId);
    if (known != null) {
      add(true, 'In the catalog${known.rank != null ? ' (MAL rank #${known.rank})' : ''}.');
    } else if (st == UserStatus.planned) {
      add(true, 'On your Plan list (outside the top ${CatalogStore.perKind}).');
    } else {
      add(s.firstEntryOnly ? null : false,
          'Not in the catalog (top ${CatalogStore.perKind} by MAL score) and '
          'not on your Plan list, so it can only be reached through another '
          'entry of its franchise.');
    }

    final listOk = st == null || st == UserStatus.planned;
    add(listOk, 'Your list: ${yourStatus(t.malId)}.'
        '${listOk ? '' : ' Titles you completed, are on, hold, or dropped are excluded.'}');

    if (s.plannedOnly) {
      final ok = st == UserStatus.planned;
      add(ok || s.firstEntryOnly,
          ok
              ? 'On your Plan list.'
              : s.firstEntryOnly
                  ? 'Not on your Plan list itself, but another planned entry '
                      'of its franchise can still lead to it.'
                  : 'Not on your Plan list, and "Only from Plan" is on.');
    }

    final formatOk = types.contains(t.mediaType);
    add(formatOk, 'Format: ${formatLabel(t.mediaType)}'
        '${formatOk ? '' : ' is switched off.'}');
    if (anime && !allowDonghua) {
      if (t.isDonghua) add(false, 'Chinese animation, and Donghua is off.');
    }

    if (s.pickMode != PickMode.random && (t.malScore ?? 0) <= 0) {
      add(false, 'No MAL score, and ${s.pickMode.label} needs one.');
    } else if (s.pickMode == PickMode.weighted &&
        Picker.weightFor(t.malScore) <= 0) {
      add(false, 'MAL score ${t.malScore} is 5 or lower, so its weight '
          '(score − 5)⁴ is zero.');
    } else {
      add(null, 'MAL score: ${t.malScore?.toStringAsFixed(2) ?? 'none'}.');
    }

    // --- Franchise ------------------------------------------------------------
    try {
      final Franchise? chain = s.firstEntryOnly
          ? await _resolver.mainChainOf(t.malId, anime: anime)
          : await _resolver.chainOf(t.malId, anime: anime);
      if (chain == null) {
        add(false, 'MyAnimeList has no details for this title.');
        return steps;
      }

      add(null, 'Franchise (sequel/prequel chain), earliest first:');
      final ordered = [...chain.members]
        ..sort((a, b) => a.sortDate.compareTo(b.sortDate));
      for (final m in ordered) {
        add(null, '   • ${m.title} — ${formatLabel(m.mediaType)}, '
            '${releaseLabel(m.releaseStatus)}, ${_span(m)}; '
            'you: ${yourStatus(m.malId)}');
      }

      if (chain.endedRecently) {
        add(null, 'Latest main entry ended within the past 6 years.');
        add(chain.fullyAdapted,
            'Fully adapted: ${chain.fullyAdapted ? 'yes' : 'no'}. '
            '${chain.adaptationNote ?? ''}');
      }
      final comp = chain.completion;
      final compOk = s.completion.contains(comp);
      add(compOk, 'Franchise counts as: ${comp.label}.'
          '${compOk ? '' : ' That status is not selected.'}');

      TitleDetail? entry;
      if (s.firstEntryOnly) {
        final blocked = chain.members.where((m) {
          final x = statusOf(m.malId);
          return x == UserStatus.current ||
              x == UserStatus.onHold ||
              x == UserStatus.dropped;
        }).toList();
        if (blocked.isNotEmpty) {
          add(false, 'You\'re watching, on hold, or dropped on '
              '"${blocked.first.title}", so the whole franchise is skipped.');
        }
        if (s.plannedOnly &&
            !chain.members.any((m) => statusOf(m.malId) == UserStatus.planned)) {
          add(false, 'No entry of this franchise is on your Plan list.');
        }
        for (final m in chain.releasedByDate) {
          if (!types.contains(m.mediaType)) continue;
          if (statusOf(m.malId) == UserStatus.completed) continue;
          entry = m;
          break;
        }
        _lastEntryId = entry?.malId;
        if (entry == null) {
          add(false, 'You\'ve completed every entry in the formats you have on.');
        } else {
          add(entry.malId == t.malId ? true : null,
              'First entry the app would show: "${entry.title}".');
        }
      } else {
        entry = chain.members.where((m) => m.malId == t.malId).firstOrNull;
      }

      if (entry != null &&
          FranchiseResolver.extraTypes.contains(entry.mediaType)) {
        final skip = await _resolver.isExtraOfWatchedSeries(
          entry.malId,
          anime: anime,
          chain: s.firstEntryOnly ? chain : null,
          watched: (id) {
            final x = statusOf(id);
            return x == UserStatus.completed || x == UserStatus.current;
          },
        );
        add(!skip, skip
            ? 'A side movie/OVA/special of a series you\'ve watched, so it\'s skipped.'
            : 'Not a skipped extra.');
      }
    } on MalException catch (e) {
      add(false, 'Couldn\'t check the franchise: ${e.message}');
    }

    try {
      // Check the entry the app would actually show.
      final shownId = _lastEntryId ?? t.malId;
      final alt = await _resolver.watchedAlternative(shownId,
          anime: anime,
          watched: (id) {
            final x = statusOf(id);
            return x == UserStatus.completed || x == UserStatus.current;
          },
          watchedTitles: {
            for (final e in listed.values)
              if (e.userStatus == UserStatus.completed ||
                  e.userStatus == UserStatus.current)
                FranchiseResolver.normalizeTitle(e.title):
                    (id: e.malId, title: e.title),
          });
      add(alt == null, alt == null
          ? 'No alternative version you\'ve already seen.'
          : 'You\'ve already seen the alternative version "$alt".');
    } on MalException catch (e) {
      add(null, 'Couldn\'t check alternative versions: ${e.message}');
    }

    if (!anime && !s.skipAdapted) {
      try {
        final started = {
          for (final e in LibraryStore.instance.anime)
            if (e.userStatus != UserStatus.planned) e.malId,
        };
        final check = await _resolver.unwatchedAnime(t.malId,
            seen: started.contains);
        final bool? ok = switch (check.status) {
          UnwatchedStatus.noAnime => null,
          UnwatchedStatus.watchedSome => null,
          UnwatchedStatus.unwatchedOk => s.includeUnwatchedAnime,
          UnwatchedStatus.unwatchedBlocked => false,
        };
        final suffix = check.status == UnwatchedStatus.unwatchedOk &&
                !s.includeUnwatchedAnime
            ? ' "Include manga with unwatched anime" is off.'
            : '';
        add(ok, '${check.note}$suffix');
      } on MalException catch (e) {
        add(null, 'Couldn\'t check unwatched anime: ${e.message}');
      }
    }

    if (!anime && s.skipAdapted) {
      try {
        const limit = SettingsStore.adaptedMinutes;
        final r = await _resolver.adaptationRuntime(t.malId);
        add(r.minutes < limit,
            'Anime adaptations: ${r.minutes} min combined'
            '${r.minutes >= limit ? ' (≥ $limit, and "Exclude adapted manga" is on)' : ''}. '
            '${r.note}');
      } on MalException catch (e) {
        add(null, 'Couldn\'t add up adaptations: ${e.message}');
      }
    }

    if (!anime) {
      try {
        final completedAnime = {
          for (final e in LibraryStore.instance.anime)
            if (e.userStatus == UserStatus.completed) e.malId,
        };
        final check = await _resolver.watchedFullAdaptation(
          t.malId,
          completed: completedAnime.contains,
        );
        if (check.coveredBy != null) {
          add(false, 'You completed the anime "${check.coveredBy}", which '
              'fully adapts this manga. ${check.note}');
        } else {
          add(true, 'Anime adaptation check: ${check.note}');
        }
      } on MalException catch (e) {
        add(null, 'Couldn\'t check anime adaptations: ${e.message}');
      }
    }

    final blockers = steps.where((x) => x.ok == false).length;
    add(blockers == 0,
        blockers == 0
            ? 'Verdict: eligible. If you didn\'t get it, higher-ranked titles '
                'came first in this pick mode, or it was already shown this '
                'session.'
            : 'Verdict: skipped because of the step${blockers > 1 ? 's' : ''} '
                'marked ✕.');
    return steps;
  }

  static String _span(TitleDetail m) {
    final a = m.startDate ?? '?';
    final b = m.endDate;
    return b == null || b == a ? a : '$a → $b';
  }
}
