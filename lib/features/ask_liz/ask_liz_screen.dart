import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/liz_card.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import '../track/bookmark_button.dart';
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
  const AskLizScreen({super.key, this.initialQuery});

  /// Asked at once when the screen opens (from the search box).
  final String? initialQuery;

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
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask(q);
      });
    }
  }

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
    Analytics.track(
      'ask',
      props: {'q': clip(q, 100), 'results': server?.length},
    );
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
    final p = context.liz;
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    void pick(String q) {
      _controller.text = q;
      _ask(q);
    }

    // Before a question, the page is the question: a title, the field in the
    // middle of it, and a few examples. Afterwards the field moves to the foot
    // of the page and the answer takes its place.
    if (_answered == null) {
      return Scaffold(
        body: SafeArea(
          child: _Intro(
            controller: _controller,
            examples: _examples,
            onSubmit: _ask,
            onPick: pick,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MaxWidth(
                maxWidth: 760 + gutter * 2,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    phone ? 12 : 32,
                    gutter,
                    24,
                  ),
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 18, color: p.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Ask Liz',
                          style: LizText.subhead.copyWith(
                            color: p.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _answered = null;
                            _results = [];
                            _notice = null;
                            _controller.clear();
                          }),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New question'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(
                        '“${_answered!}”',
                        style: (phone ? LizText.title2 : LizText.title1)
                            .copyWith(color: p.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const _ThinkingRows()
                    else if (_notice != null)
                      _Notice(text: _notice!)
                    else if (_results.isEmpty)
                      Text(
                        "I couldn't find a great match for that. Try describing what you want to do.",
                        style: LizText.body.copyWith(color: p.textSecondary),
                      )
                    else ...[
                      Text(
                        "Here's what fits best",
                        style: LizText.subhead.copyWith(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < _results.length; i++) ...[
                        _Answer(rank: i + 1, suggestion: _results[i]),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            MaxWidth(
              maxWidth: 760 + gutter * 2,
              child: _InputBar(controller: _controller, onSubmit: _ask),
            ),
          ],
        ),
      ),
    );
  }
}

/// One answer: its place, the tool, and why it fits.
class _Answer extends StatelessWidget {
  const _Answer({required this.rank, required this.suggestion});
  final int rank;
  final _Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final tool = suggestion.tool;
    return ToolLink(
      tool: tool,
      builder: (context, open) => _card(context, open),
    );
  }

  Widget _card(BuildContext context, VoidCallback open) {
    final p = context.liz;
    final tool = suggestion.tool;
    return LizCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: LizText.title3.copyWith(
                    color: p.textSecondary,
                    fontFeatures: LizText.tabular,
                  ),
                ),
              ),
              ToolLogo(tool: tool, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      style: LizText.headline.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.callout.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ToolMeta(tool),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(10, -10),
                child: BookmarkButton(toolId: tool.id),
              ),
            ],
          ),
          if (suggestion.reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: ShapeDecoration(
                color: p.surfaceMuted,
                shape: LizRadius.shape(LizRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.auto_awesome, size: 16, color: p.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion.reason,
                      style: LizText.callout.copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// While Liz looks, the shape of three answers.
class _ThinkingRows extends StatelessWidget {
  const _ThinkingRows();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Finding tools',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Shimmer(
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SkeletonBox(height: 96, radius: LizRadius.md),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: p.caution.withValues(alpha: 0.10),
        shape: LizRadius.shape(LizRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_bottom, size: 20, color: p.caution),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: LizText.callout.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.controller,
    required this.examples,
    required this.onSubmit,
    required this.onPick,
  });

  final TextEditingController controller;
  final List<String> examples;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onPick;

  static const _icons = [
    Icons.image_outlined,
    Icons.movie_outlined,
    Icons.code,
    Icons.mic_none,
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: ShapeDecoration(
                  color: p.accentSoft,
                  shape: LizRadius.shape(16),
                ),
                child: Icon(Icons.auto_awesome, size: 28, color: p.accent),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  'What do you want to do?',
                  textAlign: TextAlign.center,
                  style: (phone ? LizText.title1 : LizText.largeTitle).copyWith(
                    color: p.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Describe it in plain words. Liz finds the tools that fit '
                'and says why.',
                textAlign: TextAlign.center,
                style: LizText.body.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 28),
              _Composer(controller: controller, onSubmit: onSubmit),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 520 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < examples.length; i++)
                        SizedBox(
                          width: width,
                          child: LizCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            onTap: () => onPick(examples[i]),
                            child: Row(
                              children: [
                                Icon(
                                  _icons[i % _icons.length],
                                  size: 20,
                                  color: p.textSecondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    examples[i],
                                    style: LizText.callout.copyWith(
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.north_east,
                                  size: 16,
                                  color: p.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large field of the start page, with its send button inside it.
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.lg,
          side: BorderSide(color: p.hairlineStrong),
        ),
        shadows: LizShadows.raised(p),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmit,
                style: LizText.body.copyWith(color: p.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'e.g. free AI tool for transcription',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            _SendButton(onPressed: () => onSubmit(controller.text)),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // An icon-only button has no name of its own, so a screen reader
    // announced this as just "button". The name has to sit on the icon: a
    // button merges its children's semantics into its own node, while a
    // wrapping Tooltip labels a separate node above it and leaves the
    // tappable one nameless — which the accessibility test caught. The
    // tooltip stays as the hover hint.
    return Tooltip(
      message: 'Ask Liz',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: const Icon(Icons.arrow_upward, semanticLabel: 'Ask Liz'),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        8,
        gutter,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _Composer(controller: controller, onSubmit: onSubmit),
    );
  }
}
