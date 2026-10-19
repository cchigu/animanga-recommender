import 'package:flutter/material.dart';

import '../models/catalog_title.dart';
import '../services/library_store.dart';
import '../services/picker.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/countdown.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/tap_circle.dart';
import '../widgets/title_card.dart';
import 'settings_screen.dart';

enum _Phase { idle, counting, revealed, empty }

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

  /// The pick is made when the countdown starts and revealed when it ends.
  void _startCountdown() {
    final result = Picker.instance.pick();
    setState(() {
      _result = result;
      _phase = result.title == null ? _Phase.empty : _Phase.counting;
    });
  }

  void _reveal() {
    final pick = _title!;
    setState(() {
      _palette = BackdropPalette.from(pick.color ?? kDefaultAccent);
      _phase = _Phase.revealed;
    });
  }

  void _backToIdle() => setState(() => _phase = _Phase.idle);

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
        return Column(
          key: const ValueKey('tap'),
          mainAxisSize: MainAxisSize.min,
          children: [
            TapCircle(accent: _palette.accent, onTap: _startCountdown),
            const SizedBox(height: 36),
            ListenableBuilder(
              listenable: Listenable.merge(
                [LibraryStore.instance, SettingsStore.instance],
              ),
              builder: (context, _) {
                final store = LibraryStore.instance;
                final text = store.isConnected
                    ? SettingsStore.instance.summary
                    : 'Tap your profile icon to connect MyAnimeList';
                return Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ],
        );
      case _Phase.counting:
        return Countdown(
          key: const ValueKey('countdown'),
          accent: _palette.accent,
          onFinished: _reveal,
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
