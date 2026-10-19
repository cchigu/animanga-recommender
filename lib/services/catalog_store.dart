import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/catalog_title.dart';
import 'catalog_api.dart';
import 'mal_api.dart';

/// The candidate pool: MAL's top-ranked anime and manga, enriched with
/// AniList country of origin and cover color. Saved on the phone, rebuilt
/// weekly, and filled in the background so the app stays usable meanwhile.
class CatalogStore extends ChangeNotifier {
  CatalogStore._();
  static final CatalogStore instance = CatalogStore._();

  /// How many top-ranked titles of each kind go in the pool.
  static const perKind = 5000;
  static const _pageSize = 500;
  static const refreshAfter = Duration(days: 7);
  static const _file = 'catalog.json';

  final CatalogApi _api = CatalogApi();

  List<CatalogTitle> anime = const [];
  List<CatalogTitle> manga = const [];
  DateTime? rankingsUpdated;

  bool busy = false;
  String? phase; // what's happening right now, for the Settings card
  double progress = 0; // 0..1 for the current phase
  String? error;

  bool get isEmpty => anime.isEmpty && manga.isEmpty;
  int get total => anime.length + manga.length;
  int get detailsDone =>
      anime.where((t) => t.anilistChecked).length +
      manga.where((t) => t.anilistChecked).length;
  int get donghuaCount => anime.where((t) => t.isDonghua).length;
  int get colorCount =>
      anime.where((t) => t.coverColor != null).length +
      manga.where((t) => t.coverColor != null).length;

  Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  Future<void> load() async {
    try {
      final f = await _path();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final updated = j['updated'] as int?;
      rankingsUpdated =
          updated == null ? null : DateTime.fromMillisecondsSinceEpoch(updated);
      anime = [
        for (final e in j['anime'] as List)
          CatalogTitle.fromJson(e as Map<String, dynamic>)
      ];
      manga = [
        for (final e in j['manga'] as List)
          CatalogTitle.fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      anime = const [];
      manga = const [];
      rankingsUpdated = null;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final f = await _path();
    await f.writeAsString(jsonEncode({
      'updated': rankingsUpdated?.millisecondsSinceEpoch,
      'anime': [for (final t in anime) t.toJson()],
      'manga': [for (final t in manga) t.toJson()],
    }));
  }

  /// Called at startup: builds the catalog if missing or a week old,
  /// otherwise just finishes any AniList details still missing.
  Future<void> ensureFresh() async {
    final last = rankingsUpdated;
    if (isEmpty ||
        last == null ||
        DateTime.now().difference(last) > refreshAfter) {
      await rebuild();
    } else {
      await _enrich();
    }
  }

  /// Re-downloads MAL's rankings (keeping AniList data already fetched),
  /// then fills in AniList details for anything new.
  Future<void> rebuild() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      for (final isAnime in [true, false]) {
        final previous = {
          for (final t in (isAnime ? anime : manga)) t.malId: t,
        };
        final fresh = <CatalogTitle>[];
        for (var offset = 0; offset < perKind; offset += _pageSize) {
          _setPhase(
            'Loading top ${isAnime ? 'anime' : 'manga'} from MyAnimeList',
            offset / perKind,
          );
          final page = await _api.malRankingPage(
            anime: isAnime,
            offset: offset,
            limit: _pageSize,
          );
          fresh.addAll(
            CatalogApi.parseRanking(page, anime: isAnime, previous: previous),
          );
          if (page.length < _pageSize) break; // ran out of ranked titles
        }
        // De-duplicate, keeping the first (best ranked) copy.
        final seen = <int>{};
        final list = [for (final t in fresh) if (seen.add(t.malId)) t];
        if (isAnime) {
          anime = list;
        } else {
          manga = list;
        }
      }
      rankingsUpdated = DateTime.now();
      await _save();
    } on MalException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Catalog update failed: $e';
    } finally {
      busy = false;
      phase = null;
      notifyListeners();
    }
    if (error == null) await _enrich();
  }

  /// Asks AniList about every title not checked yet, 50 at a time.
  Future<void> _enrich() async {
    if (busy) return;
    final pending = <CatalogTitle>[
      ...anime.where((t) => !t.anilistChecked),
      ...manga.where((t) => !t.anilistChecked),
    ];
    if (pending.isEmpty) return;

    busy = true;
    error = null;
    notifyListeners();

    final totalPending = pending.length;
    var done = 0;
    var sinceSave = 0;
    try {
      for (final isAnime in [true, false]) {
        final ids = [
          for (final t in pending)
            if (t.isAnime == isAnime) t.malId
        ];
        for (var i = 0; i < ids.length; i += CatalogApi.aniListBatch) {
          final batch = ids.sublist(
            i,
            (i + CatalogApi.aniListBatch).clamp(0, ids.length),
          );
          _setPhase(
            'Getting details from AniList',
            done / totalPending,
          );
          final info = await _api.aniListBatchInfo(batch, anime: isAnime);
          _apply(batch.toSet(), info, anime: isAnime);
          done += batch.length;

          if (++sinceSave >= 5) {
            sinceSave = 0;
            await _save();
          }
          await Future.delayed(_api.aniListDelay);
        }
      }
    } on MalException catch (e) {
      error = '${e.message} Details continue next time the app opens.';
    } catch (e) {
      error = 'AniList details failed: $e';
    } finally {
      await _save();
      busy = false;
      phase = null;
      notifyListeners();
    }
  }

  void _apply(Set<int> asked, Map<int, AniListInfo> info,
      {required bool anime}) {
    final list = anime ? this.anime : manga;
    final updated = [
      for (final t in list)
        if (asked.contains(t.malId))
          t.withAniList(
            country: info[t.malId]?.country,
            coverColor: info[t.malId]?.coverColor,
          )
        else
          t
    ];
    if (anime) {
      this.anime = updated;
    } else {
      manga = updated;
    }
  }

  void _setPhase(String text, double value) {
    phase = text;
    progress = value.clamp(0.0, 1.0);
    notifyListeners();
  }
}
