import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_title.dart';
import '../secrets.dart';
import 'mal_api.dart';

/// AniList data for one MAL id.
class AniListInfo {
  final String? country;
  final int? coverColor;
  const AniListInfo(this.country, this.coverColor);
}

/// The source an anime adapts, according to AniList.
class AniListSource {
  /// AniList's source type: ORIGINAL, MANGA, LIGHT_NOVEL, WEB_NOVEL...
  final String? sourceType;

  /// The source work itself, when AniList links one.
  final bool hasSourceWork;
  final bool sourceFinished;
  final DateTime? sourceEnd;
  final String? sourceTitle;

  const AniListSource({
    this.sourceType,
    this.hasSourceWork = false,
    this.sourceFinished = false,
    this.sourceEnd,
    this.sourceTitle,
  });

  Map<String, dynamic> toJson() => {
        'st': sourceType,
        'has': hasSourceWork,
        'fin': sourceFinished,
        'end': sourceEnd?.millisecondsSinceEpoch,
        'tt': sourceTitle,
      };

  factory AniListSource.fromJson(Map<String, dynamic> j) => AniListSource(
        sourceType: j['st'] as String?,
        hasSourceWork: j['has'] as bool? ?? false,
        sourceFinished: j['fin'] as bool? ?? false,
        sourceEnd: j['end'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        sourceTitle: j['tt'] as String?,
      );
}

/// Fetches the candidate pool: MAL's score ranking, then AniList details.
class CatalogApi {
  static const _malBase = 'https://api.myanimelist.net/v2';
  static const _aniList = 'https://graphql.anilist.co';
  static const _timeout = Duration(seconds: 25);

  /// AniList takes up to 50 ids per request.
  static const aniListBatch = 50;

  final http.Client _client;
  CatalogApi([http.Client? client]) : _client = client ?? http.Client();

  /// Time to wait between AniList requests. Starts at a safe 2.1 s (fits a
  /// 30/min limit) and speeds up if AniList reports a higher limit.
  Duration aniListDelay = const Duration(milliseconds: 2100);

  /// One page (up to 500) of MAL's ranking, ordered by score.
  Future<List<Map<String, dynamic>>> malRankingPage({
    required bool anime,
    required int offset,
    int limit = 500,
  }) async {
    final kind = anime ? 'anime' : 'manga';
    const fields =
        'alternative_titles,mean,media_type,status,start_date,main_picture';
    final uri = Uri.parse(
      '$_malBase/$kind/ranking?ranking_type=all'
      '&limit=$limit&offset=$offset&fields=$fields',
    );

    final http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {'X-MAL-CLIENT-ID': kMalClientId.trim()},
      ).timeout(_timeout);
    } catch (_) {
      throw const MalException(
          'Couldn\'t reach MyAnimeList to build the catalog.');
    }
    if (res.statusCode != 200) {
      throw MalException(
          'MyAnimeList ranking returned error ${res.statusCode}.');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return [
      for (final item in body['data'] as List? ?? const [])
        item as Map<String, dynamic>
    ];
  }

  static const _query = r'''
query ($ids: [Int], $type: MediaType) {
  Page(page: 1, perPage: 50) {
    media(idMal_in: $ids, type: $type) {
      idMal
      countryOfOrigin
      coverImage { color }
    }
  }
}''';

  /// Country and cover color for up to 50 MAL ids. Ids AniList doesn't know
  /// are simply missing from the result. Waits and retries when rate limited.
  Future<Map<int, AniListInfo>> aniListBatchInfo(
    List<int> malIds, {
    required bool anime,
  }) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final http.Response res;
      try {
        res = await _client
            .post(
              Uri.parse(_aniList),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'query': _query,
                'variables': {'ids': malIds, 'type': anime ? 'ANIME' : 'MANGA'},
              }),
            )
            .timeout(_timeout);
      } catch (_) {
        if (attempt == 3) {
          throw const MalException('Couldn\'t reach AniList.');
        }
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }

      _learnRateLimit(res);

      if (res.statusCode == 429) {
        final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 60;
        await Future.delayed(Duration(seconds: wait + 1));
        continue;
      }
      if (res.statusCode != 200) {
        throw MalException('AniList returned error ${res.statusCode}.');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final media =
          ((body['data'] as Map?)?['Page'] as Map?)?['media'] as List? ?? [];
      final out = <int, AniListInfo>{};
      for (final m in media) {
        if (m is! Map) continue;
        final id = (m['idMal'] as num?)?.toInt();
        if (id == null) continue;
        out[id] = AniListInfo(
          m['countryOfOrigin'] as String?,
          _parseHex((m['coverImage'] as Map?)?['color'] as String?),
        );
      }
      return out;
    }
    throw const MalException('AniList kept rate limiting. Try again later.');
  }

  static const _sourceQuery = r'''
query ($id: Int) {
  Media(idMal: $id, type: ANIME) {
    source
    relations {
      edges {
        relationType
        node {
          type
          status
          title { romaji english }
          startDate { year month day }
          endDate { year month day }
        }
      }
    }
  }
}''';

  /// What an anime adapts, from AniList. Null when AniList can't be reached
  /// or doesn't know the title.
  Future<AniListSource?> aniListSource(int malId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final http.Response res;
      try {
        res = await _client
            .post(
              Uri.parse(_aniList),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'query': _sourceQuery,
                'variables': {'id': malId},
              }),
            )
            .timeout(_timeout);
      } catch (_) {
        return null;
      }
      _learnRateLimit(res);
      if (res.statusCode == 429) {
        final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 30;
        await Future.delayed(Duration(seconds: wait + 1));
        continue;
      }
      if (res.statusCode != 200) return null;

      final media = ((jsonDecode(res.body) as Map)['data'] as Map?)?['Media'];
      if (media is! Map) return null;
      final edges = (media['relations'] as Map?)?['edges'] as List? ?? [];

      // Prefer the earliest-started SOURCE work (an LN over its manga).
      Map? best;
      String? bestStart;
      for (final e in edges) {
        if (e is! Map || e['relationType'] != 'SOURCE') continue;
        final node = e['node'];
        if (node is! Map || node['type'] != 'MANGA') continue;
        final start = _dateKey(node['startDate'] as Map?);
        if (best == null || start.compareTo(bestStart!) < 0) {
          best = node;
          bestStart = start;
        }
      }
      final title = best?['title'] as Map?;
      return AniListSource(
        sourceType: media['source'] as String?,
        hasSourceWork: best != null,
        sourceFinished: best?['status'] == 'FINISHED',
        sourceEnd: _lastDay(best?['endDate'] as Map?),
        sourceTitle: (title?['english'] ?? title?['romaji']) as String?,
      );
    }
    return null;
  }

  static String _dateKey(Map? d) {
    final y = d?['year'] as int?;
    if (y == null) return '9999';
    final m = (d?['month'] as int?) ?? 0;
    final day = (d?['day'] as int?) ?? 0;
    return '$y-${'$m'.padLeft(2, '0')}-${'$day'.padLeft(2, '0')}';
  }

  static DateTime? _lastDay(Map? d) {
    final y = d?['year'] as int?;
    if (y == null) return null;
    final m = d?['month'] as int?;
    final day = d?['day'] as int?;
    if (m == null) return DateTime(y, 12, 31);
    if (day == null) return DateTime(y, m + 1, 0);
    return DateTime(y, m, day);
  }

  void _learnRateLimit(http.Response res) {
    final limit = int.tryParse(res.headers['x-ratelimit-limit'] ?? '');
    if (limit != null && limit > 0) {
      // Stay ~10% under the limit.
      final ms = (60000 / limit * 1.1).round();
      aniListDelay = Duration(milliseconds: ms.clamp(400, 3000));
    }
  }

  /// "#e4a15d" -> 0xFFE4A15D
  static int? _parseHex(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : 0xFF000000 | v;
  }

  static List<CatalogTitle> parseRanking(
    List<Map<String, dynamic>> items, {
    required bool anime,
    Map<int, CatalogTitle> previous = const {},
  }) {
    return [
      for (final item in items)
        CatalogTitle.fromMalRanking(
          item,
          anime: anime,
          previous: previous[(item['node'] as Map)['id']],
        )
    ];
  }
}
