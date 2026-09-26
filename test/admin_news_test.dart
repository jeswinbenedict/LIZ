import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/core/repository/repositories.dart';
import 'package:liz/features/admin/news_tab.dart';
import 'package:liz/shared/models/tool.dart' show PublishStatus;

/// allNews() existed with nothing able to act on what it returned, so the
/// only way to take a bad article down was the database console.

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LizTheme.light(),
        home: const Scaffold(body: NewsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

void main() {
  testWidgets('lists articles with a way to hide each one', (tester) async {
    final container = await _pump(tester);
    expect(find.text('Hide'), findsWidgets);
    await _teardown(tester, container);
  });

  testWidgets('hiding an article takes it out of the reader feed', (
    tester,
  ) async {
    final container = await _pump(tester);
    final AdminRepository admin = container.read(adminRepositoryProvider);
    final before = await admin.allNews();
    final target = before.firstWhere(
      (n) => n.status == PublishStatus.published,
    );

    await tester.tap(find.text('Hide').first);
    await tester.pumpAndSettle();

    final after = await admin.allNews();
    final changed = after.firstWhere((n) => n.id == target.id);
    expect(changed.status, PublishStatus.hidden);

    // And the reader-facing feed no longer carries it.
    final feed = await container
        .read(contentRepositoryProvider)
        .news(limit: 200);
    expect(feed.items.any((n) => n.id == target.id), isFalse);

    // The row now offers the way back.
    expect(find.text('Restore'), findsOneWidget);
    await _teardown(tester, container);
  });

  testWidgets('a misfired hide can be undone from the snackbar', (
    tester,
  ) async {
    // A moderation click is easy to misfire on a long list.
    final container = await _pump(tester);
    final admin = container.read(adminRepositoryProvider);
    final target = (await admin.allNews()).firstWhere(
      (n) => n.status == PublishStatus.published,
    );

    await tester.tap(find.text('Hide').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = (await admin.allNews()).firstWhere(
      (n) => n.id == target.id,
    );
    expect(restored.status, PublishStatus.published);
    await _teardown(tester, container);
  });
}
