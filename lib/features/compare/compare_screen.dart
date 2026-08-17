import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_logo.dart';

final _compareProvider =
    FutureProvider.family<List<Tool>, String>((ref, idsCsv) async {
  final ids = idsCsv.split(',').where((e) => e.isNotEmpty).toList();
  return ref.watch(contentRepositoryProvider).compareTools(ids);
});

class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key, required this.toolIds});
  final List<String> toolIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_compareProvider(toolIds.join(',')));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare'),
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/saved');
          }
        }),
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (_, __) => ErrorView(
            onRetry: () => ref.invalidate(_compareProvider(toolIds.join(',')))),
        data: (tools) => tools.length < 2
            ? const EmptyView(
                icon: Icons.compare_arrows,
                title: 'Pick 2–3 tools to compare',
                message: 'Select tools from your Saved list.',
              )
            : _CompareTable(tools: tools),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.tools});
  final List<Tool> tools;

  @override
  Widget build(BuildContext context) {
    const colWidth = 220.0;
    final rows = <(_String, Widget Function(Tool))>[
      (const _String('Pricing'), (t) => PricingBadge(t.pricingType)),
      (const _String('Price'), (t) => Text(t.priceNote ?? '—')),
      (
        const _String('Rating'),
        (t) => t.ratingCount == 0
            ? const Text('—')
            : Row(mainAxisSize: MainAxisSize.min, children: [
                RatingStars(t.avgRating, size: 14),
                const SizedBox(width: 4),
                Text(t.avgRating.toStringAsFixed(1)),
              ])
      ),
      (const _String('Category'), (t) => Text(t.category.replaceAll('ai-', ''))),
      (
        const _String('Platforms'),
        (t) => Text(t.platforms.isEmpty ? '—' : t.platforms.join(', '))
      ),
      (const _String('Rank'), (t) => TrendBadge(t)),
      (
        const _String('Key features'),
        (t) => Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final tag in t.tags.take(4)) LizPill(label: tag)],
            )
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: tool logos + names
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 120),
                for (final t in tools)
                  SizedBox(
                    width: colWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          ToolLogo(tool: t, size: 48),
                          const SizedBox(height: 8),
                          Text(t.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(t.tagline,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final row in rows) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(row.$1.value,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    for (final t in tools)
                      SizedBox(
                        width: colWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: row.$2(t)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tiny wrapper so the row tuple has a const-constructible label.
class _String {
  const _String(this.value);
  final String value;
}
