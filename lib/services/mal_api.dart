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

    final entries = <ListEntry>[];
    while (next != null) {
      final http.Response res;
      try {
        res = await _client.get(
          next,
          headers: {'X-MAL-CLIENT-ID': kMalClientId},
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
        case 400:
        case 401:
          throw const MalException(
              'MyAnimeList rejected the Client ID. Check lib/secrets.dart.');
        default:
          throw MalException(
              'MyAnimeList returned an error (${res.statusCode}). Try again in a bit.');
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

  /// Profile picture URL, or null if the user has none or Jikan is down.
  /// Never throws: a missing picture shouldn't block connecting.
  Future<String?> fetchAvatarUrl(String username) async {
    try {
      final res = await _client
          .get(Uri.parse('$_jikanBase/users/${Uri.encodeComponent(username)}'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
          as Map<String, dynamic>?;
      final images = data?['images'] as Map<String, dynamic>?;
      final url = (images?['webp']?['image_url'] ??
          images?['jpg']?['image_url']) as String?;
      return (url == null || url.isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }
}
