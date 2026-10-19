import 'dart:async';
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

  /// Finds the user's profile picture. MAL now serves pictures from signed
  /// links like `cdn.myanimelist.net/s/common/userimages/<id>_225w?s=<sig>`,
  /// which can't be built by hand, so the app reads the link off the user's
  /// MAL profile page, with Jikan as a backup. Every candidate is checked to
  /// actually load. Never throws; [AvatarResult.notes] says what each step found.
  Future<AvatarResult> fetchAvatar(String username) async {
    final notes = <String>[];
    final name = Uri.encodeComponent(username);

    Future<String?> verified(String? url, String source) async {
      if (url == null || url.isEmpty) return null;
      final ok = await _imageLoads(url);
      notes.add('$source: ${ok ? 'ok' : 'image did not load'}');
      return ok ? url : null;
    }

    // 1. The MAL profile page.
    try {
      final res = await _client
          .get(Uri.parse('https://myanimelist.net/profile/$name'),
              headers: _browserHeaders)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        notes.add('Profile page: HTTP ${res.statusCode}');
      } else {
        final url = _pickOwnerImage(res.body, username);
        if (url == null) {
          notes.add('Profile page: picture link not found');
        } else {
          final found = await verified(url, 'Profile page');
          if (found != null) return AvatarResult(found, notes);
        }
      }
    } catch (e) {
      notes.add('Profile page: ${_short(e)}');
    }

    // 2. Jikan (often slow, so a shorter wait).
    try {
      final res = await _client
          .get(Uri.parse('$_jikanBase/users/$name'), headers: _browserHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        notes.add('Jikan: HTTP ${res.statusCode}');
      } else {
        final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'];
        final images = data is Map ? data['images'] : null;
        String? url;
        if (images is Map) {
          final jpg = images['jpg'];
          final webp = images['webp'];
          url = (jpg is Map ? jpg['image_url'] : null) as String? ??
              (webp is Map ? webp['image_url'] : null) as String?;
        }
        if (url == null) {
          notes.add('Jikan: no picture in response');
        } else {
          final found = await verified(url, 'Jikan');
          if (found != null) return AvatarResult(found, notes);
        }
      }
    } on TimeoutException {
      notes.add('Jikan: timed out');
    } catch (e) {
      notes.add('Jikan: ${_short(e)}');
    }

    return AvatarResult(null, notes);
  }

  /// Any MAL user picture link, old (`/images/userimages/123.jpg`) or new
  /// (`/s/common/userimages/<uuid>_225w?s=<sig>`) style.
  static final _userImage = RegExp(
    r'https://cdn\.myanimelist\.net/(?:r/\d+x\d+/)?(?:s/common|images)/userimages/[A-Za-z0-9_\-]+(?:\.(?:jpe?g|png|gif|webp))?(?:\?[^"\s<>]*)?',
    caseSensitive: false,
  );

  static final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final _altAttr =
      RegExp(r'''alt=["']([^"']*)["']''', caseSensitive: false);

  /// Picks the owner's picture from the profile page HTML: preferably an
  /// <img> whose alt text is the username, otherwise the first user picture
  /// on the page (it's in the sidebar, above the friends list).
  static String? _pickOwnerImage(String html, String username) {
    String clean(String url) => url.replaceAll('&amp;', '&');

    final user = username.toLowerCase();
    for (final m in _imgTag.allMatches(html)) {
      final tag = m.group(0)!;
      final alt = _altAttr.firstMatch(tag)?.group(1)?.toLowerCase();
      if (alt == user) {
        final url = _userImage.firstMatch(tag)?.group(0);
        if (url != null) return clean(url);
      }
    }
    final first = _userImage.firstMatch(html)?.group(0);
    return first == null ? null : clean(first);
  }

  static const _browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  /// Headers for showing MAL images; their CDN can refuse bare clients.
  static const imageHeaders = _browserHeaders;

  Future<bool> _imageLoads(String url) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: _browserHeaders)
          .timeout(_timeout);
      final type = res.headers['content-type'] ?? '';
      return res.statusCode == 200 &&
          type.startsWith('image/') &&
          res.bodyBytes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

class AvatarResult {
  final String? url;
  final List<String> notes;
  const AvatarResult(this.url, this.notes);
}
