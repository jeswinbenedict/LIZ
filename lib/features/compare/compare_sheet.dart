import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_logo.dart';

/// Close alternatives to a tool, for the compare picker and the alternatives
/// page.
final alternativesProvider = FutureProvider.autoDispose
    .family<List<Tool>, String>(
      (ref, toolId) =>
          ref.watch(contentRepositoryProvider).alternativeTools(toolId),
    );

/// "Compare with…" from a tool's own page.
///
/// Comparing used to start only from Saved, in selection mode, so you had to
/// save tools you were only weighing up. This offers the tool's closest
/// alternatives right where the question comes up; pick one or two and the
/// comparison opens, at an address that can be shared.
Future<void> showCompareSheet(BuildContext context, Tool tool) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
      ),
      child: _CompareSheet(tool: tool),
    ),
  );
}

class _CompareSheet extends ConsumerStatefulWidget {
  const _CompareSheet({required this.tool});
  final Tool tool;

  @override
  ConsumerState<_CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends ConsumerState<_CompareSheet> {
  /// The tool itself takes one of the three columns a comparison fits.
  static const _maxOthers = 2;
  final _picked = <String>{};

  void _toggle(String id) {
    setState(() {
      if (!_picked.remove(id) && _picked.length < _maxOthers) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final alts = ref.watch(alternativesProvider(widget.tool.id));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            'Compare ${widget.tool.name} with…',
            style: LizText.title3.copyWith(color: p.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Pick one or two of its closest alternatives.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
        ),
        Flexible(
          child: alts.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => ErrorView(
              onRetry: () =>
                  ref.invalidate(alternativesProvider(widget.tool.id)),
            ),
            data: (tools) => tools.isEmpty
                ? const EmptyView(
                    icon: Icons.compare_arrows,
                    title: 'Nothing close enough to compare',
                    message:
                        'No tool in the catalog is similar enough to this one. '
                        'You can still compare from your Saved list.',
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final t in tools)
                        CheckboxListTile(
                          value: _picked.contains(t.id),
                          onChanged:
                              _picked.contains(t.id) ||
                                  _picked.length < _maxOthers
                              ? (_) => _toggle(t.id)
                              : null,
                          secondary: ToolLogo(tool: t, size: 36),
                          title: Text(t.name),
                          subtitle: Text(
                            t.tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                    ],
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton(
            style: LizButtons.capsule,
            onPressed: _picked.isEmpty
                ? null
                : () {
                    final ids = [widget.tool.id, ..._picked].join(',');
                    Navigator.of(context).pop();
                    context.push('/compare?ids=$ids');
                  },
            child: Text(
              _picked.isEmpty
                  ? 'Choose a tool to compare'
                  : 'Compare ${_picked.length + 1} tools',
            ),
          ),
        ),
      ],
    );
  }
}
