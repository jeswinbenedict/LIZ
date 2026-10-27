import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/liz_sheet.dart';
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
  return showLizSheet<void>(
    context,
    builder: (ctx) => _CompareSheet(tool: tool),
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
    return LizSheet(
      title: 'Compare ${widget.tool.name} with…',
      subtitle: 'Pick one or two of its closest alternatives.',
      actions: [
        FilledButton(
          style: LizSheetButtons.filled,
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
      ],
      child: alts.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => ErrorView(
          onRetry: () => ref.invalidate(alternativesProvider(widget.tool.id)),
        ),
        data: (tools) => tools.isEmpty
            ? Text(
                'No tool in the catalog is similar enough to this one. You '
                'can still compare from your Saved list.',
                style: LizText.callout.copyWith(color: p.textSecondary),
              )
            : DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.surface,
                  shape: LizRadius.shape(
                    LizRadius.md,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(LizRadius.md),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (var i = 0; i < tools.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: p.hairline),
                          CheckboxListTile(
                            value: _picked.contains(tools[i].id),
                            onChanged:
                                _picked.contains(tools[i].id) ||
                                    _picked.length < _maxOthers
                                ? (_) => _toggle(tools[i].id)
                                : null,
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              4,
                              12,
                              4,
                            ),
                            secondary: ToolLogo(tool: tools[i], size: 36),
                            title: Text(
                              tools[i].name,
                              style: LizText.headline.copyWith(
                                color: p.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              tools[i].tagline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LizText.footnote.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
