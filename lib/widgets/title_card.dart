import 'package:flutter/material.dart';

import '../models/catalog_title.dart';
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
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
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
                  _Chip(
                    text: title.isAnime ? 'ANIME' : 'MANGA',
                    color: accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title.displayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Picked from $poolSize eligible titles',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
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
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;

  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
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

/// Shown when no title fits the current settings.
class NoMatchCard extends StatelessWidget {
  final String reason;
  final Color accent;
  final VoidCallback onBack;

  const NoMatchCard({
    super.key,
    required this.reason,
    required this.accent,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: accent),
          const SizedBox(height: 16),
          const Text(
            'Nothing to recommend',
            style: TextStyle(
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
            'Try loosening a setting.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}
