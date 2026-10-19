/// A link from one title to another on MAL ("sequel", "prequel",
/// "side_story", "parent_story", "spin_off", "alternative_version"...).
/// The type describes the *other* title: {id: 2, type: sequel} means
/// title 2 is this title's sequel.
class Relation {
  final int id;
  final String type;
  const Relation(this.id, this.type);

  Map<String, dynamic> toJson() => {'id': id, 't': type};
  factory Relation.fromJson(Map<String, dynamic> j) =>
      Relation(j['id'] as int, j['t'] as String);
}

/// Full MAL details for one title, including its relations. Cached on the
/// phone; finished titles keep longer than ones still airing/publishing.
class TitleDetail {
  final int malId;
  final bool isAnime;
  final String title;
  final String? englishTitle;
  final String mediaType;
  final String releaseStatus;
  final String? startDate;
  final String? endDate;
  final double? malScore;
  final String? pictureUrl;
  final List<Relation> relations;

  /// Anime only: MAL's source type ("manga", "light_novel", "original"...)
  /// and the MAL manga ids this anime adapts.
  final String? source;
  final List<int> adaptedFrom;

  final DateTime fetched;

  const TitleDetail({
    required this.malId,
    required this.isAnime,
    required this.title,
    this.englishTitle,
    required this.mediaType,
    required this.releaseStatus,
    this.startDate,
    this.endDate,
    this.malScore,
    this.pictureUrl,
    required this.relations,
    this.source,
    this.adaptedFrom = const [],
    required this.fetched,
  });

  bool get isFinished =>
      releaseStatus == 'finished_airing' || releaseStatus == 'finished';

  bool get isReleased =>
      releaseStatus != 'not_yet_aired' && releaseStatus != 'not_yet_published';

  /// Finished titles rarely change; others are re-checked sooner.
  Duration get maxAge =>
      isFinished ? const Duration(days: 30) : const Duration(days: 3);

  bool get isStale => DateTime.now().difference(fetched) > maxAge;

  /// When this title ended (or started, if MAL has no end date), taking
  /// the last day of a partial date like "2021" or "2021-06".
  DateTime? get endedOn => _lastDayOf(endDate) ?? _lastDayOf(startDate);

  static DateTime? _lastDayOf(String? d) {
    if (d == null || d.isEmpty) return null;
    final p = d.split('-').map(int.tryParse).toList();
    final y = p.isNotEmpty ? p[0] : null;
    if (y == null) return null;
    final m = p.length > 1 ? p[1] : null;
    final day = p.length > 2 ? p[2] : null;
    if (m == null) return DateTime(y, 12, 31);
    if (day == null) return DateTime(y, m + 1, 0); // last day of month m
    return DateTime(y, m, day);
  }

  Iterable<int> relatedOfType(Set<String> types) =>
      relations.where((r) => types.contains(r.type)).map((r) => r.id);

  /// Sortable start date. MAL gives "2006-10-04", "2006-10" or "2006";
  /// missing parts sort first within the year, missing dates sort last.
  String get sortDate {
    final d = startDate;
    if (d == null || d.isEmpty) return '9999-99-99';
    final parts = d.split('-');
    while (parts.length < 3) {
      parts.add('00');
    }
    return parts.map((p) => p.padLeft(2, '0')).join('-');
  }

  factory TitleDetail.fromMal(Map<String, dynamic> j, {required bool anime}) {
    final picture = j['main_picture'] as Map<String, dynamic>?;
    final alt = j['alternative_titles'] as Map<String, dynamic>?;
    final related =
        (j[anime ? 'related_anime' : 'related_manga'] as List?) ?? const [];
    return TitleDetail(
      malId: j['id'] as int,
      isAnime: anime,
      title: j['title'] as String? ?? 'Untitled',
      englishTitle: alt?['en'] as String?,
      mediaType: j['media_type'] as String? ?? 'unknown',
      releaseStatus: j['status'] as String? ?? 'unknown',
      startDate: j['start_date'] as String?,
      endDate: j['end_date'] as String?,
      malScore: (j['mean'] as num?)?.toDouble(),
      pictureUrl: (picture?['large'] ?? picture?['medium']) as String?,
      relations: [
        for (final r in related)
          if (r is Map && r['node'] is Map && (r['node'] as Map)['id'] is int)
            Relation(
              (r['node'] as Map)['id'] as int,
              r['relation_type'] as String? ?? 'other',
            ),
      ],
      source: anime ? j['source'] as String? : null,
      adaptedFrom: !anime
          ? const []
          : [
              for (final r in (j['related_manga'] as List?) ?? const [])
                if (r is Map &&
                    r['relation_type'] == 'adaptation' &&
                    r['node'] is Map &&
                    (r['node'] as Map)['id'] is int)
                  (r['node'] as Map)['id'] as int,
            ],
      fetched: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': malId,
        'a': isAnime,
        't': title,
        if (englishTitle != null) 'en': englishTitle,
        'type': mediaType,
        'rel': releaseStatus,
        if (startDate != null) 'start': startDate,
        if (endDate != null) 'end': endDate,
        if (malScore != null) 'mean': malScore,
        if (pictureUrl != null) 'pic': pictureUrl,
        'r': [for (final r in relations) r.toJson()],
        if (source != null) 'src': source,
        if (adaptedFrom.isNotEmpty) 'adp': adaptedFrom,
        'f': fetched.millisecondsSinceEpoch,
      };

  factory TitleDetail.fromJson(Map<String, dynamic> j) => TitleDetail(
        malId: j['id'] as int,
        isAnime: j['a'] as bool,
        title: j['t'] as String,
        englishTitle: j['en'] as String?,
        mediaType: j['type'] as String,
        releaseStatus: j['rel'] as String,
        startDate: j['start'] as String?,
        endDate: j['end'] as String?,
        malScore: (j['mean'] as num?)?.toDouble(),
        pictureUrl: j['pic'] as String?,
        relations: [
          for (final r in j['r'] as List)
            Relation.fromJson(r as Map<String, dynamic>)
        ],
        source: j['src'] as String?,
        adaptedFrom: [
          for (final id in (j['adp'] as List?) ?? const []) id as int,
        ],
        fetched: DateTime.fromMillisecondsSinceEpoch(j['f'] as int),
      );
}
