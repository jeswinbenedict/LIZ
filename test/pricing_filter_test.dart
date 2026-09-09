import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/core/repository/repositories.dart';
import 'package:liz/features/discover/discover_controller.dart';
import 'package:liz/features/discover/discover_screen.dart';
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

    container.read(discoverPricingProvider.notifier).state = PricingType.free;
    await tester.pumpAndSettle();

    expect(find.text('Free'), findsWidgets);
    expect(find.text('Any price'), findsNothing);

    // Unmount before disposing: the feed holds a grace-period timer that the
    // container cancels on dispose, and the framework checks for stray timers
    // as soon as the tree comes down.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
