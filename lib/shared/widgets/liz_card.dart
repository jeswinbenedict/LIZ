import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A card in the `base` material that becomes `raised` under the pointer
/// (docs/DESIGN.md §5–6): the border strengthens, a soft shadow appears and it
/// lifts 2px; pressing scales it to 98%. With reduced motion the colours still
/// change but nothing moves.
class LizCard extends StatefulWidget {
  const LizCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = LizRadius.md,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// When set, the card reads as one control with this label, rather than as
  /// every piece of text inside it.
  final String? semanticLabel;

  @override
  State<LizCard> createState() => _LizCardState();
}

class _LizCardState extends State<LizCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final interactive = widget.onTap != null;
    // Lit under the pointer, and when the keyboard brings focus here — the
    // only sign a keyboard user has of where they are.
    final keyboardFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final lifted = interactive && (_hovered || keyboardFocus);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final duration = reduce ? Duration.zero : LizMotion.quick;

    Widget card = AnimatedContainer(
      duration: duration,
      curve: LizMotion.ease,
      transform: Matrix4.translationValues(0, lifted && !reduce ? -2 : 0, 0),
      decoration: ShapeDecoration(
        shape: LizRadius.shape(
          widget.radius,
          // Under the pointer a card lifts, and its edge takes some of the
          // red light behind the page (ambient.dart) — never solid red,
          // which means an action.
          side: BorderSide(
            color: lifted
                ? Color.lerp(p.hairlineStrong, p.accent, 0.4)!
                : p.hairline,
          ),
        ),
        // Glass: the ambient light shows faintly through, brighter along the
        // top edge as if lit from above.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (lifted ? p.surfaceHover : p.surfaceMuted).withValues(alpha: 0.86),
            (lifted ? p.surfaceMuted : p.surface).withValues(alpha: 0.8),
          ],
        ),
        shadows: [
          // Depth under every card; a red glow under a lifted one.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          if (lifted)
            BoxShadow(
              color: p.accent.withValues(alpha: 0.16),
              blurRadius: 30,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: LizRadius.shape(widget.radius),
          onTap: widget.onTap,
          onHover: interactive ? (v) => setState(() => _hovered = v) : null,
          onFocusChange: interactive
              ? (v) => setState(() => _focused = v)
              : null,
          onHighlightChanged: interactive
              ? (v) => setState(() => _pressed = v)
              : null,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    card = AnimatedScale(
      scale: _pressed && !reduce ? 0.98 : 1,
      duration: duration,
      curve: LizMotion.ease,
      child: card,
    );

    if (widget.semanticLabel != null) {
      card = Semantics(
        button: interactive,
        label: widget.semanticLabel,
        child: card,
      );
    }
    return card;
  }
}
