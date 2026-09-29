import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/liz_card.dart';
import '../../shared/widgets/tool_link.dart';
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
    final tools = similar.value ?? const <Tool>[];
    if (tools.isEmpty) return const SizedBox.shrink();

    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Similar tools',
              style: LizText.title2.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height:
                132 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: tools.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _SimilarCard(tool: tools[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      // Replace rather than push: hopping between related tools should not
      // build a back stack ten deep to escape from.
      child: ToolLink(
        tool: tool,
        replace: true,
        builder: (context, open) => _card(context, open),
      ),
    );
  }

  Widget _card(BuildContext context, VoidCallback open) {
    final p = context.liz;
    return LizCard(
      padding: const EdgeInsets.all(14),
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ToolLogo(tool: tool, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.headline.copyWith(color: p.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              tool.tagline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LizText.subhead.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          ToolMeta(tool, showCategory: false),
        ],
      ),
    );
  }
}
