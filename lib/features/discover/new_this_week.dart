import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/tool_card.dart';
import '../profile/preferences.dart';
import 'discover_controller.dart';

/// A titled shelf of tool cards that scrolls sideways, so it previews a list
/// without pushing the full catalog off the screen. Renders nothing while
/// loading or when empty: the page is complete without it.
class ToolShelf extends ConsumerWidget {
  const ToolShelf({
    super.key,
    required this.title,
    required this.subtitle,
    required this.feedKey,
    this.action,
  });

  final String title;
  final String subtitle;
  final FeedKey feedKey;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(toolFeedProvider(feedKey));
    if (state.loading || state.items.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final cardWidth = context.isPhone ? width * 0.78 : 320.0;
    final items = state.items.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, subtitle: subtitle, action: action),
        SizedBox(
          height: toolCardExtent(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: ToolCard(tool: items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tools Liz first saw in the last seven days, newest first — the plainest
/// form of "before everyone else".
class NewThisWeek extends ConsumerWidget {
  const NewThisWeek({super.key, this.onSeeAll});

  /// Shows every new tool in the grid below.
  final VoidCallback? onSeeAll;

  static const days = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ToolShelf(
      title: 'New this week',
      subtitle: 'First seen by Liz in the last seven days.',
      feedKey: FeedKey(
        sort: ToolSort.newest,
        pricing: ref.watch(discoverPricingProvider),
        newWithinDays: days,
      ),
      action: onSeeAll == null
          ? null
          : TextButton(onPressed: onSeeAll, child: const Text('See all')),
    );
  }
}

/// What is rising in the categories someone said they care about (the
/// interest picker). Absent until they have picked some.
class ForYou extends ConsumerWidget {
  const ForYou({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(preferencesProvider).interests;
    if (interests.isEmpty) return const SizedBox.shrink();
    return ToolShelf(
      title: 'For you',
      subtitle: 'Rising in the kinds of tools you follow.',
      feedKey: FeedKey(
        sort: ToolSort.rising,
        pricing: ref.watch(discoverPricingProvider),
        categories: ([...interests]..sort()).join(','),
      ),
      action: TextButton(
        onPressed: () => showInterestPicker(context),
        child: const Text('Edit'),
      ),
    );
  }
}
