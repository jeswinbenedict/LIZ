import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/page_title.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';
import '../../shared/widgets/tool_link.dart';
import '../community/community_controller.dart';
import '../compare/compare_sheet.dart';
import '../../shared/widgets/top_bar.dart';

/// "Alternatives to X": the tools closest to one, by meaning.
///
/// The question people bring to a directory most often, and one of the most
/// searched. Its static twin is written by liz_scraper.prerender at the same
/// address, so search engines find the page and the app takes over on load.
class AlternativesScreen extends ConsumerWidget {
  const AlternativesScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolAsync = ref.watch(toolBySlugProvider(slug));
    return Scaffold(
      appBar: LizTopBar(
        section: ('Discover', '/'),
        title: 'Alternatives',
        titleIsHeading: false,
        fallback: '/tools/$slug',
      ),
      body: toolAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) =>
            ErrorView(onRetry: () => ref.invalidate(toolBySlugProvider(slug))),
        data: (tool) => tool == null
            ? const EmptyView(
                icon: Icons.help_outline,
                title: 'Tool not found',
                message: 'It may have been removed.',
              )
            : PageTitle(
                title: PageTitle.forAlternatives(tool.name),
                child: _Alternatives(tool: tool),
              ),
      ),
    );
  }
}

class _Alternatives extends ConsumerWidget {
  const _Alternatives({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final alts = ref.watch(alternativesProvider(tool.id));
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: MaxWidth(
            child: PageHeader(
              title: 'Alternatives to ${tool.name}',
              subtitle: 'Tools that do the most similar job, closest first.',
              bottom: 8,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MaxWidth(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ToolLink(
                    tool: tool,
                    builder: (context, open) => OutlinedButton(
                      onPressed: open,
                      child: Text('About ${tool.name}'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showCompareSheet(context, tool),
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label: const Text('Compare'),
                  ),
                ],
              ),
            ),
          ),
        ),
        alts.when(
          loading: () => const SliverToBoxAdapter(child: LoadingView()),
          error: (_, _) => SliverToBoxAdapter(
            child: ErrorView(
              onRetry: () => ref.invalidate(alternativesProvider(tool.id)),
            ),
          ),
          data: (tools) => tools.isEmpty
              ? SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.search_off,
                    title: 'No close alternatives yet',
                    message:
                        'Nothing in the catalog does a similar enough job to '
                        '${tool.name}.',
                  ),
                )
              : MaxWidthSliver(
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 48),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumnsFor(width),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: toolCardExtent(context),
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ToolCard(tool: tools[i]),
                        childCount: tools.length,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
