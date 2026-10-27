import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Opens [builder] as a bottom sheet the way every sheet in Liz opens: a drag
/// handle, at most 560 wide and 90% of the height, lifted above the keyboard.
Future<T?> showLizSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
        ),
        child: builder(ctx),
      ),
    ),
  );
}

/// The inside of a sheet (docs/DESIGN.md §7, Sheets): its title as a heading,
/// one line under it, the body — which scrolls when it has to — and the
/// actions in a row along the foot, sharing the width.
class LizSheet extends StatelessWidget {
  const LizSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Usually an outlined way out and the filled action, in that order.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                style: LizText.title2.copyWith(color: p.textPrimary),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: LizText.callout.copyWith(color: p.textSecondary),
              ),
            ],
            const SizedBox(height: 20),
            Flexible(child: SingleChildScrollView(child: child)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A sheet's or dialog's buttons at one height.
abstract final class LizSheetButtons {
  static final outlined = OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  );
  static final filled = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  );
}

/// Asks before something that cannot be undone, or should not happen by
/// accident. [destructive] makes the confirming button red. True on confirm.
Future<bool> showLizConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final p = context.liz;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          message,
          style: LizText.body.copyWith(color: p.textSecondary),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: LizSheetButtons.outlined,
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: destructive
                    ? LizSheetButtons.filled.copyWith(
                        backgroundColor: WidgetStatePropertyAll(p.danger),
                        foregroundColor: const WidgetStatePropertyAll(
                          Colors.white,
                        ),
                      )
                    : LizSheetButtons.filled,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result == true;
}
