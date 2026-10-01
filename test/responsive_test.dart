import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/shared/widgets/states.dart';

/// Layout cases the per-screen sweep cannot reach. Every screen at 320px,
/// 1.5x text and tablet size is in screen_sweep_test.dart.

void main() {
  testWidgets('an empty state survives a box too short for it', (tester) async {
    // The admin console stacks filters above a filtered list, so an empty
    // result can be left with very little height. It used to paint an overflow
    // stripe over its own message.
    tester.view.physicalSize = const Size(400, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: LizTheme.app(),
        home: const Scaffold(
          body: Column(
            children: [
              SizedBox(height: 150),
              Expanded(
                child: EmptyView(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing here',
                  message: 'No tools match this filter.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
