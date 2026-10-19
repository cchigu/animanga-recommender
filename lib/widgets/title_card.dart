import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog_title.dart';
import '../models/title_extras.dart';
import '../services/detail_store.dart';
import '../services/mal_api.dart';
import '../services/picker.dart';

/// The reveal card shown after the countdown. Cover art, synopsis and an
/// "Open on MAL" button get added in Milestone 7.
class TitleCard extends StatelessWidget {
  final CatalogTitle title;
  final Color accent;
  final VoidCallback onAgain;

  /// How many titles this one was picked from.
  final int poolSize;

  const TitleCard({
    super.key,
    required this.title,
    required this.accent,
    required this.onAgain,
    required this.poolSize,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: accent.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _Cover(title: title, accent: accent),
                  const SizedBox(height: 18),
                  Text(
                    title.displayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (title.displayTitle != title.title) ...[
                    const SizedBox(height: 6),
                    Text(
                      title.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 15,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_rounded, color: accent, size: 28),
                      const SizedBox(width: 4),
                      Text(
                        title.malScore?.toStringAsFixed(2) ?? 'N/A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'MAL',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _Chip(
                        text: formatLabel(title.mediaType),
                        color: Colors.white24,
                      ),
                      _Chip(
                        text: releaseLabel(title.releaseStatus),
                        color: Colors.white24,
                      ),
                      if (title.isDonghua)
                        const _Chip(text: 'Donghua', color: Colors.white24),
                      if (title.startDate != null &&
                          title.startDate!.length >= 4)
                        _Chip(
                          text: title.startDate!.substring(0, 4),
                          color: Colors.white24,
                        ),
                    ],
                  ),
                  _Details(title: title, accent: accent),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Picked from $poolSize candidates',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openOnMal(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: accent, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open on MAL'),
                ),
                FilledButton.icon(
              onPressed: onAgain,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Pick another'),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on TitleCard {
  Future<void> _openOnMal(BuildContext context) async {
    final kind = title.isAnime ? 'anime' : 'manga';
    final url = Uri.parse('https://myanimelist.net/$kind/${title.malId}');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open MyAnimeList.')),
      );
    }
  }
}

/// Synopsis, genres and episode/chapter counts, loaded from MAL.
class _Details extends StatefulWidget {
  final CatalogTitle title;
  final Color accent;
  const _Details({required this.title, required this.accent});

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    final muted = Colors.white.withValues(alpha: 0.7);
    return FutureBuilder<TitleExtras?>(
      future: DetailStore.instance.extras(t.malId, anime: t.isAnime),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final x = snap.data;
        if (x == null) return const SizedBox.shrink();

        final counts = <String>[
          if (t.isAnime && x.episodes > 0)
            '${x.episodes} episode${x.episodes == 1 ? '' : 's'}',
          if (!t.isAnime && x.volumes > 0)
            '${x.volumes} volume${x.volumes == 1 ? '' : 's'}',
          if (!t.isAnime && x.chapters > 0)
            '${x.chapters} chapter${x.chapters == 1 ? '' : 's'}',
        ];

        return Column(
          children: [
            if (counts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                counts.join(' · '),
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ],
            if (x.genres.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final g in x.genres.take(6))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (x.synopsis != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      Text(
                        x.synopsis!,
                        maxLines: _expanded ? null : 4,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _expanded ? 'Show less' : 'Read more',
                        style: TextStyle(
                          color: widget.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Cover art with the ANIME / MANGA tag on its corner.
class _Cover extends StatelessWidget {
  final CatalogTitle title;
  final Color accent;

  const _Cover({required this.title, required this.accent});

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final height = (screen.height * 0.40).clamp(220.0, 380.0);
    final width = height * 0.7; // MAL covers are roughly 2:3

    Widget placeholder(IconData icon) => Container(
          color: Colors.white.withValues(alpha: 0.06),
          alignment: Alignment.center,
          child: Icon(icon, size: 48, color: Colors.white38),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 30,
                spreadRadius: 1,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: title.pictureUrl == null
              ? placeholder(Icons.image_not_supported_outlined)
              : Image.network(
                  title.pictureUrl!,
                  fit: BoxFit.cover,
                  headers: MalApi.imageHeaders,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : placeholder(Icons.image_outlined),
                  errorBuilder: (_, __, ___) =>
                      placeholder(Icons.broken_image_outlined),
                ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: _Chip(
            text: title.isAnime ? 'ANIME' : 'MANGA',
            color: accent,
            solid: true,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;

  /// Opaque background, for chips laid over the cover art.
  final bool solid;

  const _Chip({required this.text, required this.color, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: solid
            ? Color.lerp(color, Colors.black, 0.45)!.withValues(alpha: 0.9)
            : color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Shown when nothing could be picked: either the settings filter out
/// everything, or MyAnimeList / AniList couldn't be reached.
class NoMatchCard extends StatelessWidget {
  final String reason;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  const NoMatchCard({
    super.key,
    required this.reason,
    required this.accent,
    required this.onBack,
    required this.onRetry,
    required this.onSettings,
  });

  bool get _offline {
    final r = reason.toLowerCase();
    return r.contains('reach') ||
        r.contains('internet') ||
        r.contains('connection') ||
        r.contains('error 5') ||
        r.contains('went wrong');
  }

  @override
  Widget build(BuildContext context) {
    final offline = _offline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.search_off_rounded,
            size: 64,
            color: accent,
          ),
          const SizedBox(height: 16),
          Text(
            offline ? 'Couldn\'t get a pick' : 'Nothing to recommend',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            offline
                ? 'Check your connection and try again.'
                : 'Try loosening a setting, or use "Why wasn\'t this picked?" '
                    'in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: onBack, child: const Text('Back')),
              if (offline)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                )
              else
                FilledButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
