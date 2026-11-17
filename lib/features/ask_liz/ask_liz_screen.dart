import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/ambient.dart';
import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/equal_height_grid.dart';
import '../../shared/widgets/liz_card.dart';
import '../../shared/widgets/liz_mark.dart';
import '../../shared/widgets/liz_notice.dart';
import '../../shared/widgets/page_header.dart';
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

  void _reset() => setState(() {
    _answered = null;
    _results = [];
    _notice = null;
    _controller.clear();
  });

  // An open page: it asks for the full ambient light (ambient.dart).
  @override
  Widget build(BuildContext context) =>
      AmbientLevel(full: _answered == null, child: _page(context));

  Widget _page(BuildContext context) {
    final p = context.liz;
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    void pick(String q) {
      _controller.text = q;
      _ask(q);
    }

    // Before a question, the page is the question: a title, the field in the
    // middle of it, and a few examples. Afterwards the field moves to a bar
    // along the foot of the page and the answer takes its place.
    if (_answered == null) {
      return Scaffold(
        appBar: phone ? const PhoneBar() : null,
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

    final String status;
    if (_loading) {
      status = 'Looking through the catalog…';
    } else if (_notice != null) {
      status = 'No answer this time.';
    } else if (_results.isEmpty) {
      status = 'Nothing in the catalog fits well enough.';
    } else {
      final n = _results.length;
      status = n == 1 ? 'One tool fits.' : '$n tools fit, best first.';
    }

    return Scaffold(
      appBar: phone ? const PhoneBar() : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MaxWidth(
                maxWidth: 760 + gutter * 2,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    phone ? 12 : 36,
                    gutter,
                    32,
                  ),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                container: true,
                                header: true,
                                headingLevel: 1,
                                child: Text(
                                  '“${_answered!}”',
                                  style:
                                      (phone ? LizText.title2 : LizText.title1)
                                          .copyWith(color: p.textPrimary),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                status,
                                style: LizText.body.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (phone)
                          IconButton.outlined(
                            tooltip: 'New question',
                            onPressed: _reset,
                            icon: const Icon(Icons.add),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _reset,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New question'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_loading)
                      const _ThinkingRows()
                    else if (_notice != null)
                      LizNotice(
                        text: _notice!,
                        color: p.caution,
                        icon: Icons.hourglass_bottom,
                      )
                    else if (_results.isEmpty)
                      _NoMatch(query: _answered!)
                    else ...[
                      Semantics(
                        container: true,
                        header: true,
                        child: Text(
                          "Here's what fits best",
                          style: LizText.title3.copyWith(color: p.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Panel(
                        child: Column(
                          children: [
                            for (var i = 0; i < _results.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: p.hairline),
                              _Answer(rank: i + 1, suggestion: _results[i]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Picked from the tools Liz tracks, by what they '
                        'say they do. Check pricing on each tool’s page.',
                        style: LizText.footnote.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _InputBar(controller: _controller, onSubmit: _ask),
          ],
        ),
      ),
    );
  }
}

/// The frame round the answers, and round their placeholders.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(LizRadius.md),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// One answer, as a row of the list: its place, the tool, and why it fits
/// in Liz's voice under it.
class _Answer extends StatelessWidget {
  const _Answer({required this.rank, required this.suggestion});
  final int rank;
  final _Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final tool = suggestion.tool;
    return ToolLink(
      tool: tool,
      builder: (context, open) => _row(context, open),
    );
  }

  Widget _row(BuildContext context, VoidCallback open) {
    final p = context.liz;
    final tool = suggestion.tool;
    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '$rank',
                  style: LizText.headline.copyWith(
                    color: p.textSecondary,
                    fontFeatures: LizText.tabular,
                  ),
                ),
              ),
            ),
            ToolLogo(tool: tool, size: 44),
            const SizedBox(width: 14),
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
                  if (suggestion.reason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: LizMark.icon(size: 14, color: p.accent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion.reason,
                            style: LizText.callout.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            BookmarkButton(toolId: tool.id),
          ],
        ),
      ),
    );
  }
}

/// While Liz looks, the shape of three answers in the answers' frame.
class _ThinkingRows extends StatelessWidget {
  const _ThinkingRows();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      container: true,
      label: 'Finding tools',
      liveRegion: true,
      child: ExcludeSemantics(
        child: _Panel(
          child: Shimmer(
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.hairline),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(44, 16, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 44, height: 44),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 140, height: 16),
                              SizedBox(height: 8),
                              SkeletonBox(height: 14),
                              SizedBox(height: 14),
                              SkeletonBox(width: 220, height: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing fits: say so, and offer the catalog's own search for the words.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.search_off, size: 20, color: p.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "I couldn't find a great match for that. Try describing "
                    'what you want to do.',
                    style: LizText.callout.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: OutlinedButton(
                onPressed: () => context.push(
                  '/search?q=${Uri.encodeQueryComponent(query)}',
                ),
                child: const Text('Search the catalog'),
              ),
            ),
          ],
        ),
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
                  color: p.surface,
                  shape: LizRadius.shape(
                    16,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
                alignment: Alignment.center,
                child: const LizMark(size: 30),
              ),
              const SizedBox(height: 20),
              Semantics(
                container: true,
                header: true,
                headingLevel: 1,
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
                  return EqualHeightGrid(
                    columns: columns,
                    spacing: 12,
                    children: [
                      for (var i = 0; i < examples.length; i++)
                        SizedBox(
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
                                  Icons.arrow_forward,
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
  const _Composer({
    required this.controller,
    required this.onSubmit,
    this.raised = true,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool raised;

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
        shadows: raised ? LizShadows.raised(p) : null,
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

/// The question box after an answer: a bar along the foot of the page, as
/// on a post.
class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760 + gutter * 2),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              12,
              gutter,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _Composer(
              controller: controller,
              onSubmit: onSubmit,
              raised: false,
            ),
          ),
        ),
      ),
    );
  }
}
