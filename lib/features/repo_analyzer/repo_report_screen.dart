import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/top_bar.dart';
import 'graph_view.dart';
import 'repo_ask.dart';
import 'repo_code.dart';
import 'repo_models.dart';
import 'repo_service.dart';

/// One analysis (`/repos/:id`): its progress while it runs, then the report
/// in tabs — the written sections, the diagrams, the code, the stack, the
/// API, the data, build and deployment, security and quality, and Ask.
class RepoReportScreen extends ConsumerStatefulWidget {
  const RepoReportScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RepoReportScreen> createState() => _RepoReportScreenState();
}

enum _Tab {
  overview,
  architecture,
  code,
  stack,
  api,
  data,
  build,
  security,
  ask,
}

const _tabNames = {
  _Tab.overview: 'Overview',
  _Tab.architecture: 'Architecture',
  _Tab.code: 'Code',
  _Tab.stack: 'Stack',
  _Tab.api: 'API',
  _Tab.data: 'Data',
  _Tab.build: 'Build & deploy',
  _Tab.security: 'Security & quality',
  _Tab.ask: 'Ask',
};

class _RepoReportScreenState extends ConsumerState<RepoReportScreen> {
  RepoAnalysis? _analysis;
  Object? _error;
  Timer? _poll;
  _Tab _tab = _Tab.overview;
  RepoAskController? _ask;
  bool _restarting = false;

  RepoAnalyzerService get _service => ref.read(repoAnalyzerServiceProvider)!;

  @override
  void initState() {
    super.initState();
    if (ref.read(repoAnalyzerServiceProvider) != null) _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ask?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await _service.get(widget.id);
      if (!mounted) return;
      setState(() {
        _analysis = a;
        _error = null;
      });
      _poll?.cancel();
      if (a.summary.inProgress) {
        _poll = Timer(const Duration(seconds: 2), _load);
      } else if (a.summary.status == AnalysisStatus.done) {
        _ask ??= RepoAskController(_service, widget.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _restart() async {
    final a = _analysis!;
    setState(() => _restarting = true);
    try {
      final id = await _service.start(
        'https://github.com/${a.summary.fullName}',
        ref: a.summary.ref,
      );
      if (mounted) context.go('/repos/$id');
    } on RepoAnalyzerException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _restarting = false);
      }
    }
  }

  void _explain(String question, {String? focus}) {
    final c = _ask;
    if (c == null) return;
    setState(() => _tab = _Tab.ask);
    c.ask(question, focus: focus);
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    return Scaffold(
      appBar: LizTopBar(
        title: a?.summary.fullName,
        section: const ('Repositories', '/repos'),
        fallback: '/repos',
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (ref.watch(repoAnalyzerServiceProvider) == null) {
      return const EmptyView(
        icon: Icons.cloud_off_outlined,
        title: 'Needs the live backend',
        message:
            'Analysing repositories reads them from GitHub and keeps the report, which this demo copy of Liz cannot do.',
      );
    }
    final a = _analysis;
    if (a == null) {
      if (_error != null) {
        final notFound =
            _error is RepoAnalyzerException &&
            (_error as RepoAnalyzerException).status == 404;
        return notFound
            ? EmptyView(
                icon: Icons.search_off,
                title: 'No such analysis',
                message: (_error as RepoAnalyzerException).message,
              )
            : ErrorView(
                onRetry: _load,
                message: 'The report could not be loaded.',
              );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final s = a.summary;
    if (s.inProgress) return _Running(summary: s);
    if (s.status == AnalysisStatus.failed || s.stalled) {
      return _Failed(summary: s, busy: _restarting, onRetry: _restart);
    }
    return _Report(
      analysis: a,
      tab: _tab,
      onTab: (t) => setState(() => _tab = t),
      ask: _ask!,
      explain: _explain,
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.summary});
  final AnalysisSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analysing ${summary.fullName}',
                style: LizText.title2.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '${summary.ref}${summary.shortSha.isNotEmpty ? ' · ${summary.shortSha}' : ''}',
                style: LizText.mono.copyWith(
                  fontSize: 12.5,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                label: 'Progress',
                value: '${summary.progress}%',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.progress / 100,
                    minHeight: 6,
                    backgroundColor: p.surfaceMuted,
                    color: p.accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.stage ?? 'Starting',
                      style: LizText.callout.copyWith(color: p.textPrimary),
                    ),
                  ),
                  Text(
                    '${summary.progress}%',
                    style: LizText.callout.copyWith(
                      color: p.textSecondary,
                      fontFeatures: LizText.tabular,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This usually takes under a minute. You can leave this page; the analysis keeps going and waits in Repositories.',
                style: LizText.footnote.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.summary,
    required this.busy,
    required this.onRetry,
  });
  final AnalysisSummary summary;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.error_outline,
      title: 'The analysis did not finish',
      message: summary.stalled
          ? 'It stopped before finishing. Large repositories sometimes run out of time; trying again re-uses the files already read.'
          : summary.error ?? 'Something went wrong.',
      action: FilledButton(
        onPressed: busy ? null : onRetry,
        child: Text(busy ? 'Starting…' : 'Try again'),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({
    required this.analysis,
    required this.tab,
    required this.onTab,
    required this.ask,
    required this.explain,
  });
  final RepoAnalysis analysis;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;
  final RepoAskController ask;
  final void Function(String question, {String? focus}) explain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final a = analysis;
    final stats = a.stats;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: MaxWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: a.summary.fullName,
                  subtitle: a.description ?? a.section('description')?.summary,
                  bottom: 12,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Fact(Icons.call_split, a.summary.ref),
                      if (a.summary.shortSha.isNotEmpty)
                        _Fact(Icons.commit, a.summary.shortSha, mono: true),
                      _Fact(
                        Icons.description_outlined,
                        '${stats['read'] ?? 0} of ${stats['files'] ?? 0} files read',
                      ),
                      if ((stats['reused'] ?? 0) as num > 0)
                        _Fact(Icons.recycling, '${stats['reused']} reused'),
                      if (a.stars > 0) _Fact(Icons.star_outline, '${a.stars}'),
                      if (a.license != null) _Fact(Icons.balance, a.license!),
                      if (a.summary.isPrivate)
                        const _Fact(Icons.lock_outline, 'Private'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Every tab built at once (a short row), so all are findable.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: Row(
                    children: [
                      for (final t in _Tab.values) ...[
                        LizFilterPill(
                          label: _tabNames[t]!,
                          selected: t == tab,
                          onTap: () => onTab(t),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Divider(height: 24, color: p.hairline),
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 48),
                  child: switch (tab) {
                    _Tab.overview => _Overview(analysis: a, explain: explain),
                    _Tab.architecture => _Architecture(
                      analysis: a,
                      explain: explain,
                    ),
                    _Tab.code => CodeExplorer(analysis: a),
                    _Tab.stack => _Stack(analysis: a, explain: explain),
                    _Tab.api => _Api(analysis: a, explain: explain),
                    _Tab.data => _Data(analysis: a, explain: explain),
                    _Tab.build => _Build(analysis: a, explain: explain),
                    _Tab.security => _Sections(
                      analysis: a,
                      ids: const [
                        'security',
                        'quality',
                        'performance',
                        'strengths',
                        'improvements',
                      ],
                    ),
                    _Tab.ask => AskPanel(controller: ask),
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.mono = false});
  final IconData icon;
  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: p.surfaceMuted,
        shape: LizRadius.shape(
          LizRadius.xs,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.textSecondary),
          const SizedBox(width: 6),
          // A long branch name ends in an ellipsis rather than overflowing.
          Flexible(
            child: Text(
              text,
              style:
                  (mono
                          ? LizText.mono.copyWith(fontSize: 12)
                          : LizText.footnote)
                      .copyWith(color: p.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading inside a tab.
class _H extends StatelessWidget {
  const _H(this.text, {this.sub, this.action});
  final String text;
  final String? sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: text,
    subtitle: sub,
    action: action,
    padding: const EdgeInsets.only(top: 20, bottom: 10),
  );
}

/// A section of the written report: its summary and items, each item with
/// the files it came from.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.section,
    required this.analysisId,
    this.initiallyOpen = false,
    this.index,
  });
  final ReportSection section;
  final String analysisId;
  final bool initiallyOpen;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyOpen,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(
              index == null ? section.title : '${index! + 1}. ${section.title}',
              style: LizText.headline.copyWith(color: p.textPrimary),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                section.summary,
                style: LizText.callout.copyWith(color: p.textSecondary),
              ),
            ),
            children: [
              if (section.items.isEmpty)
                Text(
                  'Nothing more to list.',
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              for (final item in section.items)
                _ItemRow(item: item, analysisId: analysisId),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.analysisId});
  final ReportItem item;
  final String analysisId;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: LizText.subhead.copyWith(color: p.textPrimary),
          ),
          if (item.value != null && item.value!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.value!,
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
          ],
          if (item.refs.isNotEmpty) ...[
            const SizedBox(height: 6),
            RefChips(analysisId: analysisId, refs: item.refs, max: 4),
          ],
        ],
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.analysis, required this.ids});
  final RepoAnalysis analysis;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in ids)
          if (analysis.section(id) != null)
            SectionCard(
              section: analysis.section(id)!,
              analysisId: analysis.summary.id,
              initiallyOpen: true,
            ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final n = analysis.narrative;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (n != null)
          DecoratedBox(
            decoration: ShapeDecoration(
              color: p.surface,
              shape: LizRadius.shape(
                LizRadius.md,
                side: BorderSide(color: p.hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                        color: p.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'In short',
                        style: LizText.caption.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    n.overview,
                    style: LizText.body.copyWith(
                      color: p.textPrimary,
                      height: 1.55,
                    ),
                  ),
                  if (n.howItWorks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      n.howItWorks,
                      style: LizText.body.copyWith(
                        color: p.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ],
                  if (n.learnToBuild.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'To build something similar, learn',
                      style: LizText.subhead.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in n.learnToBuild) Chip(label: Text(t)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Written by an AI model from the facts below.',
                    style: LizText.label.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        _H(
          'The full report',
          sub:
              '${analysis.sections.length} sections, each from what was found in the repository.',
        ),
        for (final (i, s) in analysis.sections.indexed)
          SectionCard(
            section: s,
            analysisId: analysis.summary.id,
            index: i,
            initiallyOpen: i < 2,
          ),
      ],
    );
  }
}

class _Architecture extends StatefulWidget {
  const _Architecture({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  State<_Architecture> createState() => _ArchitectureState();
}

/// The diagrams' names, short enough for a phone's row of pills.
const _shortName = {
  'system': 'System',
  'modules': 'Modules',
  'database': 'Database',
  'api': 'API',
  'auth': 'Sign-in',
};

class _ArchitectureState extends State<_Architecture> {
  late String? _graph = widget.analysis.graphs.isEmpty
      ? null
      : widget.analysis.graphs.first.id;
  GraphNode? _node;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = widget.analysis;
    final g = _graph == null ? null : a.graph(_graph!);
    if (g == null) {
      return const EmptyView(
        icon: Icons.account_tree_outlined,
        title: 'No diagram',
        message:
            'Not enough was found in the repository to draw its architecture.',
      );
    }
    final node = _node;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final x in a.graphs)
              LizFilterPill(
                label: _shortName[x.id] ?? x.title,
                semanticLabel: x.title,
                selected: x.id == g.id,
                onTap: () => setState(() {
                  _graph = x.id;
                  _node = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GraphView(
          graph: g,
          selected: node?.id,
          onSelect: (n) => setState(() => _node = n),
          height: context.isPhone ? 380 : 480,
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                g.note,
                style: LizText.footnote.copyWith(color: p.textSecondary),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: g.mermaid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied as Mermaid')),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Copy as Mermaid'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (node == null)
          Text(
            'Tap a part of the diagram to see what it is and where it was found.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          )
        else
          DecoratedBox(
            decoration: ShapeDecoration(
              color: p.surface,
              shape: LizRadius.shape(
                LizRadius.md,
                side: BorderSide(color: p.hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(kindIcon(node.kind), size: 18, color: p.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.label.replaceAll('\n', ' · '),
                          style: LizText.headline.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (node.detail != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      node.detail!,
                      style: LizText.callout.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 10),
                  RefChips(analysisId: a.summary.id, refs: node.refs),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => widget.explain(
                      'Explain "${node.label.replaceAll('\n', ' ')}" in this repository: what it does, how it is used, and how it connects to the rest.',
                      focus: node.refs.isEmpty
                          ? (node.kind == 'module' ? node.id : null)
                          : splitRef(node.refs.first).$1,
                    ),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('Explain this'),
                  ),
                ],
              ),
            ),
          ),
        _H(
          'Modules',
          sub: '${a.modules.length} parts of the code and what each is for.',
        ),
        for (final m in a.modules.take(30))
          _ModuleRow(
            module: m,
            analysisId: a.summary.id,
            onExplain: () => widget.explain(
              'What does the module ${m.path} do? Explain its important files and how the rest of the code uses it.',
              focus: m.path,
            ),
          ),
      ],
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.module,
    required this.analysisId,
    required this.onExplain,
  });
  final Module module;
  final String analysisId;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final m = module;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.path,
                  style: LizText.mono.copyWith(
                    fontSize: 13,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Text(
                '${m.files} files',
                style: LizText.label.copyWith(color: p.textSecondary),
              ),
              IconButton(
                tooltip: 'Explain ${m.path}',
                onPressed: onExplain,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              ),
            ],
          ),
          Text(
            [
              m.role,
              if (m.languages.isNotEmpty) m.languages.join(', '),
            ].join(' · '),
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
          if (m.imports.isNotEmpty || m.importedBy.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (m.imports.isNotEmpty)
                  'Uses ${m.imports.take(4).join(', ')}',
                if (m.importedBy.isNotEmpty)
                  'used by ${m.importedBy.take(4).join(', ')}',
              ].join('; '),
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ],
          if (m.keyFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            RefChips(analysisId: analysisId, refs: m.keyFiles, max: 4),
          ],
        ],
      ),
    );
  }
}

class _Stack extends StatelessWidget {
  const _Stack({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = analysis;
    final langs = a.languages.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final total = langs.fold<int>(0, (s, e) => s + e.value);
    final byCat = <String, List<Tech>>{};
    for (final t in a.techs) {
      byCat.putIfAbsent(t.category, () => []).add(t);
    }
    final palette = [
      p.accent,
      p.textPrimary,
      p.textSecondary,
      p.caution,
      p.positive,
      p.textSecondary,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _H('Languages'),
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final (i, e) in langs.take(6).indexed)
                    Expanded(
                      flex: (e.value * 1000 ~/ total).clamp(1, 1000),
                      child: ColoredBox(color: palette[i]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (i, e) in langs.take(10).indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette[i.clamp(0, 5)],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${e.key} ${(e.value * 100 / total).toStringAsFixed(1)}%',
                      style: LizText.footnote.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
        ] else
          Text(
            'GitHub reported no languages.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
        _H(
          'Technologies',
          sub:
              'Confirmed by a dependency or configuration file, or inferred from code (marked).',
        ),
        if (byCat.isEmpty)
          Text(
            'None identified.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
        for (final entry in byCat.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              entry.key.toUpperCase(),
              style: LizText.caption.copyWith(color: p.textSecondary),
            ),
          ),
          for (final t in entry.value)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: ShapeDecoration(
                color: p.surface,
                shape: LizRadius.shape(
                  LizRadius.md,
                  side: BorderSide(color: p.hairline),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          style: LizText.headline.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      _Badge(
                        t.confirmed ? 'Confirmed' : 'Inferred',
                        strong: t.confirmed,
                      ),
                      IconButton(
                        tooltip: 'Why ${t.name}?',
                        onPressed: () => explain(
                          'Why is ${t.name} used in this project, and where?',
                          focus: t.evidence.isEmpty
                              ? null
                              : splitRef(t.evidence.first).$1,
                        ),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      ),
                    ],
                  ),
                  Text(
                    t.purpose,
                    style: LizText.callout.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  RefChips(analysisId: a.summary.id, refs: t.evidence, max: 3),
                ],
              ),
            ),
        ],
        if (a.section('dependencies') != null) ...[
          const SizedBox(height: 8),
          _Dependencies(
            section: a.section('dependencies')!,
            analysisId: a.summary.id,
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: strong ? p.surfaceHover : Colors.transparent,
        shape: LizRadius.shape(
          LizRadius.xs,
          side: BorderSide(color: strong ? p.hairlineStrong : p.hairline),
        ),
      ),
      child: Text(
        text,
        style: LizText.label.copyWith(
          color: strong ? p.textPrimary : p.textSecondary,
        ),
      ),
    );
  }
}

class _Dependencies extends StatefulWidget {
  const _Dependencies({required this.section, required this.analysisId});
  final ReportSection section;
  final String analysisId;

  @override
  State<_Dependencies> createState() => _DependenciesState();
}

class _DependenciesState extends State<_Dependencies> {
  String _q = '';
  bool _dev = true;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final items = widget.section.items
        .where(
          (i) =>
              (_dev || !i.label.endsWith('(dev)')) &&
              i.label.toLowerCase().contains(_q.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _H('Dependencies', sub: widget.section.summary),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Filter dependencies',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            const SizedBox(width: 12),
            LizFilterPill(
              label: 'Include dev',
              selected: _dev,
              onTap: () => setState(() => _dev = !_dev),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final i in items.take(200))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    i.label,
                    style: LizText.mono.copyWith(
                      fontSize: 12.5,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    i.value ?? '',
                    style: LizText.footnote.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (items.isEmpty)
          Text(
            'No dependency matches.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
      ],
    );
  }
}

class _Api extends StatefulWidget {
  const _Api({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  State<_Api> createState() => _ApiState();
}

class _ApiState extends State<_Api> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = widget.analysis;
    if (a.endpoints.isEmpty) {
      return EmptyView(
        icon: Icons.alt_route,
        title: 'No API routes found',
        message: a.section('api')?.summary,
      );
    }
    final list = a.endpoints
        .where(
          (e) => '${e.method} ${e.route} ${e.path}'.toLowerCase().contains(
            _q.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          a.section('api')?.summary ?? '',
          style: LizText.callout.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Filter routes',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        const SizedBox(height: 10),
        for (final e in list.take(200))
          InkWell(
            onTap: () => widget.explain(
              'Explain the endpoint ${e.method} ${e.route}: what a request must contain, what it does, and what it answers.',
              focus: e.path,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.hairline)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      e.method,
                      style: LizText.mono.copyWith(
                        fontSize: 12,
                        color: p.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.route,
                          style: LizText.mono.copyWith(
                            fontSize: 13,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          e.framework,
                          style: LizText.label.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (!context.isPhone)
                    RefChip(analysisId: a.summary.id, reference: e.ref),
                  Icon(Icons.chevron_right, color: p.textSecondary),
                ],
              ),
            ),
          ),
        if (a.graph('api') != null) ...[
          const _H('Routes by area'),
          _StaticGraph(graph: a.graph('api')!, analysisId: a.summary.id),
        ],
      ],
    );
  }
}

/// A diagram with its own selection, for tabs that show one.
class _StaticGraph extends StatefulWidget {
  const _StaticGraph({required this.graph, required this.analysisId});
  final ArchGraph graph;
  final String analysisId;

  @override
  State<_StaticGraph> createState() => _StaticGraphState();
}

class _StaticGraphState extends State<_StaticGraph> {
  GraphNode? _node;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GraphView(
          graph: widget.graph,
          selected: _node?.id,
          onSelect: (n) => setState(() => _node = n),
          height: 420,
        ),
        const SizedBox(height: 8),
        if (_node != null) ...[
          Text(
            _node!.label.replaceAll('\n', ' · '),
            style: LizText.headline.copyWith(color: p.textPrimary),
          ),
          if (_node!.detail != null)
            Text(
              _node!.detail!,
              style: LizText.mono.copyWith(
                fontSize: 12,
                color: p.textSecondary,
              ),
            ),
          const SizedBox(height: 6),
          RefChips(analysisId: widget.analysisId, refs: _node!.refs),
        ] else
          Text(
            widget.graph.note,
            style: LizText.footnote.copyWith(color: p.textSecondary),
          ),
      ],
    );
  }
}

class _Data extends StatelessWidget {
  const _Data({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = analysis;
    if (a.entities.isEmpty) {
      return EmptyView(
        icon: Icons.storage_outlined,
        title: 'No schema found',
        message: a.section('database')?.summary,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          a.section('database')?.summary ?? '',
          style: LizText.callout.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        if (a.graph('database') != null)
          _StaticGraph(graph: a.graph('database')!, analysisId: a.summary.id),
        _H(
          'Tables and models',
          action: TextButton.icon(
            onPressed: () => explain(
              'Explain the database: its main tables, how they relate, and how the code reads and writes them.',
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: const Text('Explain'),
          ),
        ),
        for (final e in a.entities)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: ShapeDecoration(
              color: p.surface,
              shape: LizRadius.shape(
                LizRadius.md,
                side: BorderSide(color: p.hairline),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        style: LizText.mono.copyWith(
                          fontSize: 13.5,
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _Badge(e.source),
                  ],
                ),
                const SizedBox(height: 6),
                RefChip(
                  analysisId: a.summary.id,
                  reference: '${e.path}:${e.line}',
                ),
                if (e.columns.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final (name, type) in e.columns)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: name,
                                style: LizText.mono.copyWith(
                                  fontSize: 12,
                                  color: p.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: ' $type',
                                style: LizText.mono.copyWith(
                                  fontSize: 12,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Build extends StatelessWidget {
  const _Build({required this.analysis, required this.explain});
  final RepoAnalysis analysis;
  final void Function(String, {String? focus}) explain;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => explain(
                'How can I run this project locally? Give the steps in order, with the settings it needs.',
              ),
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: const Text('How do I run it?'),
            ),
            OutlinedButton.icon(
              onPressed: () => explain(
                'How is this project built and deployed? Walk through the pipeline step by step.',
              ),
              icon: const Icon(Icons.rocket_launch_outlined, size: 18),
              label: const Text('How is it deployed?'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Sections(analysis: a, ids: const ['build', 'deployment']),
        if (a.workflows.isNotEmpty) ...[
          const _H('CI/CD workflows'),
          for (final w in a.workflows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: ShapeDecoration(
                color: p.surface,
                shape: LizRadius.shape(
                  LizRadius.md,
                  side: BorderSide(color: p.hairline),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${w['name']}',
                          style: LizText.headline.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      Flexible(
                        child: RefChip(
                          analysisId: a.summary.id,
                          reference: '${w['path']}',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'On ${(w['triggers'] as List? ?? const []).join(', ')}',
                    style: LizText.footnote.copyWith(color: p.textSecondary),
                  ),
                  for (final j
                      in (w['jobs'] as List? ?? const []).whereType<Map>()) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${j['name']}',
                      style: LizText.subhead.copyWith(color: p.textPrimary),
                    ),
                    for (final s in (j['steps'] as List? ?? const []).take(10))
                      Padding(
                        padding: const EdgeInsets.only(left: 10, top: 2),
                        child: Text(
                          '· $s',
                          style: LizText.mono.copyWith(
                            fontSize: 12,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
        if (a.env.isNotEmpty) ...[
          const _H(
            'Settings it reads',
            sub:
                'Names only; values are never shown. Marked ones are listed in a committed example file.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in a.env)
                Tooltip(
                  message: (e['refs'] as List? ?? const [])
                      .whereType<Map>()
                      .map((r) => '${r['path']}:${r['line']}')
                      .join('\n'),
                  child: _Badge(
                    '${e['name']}${e['documented'] == true ? ' ✓' : ''}',
                    strong: e['documented'] == true,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
