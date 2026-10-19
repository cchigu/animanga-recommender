import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/list_entry.dart';
import '../secrets.dart';

class MalException implements Exception {
  final String message;
  const MalException(this.message);
  @override
  String toString() => message;
}

/// Reads public MyAnimeList data. Lists come from the official MAL API
/// (needs the Client ID in lib/secrets.dart); the profile picture comes from
/// Jikan, because the official API only exposes it for the signed-in user.
class MalApi {
  static const _malBase = 'https://api.myanimelist.net/v2';
  static const _jikanBase = 'https://api.jikan.moe/v4';
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;
  MalApi([http.Client? client]) : _client = client ?? http.Client();

  /// Fetches the user's whole anime or manga list, following MAL's paging.
  Future<List<ListEntry>> fetchList(String username,
      {required bool anime}) async {
    final kind = anime ? 'animelist' : 'mangalist';
    const fields = 'list_status,media_type,status,mean,start_date';
    Uri? next = Uri.parse(
      '$_malBase/users/${Uri.encodeComponent(username)}/$kind'
      '?fields=$fields&limit=1000&nsfw=true',
    );

    final clientId = kMalClientId.trim();
    if (clientId.isEmpty || clientId.startsWith('PASTE_')) {
      throw const MalException(
          'No Client ID yet. Paste it into lib/secrets.dart, then fully '
          'restart the app (stop and run again, not hot reload).');
    }

    final entries = <ListEntry>[];
    while (next != null) {
      final http.Response res;
      try {
        res = await _client.get(
          next,
          headers: {'X-MAL-CLIENT-ID': clientId},
        ).timeout(_timeout);
      } catch (_) {
        throw const MalException(
            'Couldn\'t reach MyAnimeList. Check your internet connection.');
      }

      switch (res.statusCode) {
        case 200:
          break;
        case 404:
          throw MalException('No MyAnimeList user named "$username".');
        case 403:
          throw const MalException(
              'That list is private. Set your MAL list to public and try again.');
        case 401:
          throw MalException('MyAnimeList rejected the Client ID '
              '(${clientId.length} characters, ends in '
              '"${clientId.length >= 4 ? clientId.substring(clientId.length - 4) : clientId}"). '
              '${_malError(res)}');
        default:
          throw MalException('MyAnimeList returned error ${res.statusCode} '
              'on the $kind request. ${_malError(res)}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final item in (body['data'] as List? ?? const [])) {
        entries.add(
          ListEntry.fromMal(item as Map<String, dynamic>, anime: anime),
        );
      }
      final nextUrl = (body['paging'] as Map<String, dynamic>?)?['next'];
      next = nextUrl is String ? Uri.parse(nextUrl) : null;
    }
    return entries;
  }

  /// MAL's own error code and message, e.g. "invalid_parameters".
  static String _malError(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final code = j['error'] ?? '';
      final msg = j['message'] ?? '';
      return 'MAL says: $code${msg.toString().isEmpty ? '' : ' - $msg'}';
    } catch (_) {
      final body = res.body.length > 120 ? res.body.substring(0, 120) : res.body;
      return 'MAL says: $body';
    }
  }

  /// Profile picture URL, or null if the user has none or MAL can't be read.
  /// Tries Jikan first, then the MAL profile page itself.
  /// Never throws: a missing picture shouldn't block connecting.
  Future<String?> fetchAvatarUrl(String username) async {
    return await _avatarFromJikan(username) ??
        await _avatarFromProfilePage(username);
  }

  Future<String?> _avatarFromJikan(String username) async {
    try {
      final res = await _client
          .get(Uri.parse('$_jikanBase/users/${Uri.encodeComponent(username)}'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
          as Map<String, dynamic>?;
      final images = data?['images'] as Map<String, dynamic>?;
      final url = (images?['jpg']?['image_url'] ??
          images?['webp']?['image_url']) as String?;
      return (url == null || url.isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }

  static final _userImage = RegExp(
    r'https://cdn\.myanimelist\.net/(?:r/\d+x\d+/)?images/userimages/\d+\.(?:jpe?g|png|gif|webp)(?:\?[^"\s<>]*)?',
    caseSensitive: false,
  );

  Future<String?> _avatarFromProfilePage(String username) async {
    try {
      final res = await _client.get(
        Uri.parse(
            'https://myanimelist.net/profile/${Uri.encodeComponent(username)}'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AnimangaRecommender/0.2',
        },
      ).timeout(_timeout);
      if (res.statusCode != 200) return null;
      // The owner's picture sits in the "user-image" block; search from there
      // so a friend's picture further down the page can't be picked up.
      final body = res.body;
      final at = body.indexOf('user-image');
      final match = _userImage
          .firstMatch(at >= 0 ? body.substring(at) : body)
          ?.group(0);
      if (match == null) return null;
      // Ask for the full-size image instead of a resized thumbnail.
      return match.replaceFirst(RegExp(r'/r/\d+x\d+/'), '/');
    } catch (_) {
      return null;
    }
  }
}
