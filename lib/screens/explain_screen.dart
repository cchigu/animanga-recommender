import 'package:flutter/material.dart';

import '../models/catalog_title.dart';
import '../services/explainer.dart';
import '../services/picker.dart';
import '../services/settings_store.dart';

/// "Why wasn't this picked?" — search a title and see every rule it
/// passes or fails under the current settings.
class ExplainScreen extends StatefulWidget {
  const ExplainScreen({super.key});

  @override
  State<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends State<ExplainScreen> {
  final _explainer = Explainer();
  final _controller = TextEditingController();
  List<CatalogTitle> _results = const [];
  CatalogTitle? _selected;
  List<ExplainStep>? _steps;
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check(CatalogTitle t) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = t;
      _steps = null;
      _working = true;
    });
    final steps = await _explainer.explain(t);
    if (!mounted || _selected != t) return;
    setState(() {
      _steps = steps;
      _working = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = SettingsStore.instance.anime ? 'anime' : 'manga';
    final muted = Colors.white.withValues(alpha: 0.65);

    return Scaffold(
      appBar: AppBar(title: const Text('Why wasn\'t this picked?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Search a title to see how each rule treats it with your current '
            'settings. Searching $kind (switch in Settings).',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (q) => setState(() {
              _results = _explainer.search(q);
              _selected = null;
              _steps = null;
            }),
          ),
          const SizedBox(height: 8),
          if (_selected == null)
            for (final t in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.displayTitle),
                subtitle: Text(
                  '${formatLabel(t.mediaType)} · '
                  '${(t.startDate?.length ?? 0) >= 4 ? t.startDate!.substring(0, 4) : '?'} · '
                  'MAL ${t.malScore?.toStringAsFixed(2) ?? '-'}',
                ),
                onTap: () => _check(t),
              ),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            Text(
              _selected!.displayTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_working)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final step in _steps ?? const <ExplainStep>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        step.ok == null ? '·' : (step.ok! ? '✓' : '✕'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: step.ok == null
                              ? muted
                              : step.ok!
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(step.text, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() {
                _selected = null;
                _steps = null;
              }),
              child: const Text('Check another title'),
            ),
          ],
        ],
      ),
    );
  }
}
