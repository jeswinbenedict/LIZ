import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/liz_card.dart';
import '../../shared/widgets/liz_notice.dart';
import '../../shared/widgets/liz_sheet.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import 'repo_models.dart';
import 'repo_service.dart';

/// Whether text is a GitHub repository address the server will accept
/// (the same shapes as supabase/functions/_shared/repo/url.ts).
bool looksLikeRepo(String s) {
  final t = s.trim();
  return RegExp(
        r'^(https?://)?(www\.)?github\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+(\.git)?(/.*)?$',
      ).hasMatch(t) ||
      RegExp(
        r'^git@github\.com:[A-Za-z0-9-]+/[A-Za-z0-9._-]+(\.git)?$',
      ).hasMatch(t) ||
      RegExp(r'^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$').hasMatch(t);
}

/// The Repository Analyzer (`/repos`): paste a GitHub address, choose a
/// branch, start; past analyses are listed below to revisit.
class RepoAnalyzerScreen extends ConsumerStatefulWidget {
  const RepoAnalyzerScreen({super.key});

  @override
  ConsumerState<RepoAnalyzerScreen> createState() => _RepoAnalyzerScreenState();
}

class _RepoAnalyzerScreenState extends ConsumerState<RepoAnalyzerScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _private = false;
  bool _starting = false;
  String? _error;
  RepoBranches? _branches;
  String? _branch;
  bool _loadingBranches = false;
  String? _branchesFor;
  List<AnalysisSummary>? _history;
  Object? _historyError;
  Timer? _refresh;

  RepoAnalyzerService? get _service => ref.read(repoAnalyzerServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final s = _service;
    if (s == null) return;
    try {
      final rows = await s.mine();
      if (!mounted) return;
      setState(() {
        _history = rows;
        _historyError = null;
      });
      _refresh?.cancel();
      // Keep running rows moving while the page is open.
      if (rows.any((r) => r.inProgress)) {
        _refresh = Timer(const Duration(seconds: 3), _loadHistory);
      }
    } catch (e) {
      if (mounted) setState(() => _historyError = e);
    }
  }

  Future<void> _loadBranches() async {
    final url = _url.text.trim();
    final s = _service;
    if (s == null || !looksLikeRepo(url) || _branchesFor == url) return;
    setState(() {
      _loadingBranches = true;
      _branchesFor = url;
      _error = null;
    });
    try {
      final b = await s.branches(
        url,
        token: _private ? _token.text.trim() : null,
      );
      if (!mounted || _url.text.trim() != url) return;
      setState(() {
        _branches = b;
        _branch = b.defaultBranch;
        if (b.isPrivate && !_private) _private = true;
      });
    } on RepoAnalyzerException catch (e) {
      if (!mounted) return;
      setState(() {
        _branches = null;
        _error = e.message;
        if (e.code == 'not_found' && !_private) _private = true;
      });
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _start() async {
    final url = _url.text.trim();
    if (!looksLikeRepo(url)) {
      setState(
        () => _error =
            'Paste a GitHub repository address, like https://github.com/owner/name.',
      );
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final id = await _service!.start(
        url,
        ref: _branch != null && _branch != _branches?.defaultBranch
            ? _branch
            : null,
        token: _private ? _token.text.trim() : null,
      );
      _token.clear();
      if (mounted) context.push('/repos/$id').then((_) => _loadHistory());
    } on RepoAnalyzerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _delete(AnalysisSummary a) async {
    final ok = await showLizConfirm(
      context,
      title: 'Delete this analysis?',
      message:
          'The report on ${a.fullName} and the files it read are removed for good.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _service!.delete(a.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete it. Try again.')),
        );
      }
    }
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final live = ref.watch(repoAnalyzerServiceProvider) != null;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: MaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageHeader(
                    title: 'Repository Analyzer',
                    subtitle:
                        'Paste a GitHub repository. Liz reads its code and explains how it was built: '
                        'the stack, the architecture, the data, the API, and how it is built and deployed.',
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: live ? _form(p) : const _DemoNotice(),
                  ),
                  if (live) ...[
                    const SectionHeader(title: 'Your analyses'),
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
                      child: _historyList(p),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(LizPalette p) {
    final wide = !context.isPhone;
    final branchField = DropdownButtonFormField<String>(
      key: ValueKey(_branches?.fullName),
      initialValue: _branch,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Branch',
        prefixIcon: const Icon(Icons.call_split),
        suffixIcon: _loadingBranches
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: const Text('Default branch'),
      items: [
        for (final b in _branches?.branches ?? const <String>[])
          DropdownMenuItem(
            value: b,
            child: Text(
              b == _branches?.defaultBranch ? '$b (default)' : b,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _branches == null ? null : (v) => setState(() => _branch = v),
    );
    // Material, not a decorated box: the switch's ink needs a surface.
    return Material(
      color: p.surface,
      shape: LizRadius.shape(LizRadius.lg, side: BorderSide(color: p.hairline)),
      child: Padding(
        padding: EdgeInsets.all(wide ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              onFocusChange: (has) {
                if (!has) _loadBranches();
              },
              child: TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _start(),
                onChanged: (_) {
                  if (_branches != null || _error != null) {
                    setState(() {
                      _branches = null;
                      _branch = null;
                      _branchesFor = null;
                      _error = null;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'GitHub repository',
                  hintText: 'https://github.com/owner/name',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (wide)
              Row(
                children: [
                  Expanded(child: branchField),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _loadingBranches ? null : _loadBranches,
                    child: const Text('Load branches'),
                  ),
                ],
              )
            else ...[
              branchField,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _loadingBranches ? null : _loadBranches,
                  child: const Text('Load branches'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _private,
              onChanged: (v) => setState(() => _private = v),
              title: Text(
                'Private repository',
                style: LizText.callout.copyWith(color: p.textPrimary),
              ),
              subtitle: Text(
                'Analyse it with a GitHub token that can read it.',
                style: LizText.footnote.copyWith(color: p.textSecondary),
              ),
            ),
            if (_private) ...[
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'GitHub token',
                  helperText:
                      'A fine-grained token with read-only access to Contents and Metadata. '
                      'Used for this analysis only: it is never stored.',
                  helperMaxLines: 3,
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              LizNotice(
                text: _error!,
                color: p.danger,
                icon: Icons.error_outline,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: _starting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.travel_explore),
                label: Text(_starting ? 'Starting…' : 'Analyse repository'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Liz reads source, configuration, documentation and schemas, up to 180 files; it never runs the code. '
              'Secrets found in files are removed from the report.',
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyList(LizPalette p) {
    final h = _history;
    if (_historyError != null && h == null) {
      return ErrorView(
        onRetry: _loadHistory,
        message: 'Your analyses could not be loaded.',
      );
    }
    if (h == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (h.isEmpty) {
      return Text(
        'Nothing yet. Analyse a repository above and its report will be kept here.',
        style: LizText.callout.copyWith(color: p.textSecondary),
      );
    }
    return Column(
      children: [
        for (final a in h)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LizCard(
              onTap: () =>
                  context.push('/repos/${a.id}').then((_) => _loadHistory()),
              semanticLabel: '${a.fullName}, ${_statusText(a)}',
              child: Row(
                children: [
                  Icon(
                    a.isPrivate
                        ? Icons.lock_outline
                        : Icons.folder_open_outlined,
                    color: p.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.fullName,
                          style: LizText.headline.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${a.ref}${a.shortSha.isNotEmpty ? ' · ${a.shortSha}' : ''} · ${timeAgo(a.createdAt)}',
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        if (a.inProgress) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: a.progress / 100,
                            minHeight: 3,
                            color: p.accent,
                            backgroundColor: p.surfaceMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _statusText(a),
                    style: LizText.footnote.copyWith(
                      color: a.status == AnalysisStatus.failed || a.stalled
                          ? p.danger
                          : p.textSecondary,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete ${a.fullName}',
                    onPressed: () => _delete(a),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _statusText(AnalysisSummary a) {
    if (a.inProgress) return '${a.progress}%';
    if (a.stalled || a.status == AnalysisStatus.failed) return 'Failed';
    return 'Ready';
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return LizNotice(
      title: 'Needs the live backend',
      text:
          'Analysing a repository reads it from GitHub and keeps its report, which this demo copy of Liz cannot do. '
          'Sign in on the live site to use it.',
      color: p.caution,
      icon: Icons.cloud_off_outlined,
    );
  }
}
