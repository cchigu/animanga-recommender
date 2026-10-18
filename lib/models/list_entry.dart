/// Where a title sits on the user's MAL list.
enum UserStatus {
  current, // Watching / Reading
  completed,
  onHold,
  dropped,
  planned; // Plan to Watch / Plan to Read

  static UserStatus fromMal(String raw) {
    switch (raw) {
      case 'watching':
      case 'reading':
        return UserStatus.current;
      case 'completed':
        return UserStatus.completed;
      case 'on_hold':
        return UserStatus.onHold;
      case 'dropped':
        return UserStatus.dropped;
      default: // plan_to_watch / plan_to_read
        return UserStatus.planned;
    }
  }

  String label({required bool anime}) {
    switch (this) {
      case UserStatus.current:
        return anime ? 'Watching' : 'Reading';
      case UserStatus.completed:
        return 'Completed';
      case UserStatus.onHold:
        return 'On hold';
      case UserStatus.dropped:
        return 'Dropped';
      case UserStatus.planned:
        return anime ? 'Plan to watch' : 'Plan to read';
    }
  }
}

/// One title from the user's anime or manga list.
class ListEntry {
  final int malId;
  final bool isAnime;
  final String title;

  /// MAL media type: tv, movie, ova, ona, special, music (anime) or
  /// manga, manhwa, manhua, light_novel, novel, one_shot... (manga).
  final String mediaType;

  /// Airing/publishing status: finished_airing, currently_airing,
  /// not_yet_aired, finished, currently_publishing, on_hiatus, discontinued...
  final String releaseStatus;

  final UserStatus userStatus;
  final int userScore; // 0 = not scored
  final double? malScore;
  final String? startDate;
  final String? pictureUrl;

  const ListEntry({
    required this.malId,
    required this.isAnime,
    required this.title,
    required this.mediaType,
    required this.releaseStatus,
    required this.userStatus,
    required this.userScore,
    this.malScore,
    this.startDate,
    this.pictureUrl,
  });

  /// Builds an entry from one item of MAL's `/users/{name}/animelist`
  /// or `/mangalist` response: `{ "node": {...}, "list_status": {...} }`.
  factory ListEntry.fromMal(Map<String, dynamic> item, {required bool anime}) {
    final node = item['node'] as Map<String, dynamic>;
    final status = (item['list_status'] as Map<String, dynamic>?) ?? const {};
    final picture = node['main_picture'] as Map<String, dynamic>?;
    return ListEntry(
      malId: node['id'] as int,
      isAnime: anime,
      title: node['title'] as String? ?? 'Untitled',
      mediaType: node['media_type'] as String? ?? 'unknown',
      releaseStatus: node['status'] as String? ?? 'unknown',
      userStatus: UserStatus.fromMal(status['status'] as String? ?? ''),
      userScore: (status['score'] as num?)?.toInt() ?? 0,
      malScore: (node['mean'] as num?)?.toDouble(),
      startDate: node['start_date'] as String?,
      pictureUrl: (picture?['large'] ?? picture?['medium']) as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': malId,
        'anime': isAnime,
        'title': title,
        'type': mediaType,
        'release': releaseStatus,
        'user': userStatus.name,
        'score': userScore,
        'mean': malScore,
        'start': startDate,
        'pic': pictureUrl,
      };

  factory ListEntry.fromJson(Map<String, dynamic> j) => ListEntry(
        malId: j['id'] as int,
        isAnime: j['anime'] as bool,
        title: j['title'] as String,
        mediaType: j['type'] as String,
        releaseStatus: j['release'] as String,
        userStatus: UserStatus.values.byName(j['user'] as String),
        userScore: j['score'] as int,
        malScore: (j['mean'] as num?)?.toDouble(),
        startDate: j['start'] as String?,
        pictureUrl: j['pic'] as String?,
      );
}
