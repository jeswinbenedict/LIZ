import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:liz/app/theme.dart';
import 'package:liz/features/discover/discover_screen.dart';

void main() {
  testWidgets('Discover screen renders the rising chart on mock data',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.light(),
          home: const DiscoverScreen(),
        ),
      ),
    );

    // Initial frame shows loading; let the mock repositories resolve.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Rising this week'), findsOneWidget);
  });
}
