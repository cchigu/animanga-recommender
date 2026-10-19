import 'package:flutter/material.dart';

import '../models/list_entry.dart';
import '../services/library_store.dart';
import '../widgets/profile_avatar.dart';

/// Settings: the MAL account (Milestone 2) and the recommendation settings,
/// which become real controls in Milestone 4.
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
          ListenableBuilder(
            listenable: LibraryStore.instance,
            builder: (context, _) => LibraryStore.instance.isConnected
                // Not const, so the cards rebuild while syncing.
                // ignore: prefer_const_constructors
                ? _ConnectedCard()
                // ignore: prefer_const_constructors
                : _ConnectCard(),
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

/// Shown before an account is connected: username field + Connect button.
class _ConnectCard extends StatefulWidget {
  const _ConnectCard();

  @override
  State<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<_ConnectCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    await LibraryStore.instance.sync(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final store = LibraryStore.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your MyAnimeList username. Your list needs to be public.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !store.syncing,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _connect(),
              decoration: const InputDecoration(
                labelText: 'MAL username',
                prefixIcon: Icon(Icons.alternate_email_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            if (store.error != null) ...[
              const SizedBox(height: 10),
              _ErrorText(store.error!),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: store.syncing ? null : _connect,
              child: store.syncing
                  ? const _ButtonSpinner(label: 'Loading your lists…')
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once connected: profile, list counts, refresh and disconnect.
class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard();

  Future<void> _confirmDisconnect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect MyAnimeList?'),
        content: const Text(
            'The saved copy of your lists is removed from this phone. '
            'Nothing changes on MyAnimeList.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok == true) await LibraryStore.instance.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final store = LibraryStore.instance;
    final muted = Colors.white.withValues(alpha: 0.6);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  onTap: () {},
                  imageUrl: store.avatarUrl,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.username!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        store.syncing
                            ? 'Syncing…'
                            : 'Synced ${_ago(store.lastSynced)}',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CountsColumn(
                    title: 'Anime',
                    anime: true,
                    counts: store.counts(anime: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CountsColumn(
                    title: 'Manga',
                    anime: false,
                    counts: store.counts(anime: false),
                  ),
                ),
              ],
            ),
            if (store.error != null) ...[
              const SizedBox(height: 12),
              _ErrorText(store.error!),
            ],
            if (store.avatarUrl == null && store.avatarNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Profile picture not found:\n${store.avatarNotes.join('\n')}',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: store.syncing
                        ? null
                        : () => store.sync(store.username!),
                    child: store.syncing
                        ? const _ButtonSpinner(label: 'Refreshing…')
                        : const Text('Refresh lists'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed:
                      store.syncing ? null : () => _confirmDisconnect(context),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _CountsColumn extends StatelessWidget {
  final String title;
  final bool anime;
  final Map<UserStatus, int> counts;

  const _CountsColumn({
    required this.title,
    required this.anime,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final muted = Colors.white.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · $total',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final s in UserStatus.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.label(anime: anime),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  Text('${counts[s]}', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded,
            size: 18, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  final String label;
  const _ButtonSpinner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
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
