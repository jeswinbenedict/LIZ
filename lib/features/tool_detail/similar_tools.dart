import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/tool_card.dart';

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
  const SimilarToolsSection({super.key, required this.toolId, this.slug});
  final String toolId;

  /// For "See all", which opens the alternatives page.
  final String? slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarToolsProvider(toolId));
    final tools = similar.value ?? const <Tool>[];
    if (tools.isEmpty) return const SizedBox.shrink();

    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    'Similar tools',
                    style: LizText.title2.copyWith(color: p.textPrimary),
                  ),
                ),
              ),
              if (slug != null)
                SectionAction(
                  label: 'See all',
                  onPressed: () => context.push('/alternatives/$slug'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // The same card as Discover's grid, at the width it is drawn for:
          // two across in a reading column, up to two rows (the rest are a
          // "See all" away). On a phone, a strip to swipe.
          LayoutBuilder(
            builder: (context, box) {
              final height = toolCardExtent(context);
              if (box.maxWidth >= 640) {
                final shown = tools.take(4).toList();
                return Column(
                  children: [
                    for (var r = 0; r < shown.length; r += 2) ...[
                      if (r > 0) const SizedBox(height: 16),
                      SizedBox(
                        height: height,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: ToolCard(tool: shown[r])),
                            const SizedBox(width: 16),
                            Expanded(
                              child: r + 1 < shown.length
                                  ? ToolCard(tool: shown[r + 1])
                                  : const SizedBox(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              }
              return SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: tools.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) =>
                      SizedBox(width: 280, child: ToolCard(tool: tools[i])),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
