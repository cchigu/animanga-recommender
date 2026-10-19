import 'package:flutter/material.dart';

/// One title in the candidate pool the app picks from.
/// MAL gives the basics; AniList adds country of origin (to spot donghua)
/// and the cover's main color (for the background).
class CatalogTitle {
  final int malId;
  final bool isAnime;
  final String title;
  final String? englishTitle;

  /// MAL media type: tv, movie, ova, ona, special, music, tv_special (anime)
  /// or manga, manhwa, manhua, light_novel, novel, one_shot, doujinshi (manga).
  final String mediaType;

  /// finished_airing / currently_airing / not_yet_aired (anime) or
  /// finished / currently_publishing / on_hiatus / discontinued (manga).
  final String releaseStatus;

  final double? malScore;
  final int? rank;
  final String? startDate;
  final String? pictureUrl;

  // Filled in from AniList. [anilistChecked] is true once we've asked,
  // even if AniList had no match.
  final bool anilistChecked;
  final String? country; // JP, CN, KR, TW...
  final int? coverColor; // ARGB

  const CatalogTitle({
    required this.malId,
    required this.isAnime,
    required this.title,
    this.englishTitle,
    required this.mediaType,
    required this.releaseStatus,
    this.malScore,
    this.rank,
    this.startDate,
    this.pictureUrl,
    this.anilistChecked = false,
    this.country,
    this.coverColor,
  });

  /// Chinese animation. Only meaningful for anime that AniList has checked.
  bool get isDonghua => isAnime && country == 'CN';

  Color? get color => coverColor == null ? null : Color(coverColor!);

  /// Display name: the English title when MAL has one, else the main title.
  String get displayTitle =>
      (englishTitle != null && englishTitle!.isNotEmpty) ? englishTitle! : title;

  /// From one item of MAL's `/anime/ranking` or `/manga/ranking` response.
  /// [previous] carries over AniList data we already have for this title.
  factory CatalogTitle.fromMalRanking(
    Map<String, dynamic> item, {
    required bool anime,
    CatalogTitle? previous,
  }) {
    final node = item['node'] as Map<String, dynamic>;
    final picture = node['main_picture'] as Map<String, dynamic>?;
    final alt = node['alternative_titles'] as Map<String, dynamic>?;
    final ranking = item['ranking'] as Map<String, dynamic>?;
    return CatalogTitle(
      malId: node['id'] as int,
      isAnime: anime,
      title: node['title'] as String? ?? 'Untitled',
      englishTitle: alt?['en'] as String?,
      mediaType: node['media_type'] as String? ?? 'unknown',
      releaseStatus: node['status'] as String? ?? 'unknown',
      malScore: (node['mean'] as num?)?.toDouble(),
      rank: (ranking?['rank'] as num?)?.toInt(),
      startDate: node['start_date'] as String?,
      pictureUrl: (picture?['large'] ?? picture?['medium']) as String?,
      anilistChecked: previous?.anilistChecked ?? false,
      country: previous?.country,
      coverColor: previous?.coverColor,
    );
  }

  CatalogTitle withAniList({String? country, int? coverColor}) => CatalogTitle(
        malId: malId,
        isAnime: isAnime,
        title: title,
        englishTitle: englishTitle,
        mediaType: mediaType,
        releaseStatus: releaseStatus,
        malScore: malScore,
        rank: rank,
        startDate: startDate,
        pictureUrl: pictureUrl,
        anilistChecked: true,
        country: country,
        coverColor: coverColor,
      );

  Map<String, dynamic> toJson() => {
        'id': malId,
        'a': isAnime,
        't': title,
        if (englishTitle != null) 'en': englishTitle,
        'type': mediaType,
        'rel': releaseStatus,
        if (malScore != null) 'mean': malScore,
        if (rank != null) 'rank': rank,
        if (startDate != null) 'start': startDate,
        if (pictureUrl != null) 'pic': pictureUrl,
        if (anilistChecked) 'al': true,
        if (country != null) 'cc': country,
        if (coverColor != null) 'col': coverColor,
      };

  factory CatalogTitle.fromJson(Map<String, dynamic> j) => CatalogTitle(
        malId: j['id'] as int,
        isAnime: j['a'] as bool,
        title: j['t'] as String,
        englishTitle: j['en'] as String?,
        mediaType: j['type'] as String,
        releaseStatus: j['rel'] as String,
        malScore: (j['mean'] as num?)?.toDouble(),
        rank: j['rank'] as int?,
        startDate: j['start'] as String?,
        pictureUrl: j['pic'] as String?,
        anilistChecked: j['al'] as bool? ?? false,
        country: j['cc'] as String?,
        coverColor: j['col'] as int?,
      );
}
