/// Reveal-card details that the picker itself doesn't need.
class TitleExtras {
  final String? synopsis;
  final List<String> genres;
  final int episodes; // anime, 0 = unknown
  final int chapters; // manga, 0 = unknown
  final int volumes; // manga, 0 = unknown

  const TitleExtras({
    this.synopsis,
    this.genres = const [],
    this.episodes = 0,
    this.chapters = 0,
    this.volumes = 0,
  });

  factory TitleExtras.fromMal(Map<String, dynamic> j) {
    var synopsis = (j['synopsis'] as String?)?.trim();
    // Drop MAL's "[Written by MAL Rewrite]" style footers.
    synopsis = synopsis
        ?.replaceAll(RegExp(r'\n*\[Written by[^\]]*\]\s*$'), '')
        .replaceAll(RegExp(r'\n*\(Source:[^)]*\)\s*$'), '')
        .trim();
    return TitleExtras(
      synopsis: (synopsis == null || synopsis.isEmpty) ? null : synopsis,
      genres: [
        for (final g in (j['genres'] as List?) ?? const [])
          if (g is Map && g['name'] is String) g['name'] as String,
      ],
      episodes: (j['num_episodes'] as num?)?.toInt() ?? 0,
      chapters: (j['num_chapters'] as num?)?.toInt() ?? 0,
      volumes: (j['num_volumes'] as num?)?.toInt() ?? 0,
    );
  }
}
