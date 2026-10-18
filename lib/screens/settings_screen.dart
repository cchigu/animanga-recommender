import 'package:flutter/material.dart';

/// Settings shell. The MAL account section is wired up in Milestone 2 and
/// the recommendation settings become real controls in Milestone 4.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _upcoming = <(IconData, String, String)>[
    (Icons.swap_horiz_rounded, 'Anime or manga', 'Which kind of title to pick'),
    (
      Icons.check_circle_outline_rounded,
      'Completion status',
      'Completed (whole sequel/prequel chain) · Hiatus/discontinued · Ongoing',
    ),
    (
      Icons.looks_one_outlined,
      'First major entry only',
      'Earliest-released main entry of the franchise',
    ),
    (
      Icons.shuffle_rounded,
      'Pick mode',
      'Best score · Weighted random (score − 5)⁴ · Completely random',
    ),
    (
      Icons.menu_book_outlined,
      'Manga formats',
      'Manga · Manhwa · Manhua · Light novels · Novels',
    ),
    (
      Icons.movie_outlined,
      'Anime formats',
      'Donghua · Movies · OVAs · ONAs',
    ),
    (
      Icons.bookmark_border_rounded,
      'Only from Plan to Watch / Read',
      'Uses the franchise\'s first entry if any entry is on the list',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader('MyAnimeList account'),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: const Text('Not connected'),
              subtitle: Text(
                'Enter your MAL username here in Milestone 2',
                style: TextStyle(color: muted),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Recommendations'),
          Card(
            child: Column(
              children: [
                for (final (icon, title, subtitle) in _upcoming)
                  ListTile(
                    enabled: false,
                    leading: Icon(icon),
                    title: Text(title),
                    subtitle: Text(subtitle),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Watched, watching, and dropped titles are always excluded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
