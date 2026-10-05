import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/auth_gate.dart';
import 'package:liz/app/router.dart';
import 'package:liz/app/settings_controller.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop sidebar was missing from the accessibility tree: the page
/// route's BlockSemantics barrier dropped everything painted before it, which
/// was the whole sidebar. A screen reader saw the page and no way to the rest
/// of Liz.
void main() {
  testWidgets('the sidebar is in the accessibility tree beside a page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((_) => prefs)],
    );
    addTearDown(container.dispose);
    final auth = container.read(authRepositoryProvider);
    await tester.runAsync(() async {
      await auth.restored;
      await auth.signInAsDemo();
    });
    final gate = AuthGate(auth);
    addTearDown(gate.dispose);
    final router = buildRouter(gate);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: LizTheme.app(), routerConfig: router),
      ),
    );
    router.go('/news');
    await tester.pumpAndSettle();

    for (final label in ['Discover', 'Ask Liz', 'Saved', 'Search tools']) {
      expect(
        find.semantics.byLabel(label),
        findsWidgets,
        reason: '"$label" in the sidebar',
      );
    }
    // The news page polls; let its timers go with the tree.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    handle.dispose();
  });
}
