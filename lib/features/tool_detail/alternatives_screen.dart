import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/page_title.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import '../profile/profile_parts.dart';
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

/// The page: its title with how many were found and *Compare* beside it, the
/// tool it started from as a framed row that leads back to it, then the
/// alternatives as Discover's cards, closest first.
class _Alternatives extends ConsumerWidget {
  const _Alternatives({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final phone = context.isPhone;
    final alts = ref.watch(alternativesProvider(tool.id));
    final count = alts.value?.length;
    final compare = OutlinedButton.icon(
      onPressed: () => showCompareSheet(context, tool),
      icon: const Icon(Icons.compare_arrows, size: 18),
      label: const Text('Compare'),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: MaxWidth(
            child: PageHeader(
              title: 'Alternatives to ${tool.name}',
              subtitle: switch (count) {
                null || 0 => 'Tools that do the most similar job.',
                1 => 'One tool does a similar job.',
                _ => '$count tools do a similar job, closest first.',
              },
              trailing: phone ? null : compare,
              bottom: 20,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MaxWidth(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StartedFrom(tool: tool),
                  if (phone) ...[const SizedBox(height: 12), compare],
                  const SizedBox(height: 32),
                  Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      'Closest first',
                      style: LizText.title3.copyWith(color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  child: MaxWidth(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
                      child: ProfileEmptyPanel(
                        icon: Icons.search_off,
                        text:
                            'Nothing in the catalog does a similar enough job '
                            'to ${tool.name} yet.',
                        action: 'Search the catalog',
                        onAction: () => context.push('/search'),
                      ),
                    ),
                  ),
                )
              : MaxWidthSliver(
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
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

/// The tool the page is about, as a framed row: logo, name, tagline and its
/// facts, leading back to its page.
class _StartedFrom extends StatelessWidget {
  const _StartedFrom({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return ToolLink(
      tool: tool,
      builder: (context, open) => Material(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                ToolLogo(tool: tool, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        style: LizText.headline.copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tool.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.callout.copyWith(color: p.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      ToolMeta(tool),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!context.isPhone)
                  Text(
                    'View tool',
                    style: LizText.subhead.copyWith(color: p.textSecondary),
                  ),
                Icon(Icons.chevron_right, color: p.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
