import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/tool_card.dart';
import 'discover_controller.dart';

/// Tools Liz first saw in the last seven days, newest first — the plainest
/// form of "before everyone else". A shelf that scrolls sideways, so it
/// previews the week without pushing the full catalog off the screen.
class NewThisWeek extends ConsumerWidget {
  const NewThisWeek({super.key, this.onSeeAll});

  /// Shows every new tool in the grid below.
  final VoidCallback? onSeeAll;

  static const days = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = FeedKey(
      sort: ToolSort.newest,
      pricing: ref.watch(discoverPricingProvider),
      newWithinDays: days,
    );
    final state = ref.watch(toolFeedProvider(key));
    if (state.loading || state.items.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final cardWidth = context.isPhone ? width * 0.78 : 320.0;
    final items = state.items.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'New this week',
          subtitle: 'First seen by Liz in the last seven days.',
          action: onSeeAll == null
              ? null
              : TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ),
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
