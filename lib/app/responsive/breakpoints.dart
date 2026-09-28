import 'package:flutter/widgets.dart';

/// Central responsive breakpoints. Layouts adapt from 320px phones to wide
/// desktop; navigation morphs bottom bar → rail → sidebar.
enum FormFactor { phone, tablet, desktop }

class Breakpoints {
  const Breakpoints._();
  static const double tablet = 600;
  static const double desktop = 1024;

  /// Max readable content width on large screens (centered).
  static const double contentMax = 1200;

  static FormFactor of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static FormFactor fromWidth(double width) {
    if (width >= desktop) return FormFactor.desktop;
    if (width >= tablet) return FormFactor.tablet;
    return FormFactor.phone;
  }
}

extension FormFactorX on BuildContext {
  FormFactor get formFactor => Breakpoints.of(this);
  bool get isPhone => formFactor == FormFactor.phone;
  bool get isTablet => formFactor == FormFactor.tablet;
  bool get isDesktop => formFactor == FormFactor.desktop;
  bool get isWide => formFactor != FormFactor.phone;
}

/// Number of grid columns for a card feed at the current width.
int gridColumnsFor(double width) {
  if (width >= 1500) return 4;
  if (width >= Breakpoints.desktop) return 3;
  if (width >= Breakpoints.tablet) return 2;
  return 1;
}

/// Height of one tool card in a feed grid.
///
/// The card holds a fixed amount of text, so when someone turns the system
/// font up the same content needs more room; a constant height would clip the
/// bottom row instead. Growth is capped because the tallest accessibility
/// settings would otherwise leave a single card filling the screen.
double toolCardExtent(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  // Sized to the card's content: logo row, two-line tagline, one metadata
  // line. The old 222 left a band of empty card under every tool.
  return 138 * scale.clamp(1.0, 1.6);
}

/// Height of the "Rising Early" carousel strip, which grows the same way.
double risingCardExtent(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return 150 * scale.clamp(1.0, 1.6);
}

/// Centers and width-caps content on large screens so text stays readable.
class MaxWidth extends StatelessWidget {
  const MaxWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMax,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// [MaxWidth] for slivers: centres [sliver] and caps it at [maxWidth], so a
/// grid lines up with the capped content above it on wide screens.
class MaxWidthSliver extends StatelessWidget {
  const MaxWidthSliver({
    super.key,
    required this.sliver,
    this.maxWidth = Breakpoints.contentMax,
  });

  final Widget sliver;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.crossAxisExtent - maxWidth;
        final side = extra > 0 ? extra / 2 : 0.0;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: sliver,
        );
      },
    );
  }
}
