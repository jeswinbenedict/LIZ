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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final interactive = widget.onTap != null;
    final lifted = interactive && _hovered;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final duration = reduce ? Duration.zero : LizMotion.quick;

    Widget card = AnimatedContainer(
      duration: duration,
      curve: LizMotion.ease,
      transform: Matrix4.translationValues(0, lifted && !reduce ? -2 : 0, 0),
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          widget.radius,
          // Under the pointer a card is lit: a red edge and a faint glow.
          side: BorderSide(
            color: lifted ? p.accent.withValues(alpha: 0.65) : p.hairline,
          ),
        ),
        shadows: lifted ? LizShadows.glow(p, strength: 0.4) : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: LizRadius.shape(widget.radius),
          onTap: widget.onTap,
          onHover: interactive ? (v) => setState(() => _hovered = v) : null,
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
