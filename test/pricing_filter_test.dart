import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/discover/discover_controller.dart';
import 'package:liz/features/discover/discover_screen.dart';
import 'package:liz/features/discover/search_screen.dart';
import 'package:liz/features/track/saved_screen.dart';
import 'package:liz/features/track/track_controller.dart';
import 'package:liz/shared/models/tool.dart';

/// "Is it free?" is the first question most people bring to a tool directory,
/// and the catalog is split enough for the answer to matter — of 185 published
/// tools, 101 are free, 41 freemium and 20 paid.

void main() {
  test('the feed asks the repository for one price', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = container.read(contentRepositoryProvider);

    final free = await repo.tools(
      const ToolQuery(limit: 100, pricing: PricingType.free),
    );
    expect(free.items, isNotEmpty);
    expect(
      free.items.every((t) => t.pricingType == PricingType.free),
      isTrue,
      reason: 'a paid tool must not appear under a free filter',
    );

    final any = await repo.tools(const ToolQuery(limit: 100));
    expect(
      any.items.length,
      greaterThan(free.items.length),
      reason: 'the filter should actually narrow the feed',
    );
  });

  test('a feed key with a different price is a different feed', () {
    const anyPrice = FeedKey();
    const freeOnly = FeedKey(pricing: PricingType.free);

    // Riverpod caches feeds by key, so a key that ignored the filter would
    // serve the unfiltered list back under the filter.
    expect(anyPrice == freeOnly, isFalse);
    expect(anyPrice.hashCode == freeOnly.hashCode, isFalse);
    expect(const FeedKey(pricing: PricingType.free) == freeOnly, isTrue);
  });

  testWidgets('the chip says which filter is on', (tester) async {
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: LizTheme.light(),
          home: const DiscoverScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Off by default, and saying so — a filter silently on is a filter that
    // makes the catalog look empty for no visible reason.
    expect(find.text('Any price'), findsOneWidget);

    container.read(discoverPricingProvider.notifier).set(PricingType.free);
    await tester.pumpAndSettle();

    expect(find.text('Free'), findsWidgets);
    expect(find.text('Any price'), findsNothing);

    // Unmount before disposing: the feed holds a grace-period timer that the
    // container cancels on dispose, and the framework checks for stray timers
    // as soon as the tree comes down.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  test('search asks the repository for one price', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = container.read(contentRepositoryProvider);

    final any = await repo.searchTools('ai');
    final free = await repo.searchTools('ai', pricing: PricingType.free);
    expect(free, isNotEmpty);
    expect(free.every((t) => t.pricingType == PricingType.free), isTrue);
    expect(any.length, greaterThan(free.length));
  });

  test('a search key with a different price is a different search', () {
    // Same reason as the feed: results are cached per key.
    const SearchKey anyPrice = (query: 'ai', pricing: null);
    const SearchKey freeOnly = (query: 'ai', pricing: PricingType.free);
    expect(anyPrice == freeOnly, isFalse);
  });

  testWidgets('Saved narrows your own list by price', (tester) async {
    final all = await tester.runAsync(() async {
      final c = ProviderContainer();
      final page = await c
          .read(contentRepositoryProvider)
          .tools(const ToolQuery(limit: 100));
      c.dispose();
      return page.items;
    });
    final saved = [
      all!.firstWhere((t) => t.pricingType == PricingType.free),
      all.firstWhere((t) => t.pricingType == PricingType.paid),
    ];

    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWithValue(true),
        bookmarkedToolsProvider.overrideWith((ref) async => saved),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: LizTheme.light(), home: const SavedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Any price'), findsOneWidget);
    expect(find.text(saved[0].name), findsOneWidget);
    expect(find.text(saved[1].name), findsOneWidget);

    container.read(savedPricingProvider.notifier).set(PricingType.free);
    await tester.pumpAndSettle();
    expect(find.text(saved[0].name), findsOneWidget);
    expect(find.text(saved[1].name), findsNothing);

    // A filter that empties the list must say so and offer the way back,
    // not read as though nothing was ever saved.
    container.read(savedPricingProvider.notifier).set(PricingType.freemium);
    await tester.pumpAndSettle();
    expect(find.text('Nothing saved at this price'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsNothing);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text(saved[1].name), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('Search shows the price filter above results', (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: LizTheme.light(),
          home: const SearchScreen(initialQuery: 'ai'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Any price'), findsOneWidget);

    await tester.tap(find.text('Any price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Paid'), findsWidgets);
    expect(find.text('Any price'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
