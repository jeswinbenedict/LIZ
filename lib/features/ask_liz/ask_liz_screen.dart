import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/tool_card.dart';

/// A single Ask-Liz result: a tool plus a one-line reason it fits the query.
class _Suggestion {
  const _Suggestion(this.tool, this.reason);
  final Tool tool;
  final String reason;
}

/// Natural-language tool finder. In mock mode this ranks locally over the
/// bundled tools; in live mode it would call the `/ask-liz` Edge Function which
/// wraps the LLM. Either way the UI is identical.
class AskLizScreen extends ConsumerStatefulWidget {
  const AskLizScreen({super.key});

  @override
  ConsumerState<AskLizScreen> createState() => _AskLizScreenState();
}

class _AskLizScreenState extends ConsumerState<AskLizScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _answered;
  List<_Suggestion> _results = [];

  static const _examples = [
    'free AI tool to remove image backgrounds',
    'edit video by transcript',
    'review my pull requests',
    'transcribe audio privately',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _answered = q;
    });
    // Local retrieval + naive ranking. The reason string mimics the LLM's
    // "why this fits" output.
    final repo = ref.read(contentRepositoryProvider);
    final terms = q.toLowerCase().split(RegExp(r'\s+')).toSet();
    final candidates = await repo.searchTools(q);

    // If direct search is thin, widen by scoring all tools on term overlap.
    List<Tool> pool = candidates;
    if (pool.length < 3) {
      final all = await repo.tools(const ToolQuery(limit: 100));
      pool = all.items;
    }

    int score(Tool t) {
      final hay =
          '${t.name} ${t.tagline} ${t.description} ${t.tags.join(' ')} ${t.category}'
              .toLowerCase();
      var s = 0;
      for (final term in terms) {
        if (term.length < 3) continue;
        if (hay.contains(term)) s += 2;
      }
      if (terms.contains('free') && t.pricingType.name == 'free') s += 3;
      s += (t.trendScore / 40).round();
      return s;
    }

    final ranked = pool.where((t) => score(t) > 0).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    final top = ranked.take(5).toList();

    setState(() {
      _loading = false;
      _results = top
          .map((t) => _Suggestion(t, _reasonFor(t, terms)))
          .toList();
    });
  }

  String _reasonFor(Tool t, Set<String> terms) {
    if (terms.contains('free') && t.pricingType.name == 'free') {
      return 'Free, and matches what you described.';
    }
    final tag = t.tags.firstWhere(
        (tag) => terms.any((term) => term.length > 2 && tag.contains(term)),
        orElse: () => t.category.replaceAll('ai-', ''));
    return 'Strong fit for $tag — ${t.tagline}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 720,
          child: Column(
            children: [
              _Header(),
              Expanded(
                child: _answered == null
                    ? _Intro(examples: _examples, onPick: (q) {
                        _controller.text = q;
                        _ask(q);
                      })
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(LizRadius.md),
                              ),
                              child: Text(_answered!,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_results.isEmpty)
                            Text(
                              "I couldn't find a great match for that. Try describing what you want to do.",
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            )
                          else ...[
                            Row(
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 18, color: scheme.primary),
                                const SizedBox(width: 6),
                                Text('Here\'s what fits best:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            for (final s in _results) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4, bottom: 4, top: 4),
                                child: Row(
                                  children: [
                                    const Text('✨ '),
                                    Expanded(
                                      child: Text(s.reason,
                                          style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              fontStyle: FontStyle.italic)),
                                    ),
                                  ],
                                ),
                              ),
                              ToolCard(tool: s.tool),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ],
                      ),
              ),
              _InputBar(
                controller: _controller,
                onSubmit: _ask,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: LizColors.brand),
          const SizedBox(width: 8),
          Text('Ask Liz', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          if (!context.isPhone) const LizWordmark(),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.onPick});
  final List<String> examples;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48, color: LizColors.brand),
            const SizedBox(height: 16),
            Text('Describe what you need',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Liz finds the right tool and tells you why it fits.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final e in examples)
                  ActionChip(
                    label: Text(e),
                    onPressed: () => onPick(e),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSubmit,
              decoration: const InputDecoration(
                hintText: 'e.g. free AI tool for transcription',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => widget.onSubmit(widget.controller.text),
            style: FilledButton.styleFrom(
                minimumSize: const Size(52, 52),
                padding: EdgeInsets.zero,
                shape: const CircleBorder()),
            child: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
