import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/list_entry.dart';
import 'mal_api.dart';

/// Holds the connected MAL account and a cached copy of its lists.
/// Everything is saved on the phone only; nothing goes to the cloud.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore instance = LibraryStore._();

  static const _kUsername = 'mal_username';
  static const _kAvatar = 'mal_avatar';
  static const _kSynced = 'mal_last_synced';
  static const _cacheFile = 'mal_lists.json';

  /// Lists refresh automatically on launch once they are older than this.
  static const staleAfter = Duration(hours: 6);

  final MalApi _api = MalApi();

  String? username;
  String? avatarUrl;

  /// What each profile-picture lookup step found on the last sync.
  List<String> avatarNotes = const [];
  DateTime? lastSynced;
  List<ListEntry> anime = const [];
  List<ListEntry> manga = const [];

  bool syncing = false;
  String? error;

  bool get isConnected => username != null;

  Map<UserStatus, int> counts({required bool anime}) {
    final list = anime ? this.anime : manga;
    final out = {for (final s in UserStatus.values) s: 0};
    for (final e in list) {
      out[e.userStatus] = out[e.userStatus]! + 1;
    }
    return out;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFile');
  }

  /// Loads the saved account and cached lists. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString(_kUsername);
    avatarUrl = prefs.getString(_kAvatar);
    final synced = prefs.getInt(_kSynced);
    lastSynced =
        synced == null ? null : DateTime.fromMillisecondsSinceEpoch(synced);

    try {
      final f = await _file();
      if (username != null && await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        anime = [
          for (final e in j['anime'] as List)
            ListEntry.fromJson(e as Map<String, dynamic>)
        ];
        manga = [
          for (final e in j['manga'] as List)
            ListEntry.fromJson(e as Map<String, dynamic>)
        ];
      }
    } catch (_) {
      // A corrupt cache just means the next sync rebuilds it.
      anime = const [];
      manga = const [];
    }
    notifyListeners();
  }

  /// Refreshes in the background if the cache is old. Errors stay quiet here
  /// and show up in Settings instead.
  Future<void> refreshIfStale() async {
    if (!isConnected || syncing) return;
    final last = lastSynced;
    if (last == null || DateTime.now().difference(last) > staleAfter) {
      await sync(username!);
    }
  }

  /// Fetches both lists (and the profile picture) for [name]. On success the
  /// account switches to [name]; on failure the previous data stays as is.
  Future<bool> sync(String name) async {
    final user = name.trim();
    if (user.isEmpty || syncing) return false;

    syncing = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.fetchList(user, anime: true),
        _api.fetchList(user, anime: false),
      ]);
      final avatarResult = await _api.fetchAvatar(user);
      final avatar = avatarResult.url;
      avatarNotes = avatarResult.notes;

      // Keep the old picture if Jikan hiccups, unless the account changed.
      final sameUser = user.toLowerCase() == username?.toLowerCase();
      avatarUrl = avatar ?? (sameUser ? avatarUrl : null);
      anime = results[0];
      manga = results[1];
      username = user;
      lastSynced = DateTime.now();
      await _save();
      return true;
    } on MalException catch (e) {
      error = e.message;
      return false;
    } catch (e) {
      error = 'Something went wrong: $e';
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    username = null;
    avatarUrl = null;
    lastSynced = null;
    anime = const [];
    manga = const [];
    error = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUsername);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kSynced);
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsername, username!);
    if (avatarUrl != null) {
      await prefs.setString(_kAvatar, avatarUrl!);
    } else {
      await prefs.remove(_kAvatar);
    }
    await prefs.setInt(_kSynced, lastSynced!.millisecondsSinceEpoch);

    final f = await _file();
    await f.writeAsString(jsonEncode({
      'anime': [for (final e in anime) e.toJson()],
      'manga': [for (final e in manga) e.toJson()],
    }));
  }
}
