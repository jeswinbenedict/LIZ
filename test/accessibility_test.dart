import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/ask_liz/ask_liz_screen.dart';
import 'package:liz/shared/models/tool.dart';
import 'package:liz/shared/widgets/badges.dart';

/// Accessibility checks the per-screen sweep (screen_sweep_test.dart) cannot
/// make on its own.
///
/// The sweep runs Flutter's contrast guideline over whatever is on screen, but
/// a tool card merges its text into one label for the card, so the guideline
/// never measures a badge inside one. The badges are where the brand accents
/// are used as text, and where contrast actually failed: orange on a pale
/// orange tint read at 2.2:1. They are checked directly here instead.

void main() {
  testWidgets('Ask Liz names its send button', (tester) async {
    // Its only control past the text field was an icon-only button, which a
    // screen reader announced as "button" — found by a sweep, fixed with a
    // label, and kept here so it cannot quietly go back.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: LizTheme.app(), home: const AskLizScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.bySemanticsLabel('Ask Liz'), findsWidgets);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('legibleOn', () {
    test('reaches the minimum against light and dark backgrounds', () {
      for (final accent in [
        LizColors.brand,
        LizColors.rising,
        LizColors.positive,
        LizColors.warn,
        Colors.grey,
      ]) {
        for (final background in [Colors.white, const Color(0xFF121218)]) {
          final ink = LizColors.legibleOn(accent, background);
          expect(
            LizColors.contrast(ink, background),
            greaterThanOrEqualTo(4.5),
            reason: '$accent on $background',
          );
        }
      }
    });

    test('leaves a colour alone when it already reads', () {
      // Adjusting only what fails keeps the palette recognisable.
      expect(LizColors.legibleOn(Colors.black, Colors.white), Colors.black);
    });
  });

  {
    testWidgets('every badge colour reads on its own tint', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: LizTheme.app(),
          home: Scaffold(
            body: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pricing in PricingType.values) PricingBadge(pricing),
                const LizPill(label: '#12', color: LizColors.rising),
                const LizPill(label: 'agents'),
                const LizPill(
                  label: 'NEW',
                  color: LizColors.positive,
                  filled: true,
                ),
                const LizPill(
                  label: 'HOT',
                  color: LizColors.rising,
                  filled: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
