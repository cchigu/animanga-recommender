import 'package:flutter/material.dart';

import '../models/catalog_title.dart';
import '../services/catalog_store.dart';
import '../services/detail_store.dart';
import '../services/library_store.dart';
import '../services/mal_api.dart';
import '../services/picker.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/countdown.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/tap_circle.dart';
import '../widgets/title_card.dart';
import 'settings_screen.dart';

enum _Phase { idle, counting, searching, revealed, empty }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Phase _phase = _Phase.idle;
  PickResult? _result;
  CatalogTitle? get _title => _result?.title;
  BackdropPalette _palette = BackdropPalette.initial;

  bool _countdownDone = false;
  int _tapId = 0; // ignores results from an earlier tap

  /// The search starts with the countdown; the reveal waits for both.
  void _startCountdown() {
    final tap = ++_tapId;
    setState(() {
      _result = null;
      _countdownDone = false;
      _phase = _Phase.counting;
    });

    Picker.instance.pick().then((result) {
      if (!mounted || tap != _tapId) return;
      // Load the cover and details now so they're ready at the reveal.
      final picked = result.title;
      if (picked != null) {
        DetailStore.instance.extras(picked.malId, anime: picked.isAnime);
      }
      final url = result.title?.pictureUrl;
      if (url != null) {
        precacheImage(
          NetworkImage(url, headers: MalApi.imageHeaders),
          context,
          onError: (_, __) {},
        );
      }
      _result = result;
      _maybeFinish();
    }).catchError((Object e) {
      if (!mounted || tap != _tapId) return;
      _result = PickResult(null, 0, 'Something went wrong: $e');
      _maybeFinish();
    });
  }

  void _onCountdownFinished() {
    _countdownDone = true;
    _maybeFinish();
  }

  void _maybeFinish() {
    if (!_countdownDone) return;
    final result = _result;
    setState(() {
      if (result == null) {
        _phase = _Phase.searching;
      } else if (result.title == null) {
        _phase = _Phase.empty;
      } else {
        _palette = BackdropPalette.from(result.title!.color ?? kDefaultAccent);
        _phase = _Phase.revealed;
      }
    });
  }

  void _backToIdle() => setState(() => _phase = _Phase.idle);

  /// The idle screen: welcome when no account is connected, otherwise the
  /// Tap here circle with the current setup and catalog status under it.
  Widget _buildIdle() {
    final library = LibraryStore.instance;
    final catalog = CatalogStore.instance;
    final muted = Colors.white.withValues(alpha: 0.75);

    if (!library.isConnected) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 64, color: _palette.accent),
            const SizedBox(height: 20),
            const Text(
              'One tap, one pick',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect your MyAnimeList account and Animanga Recommender '
              'picks your next anime or manga from what you haven\'t seen, '
              'following your settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _openSettings,
              style: FilledButton.styleFrom(
                backgroundColor: _palette.accent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect MyAnimeList'),
            ),
          ],
        ),
      );
    }

    final building = catalog.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: building ? 0.45 : 1,
          child: TapCircle(
            accent: _palette.accent,
            label: building ? 'Hang on…' : 'Tap here',
            onTap: building
                ? () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                      content: Text('The catalog is still being built.')))
                : _startCountdown,
          ),
        ),
        const SizedBox(height: 36),
        Text(
          SettingsStore.instance.summary,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (building) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              children: [
                Text(
                  catalog.error != null
                      ? 'Couldn\'t build the catalog: ${catalog.error}'
                      : catalog.phase ?? 'Building your catalog…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (catalog.error == null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: catalog.busy ? catalog.progress : null,
                      minHeight: 5,
                      color: _palette.accent,
                    ),
                  )
                else
                  TextButton(
                    onPressed: catalog.busy ? null : catalog.rebuild,
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
        ] else if (library.error != null) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Couldn\'t refresh your MAL list, so picks use the last saved '
              'copy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_palette.top, _palette.middle, _palette.bottom],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(onProfileTap: _openSettings),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.85, end: 1.0).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _buildCenter(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenter() {
    switch (_phase) {
      case _Phase.idle:
        return ListenableBuilder(
          key: const ValueKey('tap'),
          listenable: Listenable.merge([
            LibraryStore.instance,
            SettingsStore.instance,
            CatalogStore.instance,
          ]),
          builder: (context, _) => _buildIdle(),
        );
      case _Phase.counting:
        return Countdown(
          key: const ValueKey('countdown'),
          accent: _palette.accent,
          onFinished: _onCountdownFinished,
        );
      case _Phase.searching:
        return Column(
          key: const ValueKey('searching'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                color: _palette.accent,
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<int>(
              valueListenable: Picker.instance.checked,
              builder: (context, n, _) => Text(
                n <= 1 ? 'Checking franchises…' : 'Checked $n franchises…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'First picks take longer; later ones are cached.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        );
      case _Phase.revealed:
        return SingleChildScrollView(
          key: ValueKey('${_title!.isAnime}-${_title!.malId}'),
          child: TitleCard(
            title: _title!,
            accent: _palette.accent,
            poolSize: _result!.poolSize,
            onAgain: _startCountdown,
          ),
        );
      case _Phase.empty:
        return NoMatchCard(
          key: const ValueKey('empty'),
          reason: _result?.emptyReason ?? 'No titles match your settings.',
          accent: _palette.accent,
          onBack: _backToIdle,
          onRetry: _startCountdown,
          onSettings: _openSettings,
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onProfileTap;

  const _TopBar({required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Animanga Recommender',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: LibraryStore.instance,
            builder: (context, _) => ProfileAvatar(
              onTap: onProfileTap,
              imageUrl: LibraryStore.instance.avatarUrl,
            ),
          ),
        ],
      ),
    );
  }
}
