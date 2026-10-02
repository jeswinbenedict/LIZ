import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Keyboard reach for a control Liz draws itself (a filter pill, a segment):
/// Tab focuses it, Enter or Space presses it, and [builder] is told when to
/// draw the focus ring.
///
/// A bare GestureDetector could only be clicked — the keyboard skipped it, and
/// with the accessibility tree on, the browser's focus landed on it with
/// nothing drawn to show where it was.
///
/// Put any `Semantics(excludeSemantics: true)` *inside* [builder], not around
/// this widget: excluding it drops the focus action a screen reader and the
/// browser's Tab use to move Flutter's focus here.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    // One node for the control: the focus action from Focus and the label
    // and flags the builder sets merge into it, instead of into whatever row
    // the control sits in.
    return Semantics(
      container: true,
      child: FocusableActionDetector(
        enabled: onTap != null,
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: widget.builder(context, _focused && onTap != null),
        ),
      ),
    );
  }
}

/// The ring a keyboard-focused control wears: a white line just outside its
/// edge, distinct from the red that marks a selected one.
List<BoxShadow> focusRing(LizPalette p) => [
  BoxShadow(color: p.textPrimary, spreadRadius: 2),
];

/// A white outline over a row or card while the keyboard has focus on it,
/// for surfaces whose own fill would hide an InkWell's focus tint (the lit
/// leader of the movers table). Hand [builder]'s callback to the InkWell's
/// `onFocusChange`.
class FocusOutline extends StatefulWidget {
  const FocusOutline({super.key, required this.builder, this.radius = 0});

  final Widget Function(BuildContext context, ValueChanged<bool> onFocusChange)
  builder;
  final double radius;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final show =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // Always the same widget, with or without the outline: a Container that
    // adds its decoration only when focused changes the tree under it, which
    // rebuilds the InkWell, disposes its focus node and sends focus back to
    // whatever had it before.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: show
            ? Border.all(color: context.liz.textPrimary, width: 2)
            : null,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.builder(context, (v) {
        if (v != _focused) setState(() => _focused = v);
      }),
    );
  }
}
