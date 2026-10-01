import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/news_item.dart';
import '../../shared/widgets/news_card.dart';

/// Articles that name a tool in their headline, newest first.
final toolNewsProvider = FutureProvider.autoDispose
    .family<List<NewsItem>, String>((ref, toolId) async {
      return ref.watch(contentRepositoryProvider).newsForTool(toolId);
    });

/// "In the news" on a tool's page: the coverage Liz already collected for the
/// news feed, joined to the product it is about.
///
/// Like the similar-tools strip, it renders nothing while loading and nothing
/// when no article names the tool — most small launches never make the news,
/// and an empty heading would only say so.
class ToolNewsSection extends ConsumerWidget {
  const ToolNewsSection({super.key, required this.toolId, required this.name});
  final String toolId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(toolNewsProvider(toolId)).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();

    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'In the news',
              style: LizText.title2.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recent headlines that mention $name.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.hairline),
            NewsCard(item: items[i]),
          ],
        ],
      ),
    );
  }
}
