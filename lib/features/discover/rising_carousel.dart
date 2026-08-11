import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/repository/repositories.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/tool_logo.dart';
import 'discover_controller.dart';

/// Horizontal "Rising Early" strip — the product's core differentiator:
/// tools growing fast but not yet mainstream.
class RisingCarousel extends ConsumerWidget {
  const RisingCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const key = FeedKey(sort: ToolSort.rising);
    final state = ref.watch(toolFeedProvider(key));
    if (state.loading || state.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final items = state.items.take(10).toList();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: LizColors.rising, size: 20),
              const SizedBox(width: 6),
              Text('Rising Early',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('growing fast, still under the radar',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12.5)),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RisingCard(tool: items[i]),
          ),
        ),
      ],
    );
  }
}

class _RisingCard extends StatelessWidget {
  const _RisingCard({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/tool/${tool.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ToolLogo(tool: tool, size: 40),
                    const Spacer(),
                    TrendBadge(tool.trendScore),
                  ],
                ),
                const SizedBox(height: 10),
                Text(tool.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    tool.tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.2),
                  ),
                ),
                PricingBadge(tool.pricingType),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
