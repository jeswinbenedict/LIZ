import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/responsive/breakpoints.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/skeletons.dart';

/// The placeholders stand in for content that has not arrived. They have to
/// hold the layout, say "loading" once to a screen reader, and stop moving when
/// the platform asks for reduced motion.

Future<void> _pump(
  WidgetTester tester,
  Widget sliver, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: LizTheme.light(),
        home: Scaffold(body: CustomScrollView(slivers: [sliver])),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the tool grid shows a placeholder per card', (tester) async {
    await _pump(tester, const ToolGridSkeletonSliver(count: 6));

    expect(find.byType(ToolCardSkeleton), findsNWidgets(6));
    // Each card is built from several blocks, so the shapes are really there.
    expect(find.byType(SkeletonBox), findsAtLeast(6));
  });

  testWidgets('the news list shows article-shaped placeholders', (
    tester,
  ) async {
    await _pump(tester, const NewsListSkeletonSliver(count: 3));

    expect(find.byType(SkeletonBox), findsAtLeast(3));
  });

  testWidgets('a screen reader hears one loading message, not the shapes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ToolGridSkeletonSliver(count: 6));

    expect(find.bySemanticsLabel('Loading tools'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the shimmer stops when the platform asks for reduced motion', (
    tester,
  ) async {
    await _pump(
      tester,
      const ToolGridSkeletonSliver(),
      disableAnimations: true,
    );

    // With no repeating animation there is no endlessly pending frame, so the
    // tester can settle. Under the shimmer this call would time out.
    await tester.pumpAndSettle();
    expect(find.byType(ToolCardSkeleton), findsWidgets);
  });

  testWidgets('the placeholders occupy the space the cards will fill', (
    tester,
  ) async {
    await _pump(tester, const ToolGridSkeletonSliver(count: 4));

    // The placeholder must be exactly as tall as the real card, or the page
    // jumps when the tools arrive. Measured against the grid's own extent, so
    // resizing the card cannot leave the skeleton behind (it did: 222 → 138).
    final skeleton = find.byType(ToolCardSkeleton).first;
    final card = tester.getSize(skeleton);
    expect(card.height, toolCardExtent(tester.element(skeleton)));
  });
}
