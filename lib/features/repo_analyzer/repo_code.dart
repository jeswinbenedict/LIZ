import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/widgets/top_bar.dart';
import 'repo_models.dart';
import 'repo_service.dart';

/// "lib/main.dart:12" → ("lib/main.dart", 12); a bare path is line 1.
(String, int) splitRef(String ref) {
  final m = RegExp(r'^(.*):(\d+)$').firstMatch(ref);
  return m == null ? (ref, 1) : (m.group(1)!, int.parse(m.group(2)!));
}

/// A citation of the repository: the path and line, mono, opening the file
/// there when tapped.
class RefChip extends StatelessWidget {
  const RefChip({super.key, required this.analysisId, required this.reference});
  final String analysisId;
  final String reference;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final (path, line) = splitRef(reference);
    final short = path.split('/').length > 3
        ? '…/${path.split('/').sublist(path.split('/').length - 2).join('/')}'
        : path;
    return Tooltip(
      message: reference,
      child: Semantics(
        button: true,
        label: 'Open $path at line $line',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => openFile(context, analysisId, path, line: line),
          borderRadius: BorderRadius.circular(LizRadius.xs),
          child: Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                Icon(
                  Icons.description_outlined,
                  size: 13,
                  color: p.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    reference.contains(':') && line > 1
                        ? '$short:$line'
                        : short,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.mono.copyWith(
                      fontSize: 11.5,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RefChips extends StatelessWidget {
  const RefChips({
    super.key,
    required this.analysisId,
    required this.refs,
    this.max = 6,
  });
  final String analysisId;
  final List<String> refs;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in refs.take(max))
          RefChip(analysisId: analysisId, reference: r),
      ],
    );
  }
}

void openFile(
  BuildContext context,
  String analysisId,
  String path, {
  int line = 1,
}) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          FileViewerScreen(analysisId: analysisId, path: path, line: line),
    ),
  );
}

/// One file the analysis read, with line numbers, scrolled to [line].
class FileViewerScreen extends ConsumerStatefulWidget {
  const FileViewerScreen({
    super.key,
    required this.analysisId,
    required this.path,
    this.line = 1,
  });
  final String analysisId;
  final String path;
  final int line;

  @override
  ConsumerState<FileViewerScreen> createState() => _FileViewerScreenState();
}

const _lineHeight = 20.0;

class _FileViewerScreenState extends ConsumerState<FileViewerScreen> {
  late final Future<String?> _content = ref
      .read(repoAnalyzerServiceProvider)!
      .fileContent(widget.analysisId, widget.path);
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Scaffold(
      appBar: LizTopBar(
        title: widget.path.split('/').last,
        section: const ('Repositories', '/repos'),
        fallback: '/repos',
      ),
      body: FutureBuilder<String?>(
        future: _content,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final text = snap.data;
          if (snap.hasError || text == null) {
            return _Unread(path: widget.path);
          }
          final lines = text.split('\n');
          final target = widget.line.clamp(1, lines.length);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients && _scroll.offset == 0 && target > 4) {
              _scroll.jumpTo(
                ((target - 5) * _lineHeight).clamp(
                  0,
                  _scroll.position.maxScrollExtent,
                ),
              );
            }
          });
          final gutter = '${lines.length}'.length * 8.0 + 20;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.path,
                        style: LizText.mono.copyWith(
                          fontSize: 12.5,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${lines.length} lines',
                      style: LizText.label.copyWith(color: p.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'Copy file',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: text)),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.hairline),
              Expanded(
                child: SelectionArea(
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: _width(lines, gutter),
                        child: ListView.builder(
                          controller: _scroll,
                          itemExtent: _lineHeight,
                          itemCount: lines.length,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (context, i) {
                            final hot = i + 1 == target && widget.line > 1;
                            return Container(
                              color: hot
                                  ? p.accent.withValues(alpha: 0.14)
                                  : null,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: gutter,
                                    child: Text(
                                      '${i + 1}',
                                      textAlign: TextAlign.right,
                                      style: LizText.mono.copyWith(
                                        fontSize: 12,
                                        color: hot ? p.accent : p.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Clipped at the width measured below: a
                                  // minified line of thousands of characters
                                  // must not widen the page without end.
                                  Expanded(
                                    child: Text(
                                      lines[i].replaceAll('\t', '    '),
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: LizText.mono.copyWith(
                                        fontSize: 12.5,
                                        color: p.textPrimary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _width(List<String> lines, double gutter) {
    final longest = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final w = gutter + 30 + longest.clamp(40, 1200) * 7.8;
    final screen = MediaQuery.sizeOf(context).width;
    return w < screen ? screen : w;
  }
}

class _Unread extends StatelessWidget {
  const _Unread({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_off_outlined,
                color: p.textSecondary,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Not read by the analysis',
                style: LizText.title3.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '$path was not read: it is binary, generated, vendored, too large, '
                'a likely secret, or beyond the files an analysis reads.',
                textAlign: TextAlign.center,
                style: LizText.callout.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The repository's files as a tree. Files the analysis read open in the
/// viewer; the rest are listed, dimmed, so the structure is whole.
class CodeExplorer extends StatefulWidget {
  const CodeExplorer({super.key, required this.analysis});
  final RepoAnalysis analysis;

  @override
  State<CodeExplorer> createState() => _CodeExplorerState();
}

class _Dir {
  final dirs = <String, _Dir>{};
  final files = <TreeFile>[];
  int count = 0;
}

class _CodeExplorerState extends State<CodeExplorer> {
  late final _Dir _root = _build(widget.analysis.tree);
  final _open = <String>{''};
  String _query = '';

  _Dir _build(List<TreeFile> files) {
    final root = _Dir();
    for (final f in files) {
      var d = root..count += 1;
      final parts = f.path.split('/');
      for (final part in parts.sublist(0, parts.length - 1)) {
        d = d.dirs.putIfAbsent(part, _Dir.new)..count += 1;
      }
      d.files.add(f);
    }
    return root;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final a = widget.analysis;
    final read = a.tree.where((f) => f.read).length;
    final rows = <Widget>[];
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      for (final f
          in a.tree.where((f) => f.path.toLowerCase().contains(q)).take(300)) {
        rows.add(_fileRow(f, f.path, 0));
      }
    } else {
      _walk(_root, '', 0, rows);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${a.tree.length} files${a.treeTruncated ? ' (list truncated)' : ''}; $read read by the analysis and openable.',
          style: LizText.callout.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Find a file',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: p.surface,
            shape: LizRadius.shape(
              LizRadius.md,
              side: BorderSide(color: p.hairline),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows.isEmpty ? [_empty(p)] : rows,
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(LizPalette p) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      'No file matches.',
      style: LizText.callout.copyWith(color: p.textSecondary),
    ),
  );

  void _walk(_Dir d, String prefix, int depth, List<Widget> out) {
    final names = d.dirs.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      final path = prefix.isEmpty ? name : '$prefix/$name';
      final open = _open.contains(path);
      out.add(_dirRow(name, path, d.dirs[name]!.count, depth, open));
      if (open) _walk(d.dirs[name]!, path, depth + 1, out);
      if (out.length > 1500) return;
    }
    final files = [...d.files]
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final f in files) {
      out.add(_fileRow(f, f.path.split('/').last, depth));
    }
  }

  Widget _dirRow(String name, String path, int count, int depth, bool open) {
    final p = context.liz;
    return InkWell(
      onTap: () => setState(() => open ? _open.remove(path) : _open.add(path)),
      child: Semantics(
        button: true,
        expanded: open,
        label: 'Folder $name, $count files',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: EdgeInsets.only(left: 12 + depth * 16.0, right: 12),
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: p.textSecondary,
              ),
              const SizedBox(width: 4),
              Icon(Icons.folder_outlined, size: 17, color: p.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: LizText.callout.copyWith(color: p.textPrimary),
                ),
              ),
              Text(
                '$count',
                style: LizText.label.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileRow(TreeFile f, String label, int depth) {
    final p = context.liz;
    return InkWell(
      onTap: () => openFile(context, widget.analysis.summary.id, f.path),
      child: Semantics(
        button: true,
        label: '${f.path}${f.read ? '' : ', not read'}',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.only(left: 34 + depth * 16.0, right: 12),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 16,
                color: f.read ? p.textSecondary : p.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.mono.copyWith(
                    fontSize: 12.5,
                    color: f.read ? p.textPrimary : p.textSecondary,
                  ),
                ),
              ),
              if (f.size > 0)
                Text(
                  _size(f.size),
                  style: LizText.label.copyWith(color: p.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _size(int b) => b < 1024
      ? '$b B'
      : b < 1048576
      ? '${(b / 1024).toStringAsFixed(1)} KB'
      : '${(b / 1048576).toStringAsFixed(1)} MB';
}
