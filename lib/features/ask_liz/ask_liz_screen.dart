import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/tool_card.dart';
import 'tool_ranking.dart';

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

  /// Set when the server refused for a reason worth saying out loud, rather
  /// than one worth quietly working around.
  String? _notice;

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
      _notice = null;
    });

    // Semantic search on the server is authoritative — including when it finds
    // nothing. "No tool is close enough" is a real answer, so only an
    // unreachable backend (null) falls through to on-device keyword ranking.
    final server = await _askServer(q);
    if (_notice != null) {
      // Falling through to keyword ranking here would hand back visibly worse
      // answers and blame nothing — the exact failure this screen was rebuilt
      // to remove. Say what happened instead.
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (server != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _results = server;
        });
      }
      return;
    }

    // Local retrieval + naive ranking (fallback). The reason string mimics the
    // LLM's "why this fits" output.
    final repo = ref.read(contentRepositoryProvider);
    final terms = ToolRanking.termsOf(q);
    final candidates = await repo.searchTools(q);

    // If direct search is thin, widen by scoring all tools on term overlap.
    List<Tool> pool = candidates;
    if (pool.length < 3) {
      // This path scores tools on their prose, so it is one of the few
      // callers that genuinely needs it.
      final all = await repo.tools(
        const ToolQuery(limit: 100, includeProse: true),
      );
      pool = all.items;
    }

    final top = ToolRanking.shortlist(pool, terms);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = top
          .map((t) => _Suggestion(t, ToolRanking.reasonFor(t, terms)))
          .toList();
    });
  }

  /// Calls the ask-liz Edge Function (server-side LLM). Returns null on
  /// mock/offline mode or any failure, so the caller falls back to local rank.
  Future<List<_Suggestion>?> _askServer(String q) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return null;
    try {
      final res = await client.functions.invoke(
        'ask-liz',
        body: {'query': q, 'limit': 5},
      );
      final payload = res.data;
      if (payload is! Map || payload['data'] is! List) return null;
      final picks = (payload['data'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final ids = picks.map((p) => p['tool_id'].toString()).toList();
      // Distinct from null: the backend answered, and the answer is "nothing
      // matches well enough".
      if (ids.isEmpty) return const <_Suggestion>[];
      final tools = await ref.read(contentRepositoryProvider).compareTools(ids);
      final byId = {for (final t in tools) t.id: t};
      final out = <_Suggestion>[];
      for (final p in picks) {
        final t = byId[p['tool_id'].toString()];
        if (t != null) out.add(_Suggestion(t, (p['reason'] ?? '').toString()));
      }
      return out;
    } on FunctionException catch (e) {
      // 429 is the rate limit doing its job. It is a state worth naming: the
      // reader asked a lot in a short time, and the answer is to wait, not to
      // accept a worse result they cannot account for.
      _notice = noticeForStatus(e.status);
      return null;
    } catch (_) {
      return null;
    }
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
                    ? _Intro(
                        examples: _examples,
                        onPick: (q) {
                          _controller.text = q;
                          _ask(q);
                        },
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(
                                  LizRadius.md,
                                ),
                              ),
                              child: Text(
                                _answered!,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_notice != null)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: LizColors.rising.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  LizRadius.md,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.hourglass_bottom,
                                    size: 20,
                                    color: LizColors.rising,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_notice!)),
                                ],
                              ),
                            )
                          else if (_results.isEmpty)
                            Text(
                              "I couldn't find a great match for that. Try describing what you want to do.",
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            )
                          else ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Here\'s what fits best:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            for (final s in _results) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 4,
                                  top: 4,
                                ),
                                child: Row(
                                  children: [
                                    const Text('✨ '),
                                    Expanded(
                                      child: Text(
                                        s.reason,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
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
              _InputBar(controller: _controller, onSubmit: _ask),
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
            Text(
              'Describe what you need',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Liz finds the right tool and tells you why it fits.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final e in examples)
                  ActionChip(label: Text(e), onPressed: () => onPick(e)),
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
        16,
        8,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
          // An icon-only button has no name of its own, so a screen reader
          // announced this as just "button". The name has to sit on the icon:
          // a button merges its children's semantics into its own node, while
          // a wrapping Tooltip labels a separate node above it and leaves the
          // tappable one nameless — which the accessibility test caught. The
          // tooltip stays as the hover hint.
          Tooltip(
            message: 'Ask Liz',
            child: FilledButton(
              onPressed: () => widget.onSubmit(widget.controller.text),
              style: FilledButton.styleFrom(
                minimumSize: const Size(52, 52),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.arrow_upward, semanticLabel: 'Ask Liz'),
            ),
          ),
        ],
      ),
    );
  }
}
