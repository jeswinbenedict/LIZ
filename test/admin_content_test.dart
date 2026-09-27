import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/core/repository/repositories.dart';
import 'package:liz/features/admin/content_tab.dart';
import 'package:liz/shared/models/tool.dart';

/// The console exists to drain a review queue. The previous version listed the
/// newest 200 tools with no filter, no search and no bulk action, which is how
/// 423 pending tools accumulated outside a 200-row window without anyone being
/// able to work through them.

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LizTheme.light(),
        home: const Scaffold(body: ContentTab()),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

void main() {
  group('the queue', () {
    testWidgets('opens on pending, the queue that needs a person', (
      tester,
    ) async {
      final container = await _pump(tester);

      expect(container.read(adminQueryProvider).status, PublishStatus.pending);
      await _teardown(tester, container);
    });

    testWidgets('can be filtered to any status', (tester) async {
      final container = await _pump(tester);

      await tester.tap(find.text('Published'));
      await tester.pumpAndSettle();
      expect(
        container.read(adminQueryProvider).status,
        PublishStatus.published,
      );

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(container.read(adminQueryProvider).status, isNull);

      await _teardown(tester, container);
    });

    testWidgets('pages rather than stopping at a fixed window', (tester) async {
      final container = await _pump(tester);
      expect(container.read(adminQueryProvider).offset, 0);

      // The repository is asked for a window, so a catalog larger than one
      // page is reachable — the old flat query could not see past 200 rows.
      container
          .read(adminQueryProvider.notifier)
          .update((q) => q.copyWith(offset: 50));
      await tester.pumpAndSettle();

      expect(container.read(adminQueryProvider).offset, 50);
      await _teardown(tester, container);
    });
  });

  group('bulk actions', () {
    testWidgets('the bar appears only once something is selected', (
      tester,
    ) async {
      final container = await _pump(tester);
      expect(find.textContaining('selected'), findsNothing);

      container.read(adminSelectionProvider.notifier).set({'t-1', 't-2'});
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);

      await _teardown(tester, container);
    });

    testWidgets('publishing a selection moves every row at once', (
      tester,
    ) async {
      final container = await _pump(tester);
      final repo = container.read(adminRepositoryProvider);

      final pending = await repo.adminTools(
        const AdminToolQuery(status: PublishStatus.pending, limit: 100),
      );
      final ids = pending.items.map((t) => t.id).toList();
      expect(ids, isNotEmpty, reason: 'mock data needs a pending tool');

      await repo.setToolStatuses(ids, PublishStatus.published);

      final stillPending = await repo.adminTools(
        const AdminToolQuery(status: PublishStatus.pending, limit: 100),
      );
      expect(stillPending.items, isEmpty);

      await _teardown(tester, container);
    });
  });

  group('the query object', () {
    test('clearing the status is distinct from leaving it alone', () {
      const q = AdminToolQuery(status: PublishStatus.pending);
      // copyWith(status: null) has to mean "unchanged", or "All" could never
      // be expressed — hence the explicit flag.
      expect(q.copyWith().status, PublishStatus.pending);
      expect(q.copyWith(clearStatus: true).status, isNull);
    });

    test(
      'a changed filter is a different query, so results are not reused',
      () {
        const pending = AdminToolQuery(status: PublishStatus.pending);
        const published = AdminToolQuery(status: PublishStatus.published);
        expect(pending == published, isFalse);
        expect(pending.hashCode == published.hashCode, isFalse);
        expect(
          pending == const AdminToolQuery(status: PublishStatus.pending),
          isTrue,
        );
      },
    );

    test('paging changes the query too', () {
      const first = AdminToolQuery();
      expect(first == first.copyWith(offset: 50), isFalse);
    });
  });
}
