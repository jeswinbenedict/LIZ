import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/tool_logo.dart';

/// Tools close to this one by meaning.
///
/// Matched in Postgres against the embeddings already stored for Ask Liz, so
/// this costs one index lookup and no model call. Fresh on each visit.
final similarToolsProvider = FutureProvider.autoDispose
    .family<List<Tool>, String>((ref, toolId) async {
      return ref.watch(contentRepositoryProvider).similarTools(toolId);
    });

/// A strip of related tools under a tool's page.
///
/// Renders nothing at all when there is no genuinely close match, and nothing
/// while it loads. The page is complete without this section, so a spinner or
/// an apology in its place would be worse than its absence.
class SimilarToolsSection extends ConsumerWidget {
  const SimilarToolsSection({super.key, required this.toolId});
  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarToolsProvider(toolId));
    final tools = similar.valueOrNull ?? const <Tool>[];
    if (tools.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Similar tools',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.auto_awesome,
              size: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tools.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _SimilarCard(tool: tools[i]),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 196,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(LizRadius.lg),
          // Replace rather than push: hopping between related tools should not
          // build a back stack ten deep to escape from.
          onTap: () => context.replace('/tool/${tool.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ToolLogo(tool: tool, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Text(
                          tool.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      PricingBadge(tool.pricingType),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
