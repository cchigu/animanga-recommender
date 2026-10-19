import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Release-status filter options (setting 1).
enum Completion {
  completed('Completed', 'Whole sequel/prequel chain finished'),
  hiatus('On hiatus / discontinued', 'Paused or cancelled'),
  ongoing('Ongoing', 'Still airing or publishing. For anime, also any '
      'franchise whose latest entry ended within the past 6 years');

  final String label;
  final String hint;
  const Completion(this.label, this.hint);
}

/// How to choose among eligible titles (setting 3).
enum PickMode {
  bestScore('Best score', 'Highest MAL score you haven\'t seen'),
  weighted('Weighted random', 'Random, weighted by (score − 5)⁴'),
  random('Completely random', 'Every eligible title equally likely');

  final String label;
  final String hint;
  const PickMode(this.label, this.hint);
}

/// A format the user can switch on or off. [malTypes] are the MAL media
/// types it covers; Donghua is special and is matched by country instead.
enum TitleFormat {
  // Anime
  tv('TV series', true, ['tv']),
  movie('Movies', true, ['movie']),
  ova('OVAs', true, ['ova']),
  ona('ONAs', true, ['ona']),
  special('Specials', true, ['special', 'tv_special']),
  donghua('Donghua', true, []),
  // Manga
  manga('Manga', false, ['manga', 'one_shot']),
  manhwa('Manhwa', false, ['manhwa']),
  manhua('Manhua', false, ['manhua']),
  lightNovel('Light novels', false, ['light_novel']),
  novel('Novels', false, ['novel']);

  final String label;
  final bool isAnime;
  final List<String> malTypes;
  const TitleFormat(this.label, this.isAnime, this.malTypes);

  static List<TitleFormat> forKind({required bool anime}) =>
      [for (final f in values) if (f.isAnime == anime) f];
}

/// All recommendation settings, saved on the phone.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _kAnime = 'set_anime';
  static const _kCompletion = 'set_completion';
  static const _kFirst = 'set_first_entry';
  static const _kMode = 'set_pick_mode';
  static const _kFormats = 'set_formats';
  static const _kPlanned = 'set_planned_only';

  bool anime = true;
  Set<Completion> completion = Completion.values.toSet();
  bool firstEntryOnly = true;
  PickMode pickMode = PickMode.weighted;
  Set<TitleFormat> formats = TitleFormat.values
      .where((f) => f != TitleFormat.special)
      .toSet();
  bool plannedOnly = false;

  SharedPreferences? _prefs;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    anime = p.getBool(_kAnime) ?? anime;
    firstEntryOnly = p.getBool(_kFirst) ?? firstEntryOnly;
    plannedOnly = p.getBool(_kPlanned) ?? plannedOnly;

    final mode = p.getString(_kMode);
    pickMode = PickMode.values
            .where((m) => m.name == mode)
            .firstOrNull ??
        pickMode;

    final c = p.getStringList(_kCompletion);
    if (c != null) {
      final parsed = {
        for (final m in Completion.values) if (c.contains(m.name)) m,
      };
      if (parsed.isNotEmpty) completion = parsed;
    }

    final f = p.getStringList(_kFormats);
    if (f != null) {
      formats = {
        for (final m in TitleFormat.values) if (f.contains(m.name)) m,
      };
    }
    notifyListeners();
  }

  /// Formats switched on for the current kind (anime or manga).
  Set<TitleFormat> get activeFormats =>
      {for (final f in formats) if (f.isAnime == anime) f};

  void setAnime(bool value) {
    anime = value;
    _prefs?.setBool(_kAnime, value);
    notifyListeners();
  }

  /// Returns false (and changes nothing) if it would leave no status picked.
  bool toggleCompletion(Completion c) {
    final next = {...completion};
    if (!next.remove(c)) next.add(c);
    if (next.isEmpty) return false;
    completion = next;
    _prefs?.setStringList(_kCompletion, [for (final m in next) m.name]);
    notifyListeners();
    return true;
  }

  void setFirstEntryOnly(bool value) {
    firstEntryOnly = value;
    _prefs?.setBool(_kFirst, value);
    notifyListeners();
  }

  void setPickMode(PickMode mode) {
    pickMode = mode;
    _prefs?.setString(_kMode, mode.name);
    notifyListeners();
  }

  /// Returns false (and changes nothing) if it would leave no format on for
  /// that kind. Donghua doesn't count, since it's a filter on top of the
  /// other anime formats rather than a format of its own.
  bool toggleFormat(TitleFormat f) {
    final next = {...formats};
    if (!next.remove(f)) next.add(f);
    final remaining = next.where(
      (x) => x.isAnime == f.isAnime && x != TitleFormat.donghua,
    );
    if (remaining.isEmpty) return false;
    formats = next;
    _prefs?.setStringList(_kFormats, [for (final m in next) m.name]);
    notifyListeners();
    return true;
  }

  void setPlannedOnly(bool value) {
    plannedOnly = value;
    _prefs?.setBool(_kPlanned, value);
    notifyListeners();
  }

  /// One-line summary for the home screen.
  String get summary {
    final kind = anime ? 'Anime' : 'Manga';
    final list = plannedOnly ? ' · from ${anime ? 'PTW' : 'PTR'}' : '';
    return '$kind · ${pickMode.label}$list';
  }
}
