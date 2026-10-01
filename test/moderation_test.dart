import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/admin/moderation_tab.dart';

/// The moderation queue had three gaps that compounded. Hide only acted on
/// posts — on a reported review it quietly dismissed the report instead, so a
/// moderator could believe something was gone while it stayed live on a tool
/// page. It showed a UUID instead of what was reported. And nothing listed what
/// the report trigger had hidden on its own, so a wrong call was permanent.

// The mock repository sleeps before answering, and under the test clock only
// a pump advances time, so repository calls run under tester.runAsync.

Future<ProviderContainer> _signedIn(WidgetTester tester) async {
  final container = ProviderContainer();
  unawaited(
    container
        .read(authRepositoryProvider)
        .signInWithEmail('moderator@example.com', 'whatever'),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LizTheme.app(),
        home: const Scaffold(body: ModerationTab()),
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
  testWidgets('shows what was reported, not an id', (tester) async {
    final container = await _signedIn(tester);
    // The seeded report is against a post whose text the moderator should see.
    expect(find.textContaining('messy CSVs'), findsOneWidget);
    await _teardown(tester, container);
  });

  testWidgets('hiding a reported review actually hides the review', (
    tester,
  ) async {
    final container = await _signedIn(tester);
    await tester.runAsync(
      () => container
          .read(communityRepositoryProvider)
          .report(targetType: 'review', targetId: 'r-1', reason: 'Spam'),
    );
    container.invalidate(moderationReportsProvider);
    await tester.pumpAndSettle();

    expect(find.text('Hide review'), findsOneWidget);
    await tester.tap(find.text('Hide review'));
    await tester.pumpAndSettle();

    final reviews = await container
        .read(communityRepositoryProvider)
        .reviewsForTool('t-6');
    final r1 = reviews.where((r) => r.id == 'r-1');
    // Either filtered out of the reader view or marked hidden — never live.
    expect(r1.every((r) => r.status == 'hidden'), isTrue);

    // And it is now listed under Hidden, restorable.
    final hidden = await container
        .read(adminRepositoryProvider)
        .hiddenContent();
    expect(hidden.any((h) => h.targetId == 'r-1'), isTrue);
    await _teardown(tester, container);
  });

  testWidgets('dismissing leaves the content up', (tester) async {
    final container = await _signedIn(tester);
    await tester.runAsync(
      () => container
          .read(communityRepositoryProvider)
          .report(targetType: 'review', targetId: 'r-2', reason: 'Meh'),
    );
    container.invalidate(moderationReportsProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dismiss').last);
    await tester.pumpAndSettle();

    final hidden = await container
        .read(adminRepositoryProvider)
        .hiddenContent();
    expect(hidden.any((h) => h.targetId == 'r-2'), isFalse);
    await _teardown(tester, container);
  });

  testWidgets('something hidden by mistake can be restored', (tester) async {
    final container = await _signedIn(tester);
    final admin = container.read(adminRepositoryProvider);
    await admin.setContentHidden('review', 'r-1', hidden: true);
    container.invalidate(hiddenContentProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore').first);
    await tester.pumpAndSettle();

    final hidden = await admin.hiddenContent();
    expect(hidden.any((h) => h.targetId == 'r-1'), isFalse);
    await _teardown(tester, container);
  });

  testWidgets('one person reporting twice files one report', (tester) async {
    // Mirrors the constraint in migration 0034: the second report is a no-op,
    // not a second vote.
    final container = await _signedIn(tester);
    final community = container.read(communityRepositoryProvider);
    final admin = container.read(adminRepositoryProvider);
    final before = (await admin.openReports()).length;

    await tester.runAsync(
      () => community.report(targetType: 'tool', targetId: 't-1', reason: 'x'),
    );
    await tester.runAsync(
      () => community.report(targetType: 'tool', targetId: 't-1', reason: 'x'),
    );

    expect((await admin.openReports()).length, before + 1);
    await _teardown(tester, container);
  });
}
