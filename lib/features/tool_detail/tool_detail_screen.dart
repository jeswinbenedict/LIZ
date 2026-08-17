import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_logo.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../community/composers.dart';
import '../track/bookmark_button.dart';
import '../track/follow_button.dart';

class ToolDetailScreen extends ConsumerWidget {
  const ToolDetailScreen({super.key, required this.toolId});
  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolAsync = ref.watch(toolByIdProvider(toolId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        }),
        actions: [
          toolAsync.maybeWhen(
            data: (tool) => tool == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.ios_share),
                    onPressed: () => _share(tool),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: toolAsync.when(
        loading: () => const LoadingView(),
        error: (_, __) =>
            ErrorView(onRetry: () => ref.invalidate(toolByIdProvider(toolId))),
        data: (tool) => tool == null
            ? const EmptyView(
                icon: Icons.help_outline,
                title: 'Tool not found',
                message: 'It may have been removed.')
            : _ToolBody(tool: tool),
      ),
    );
  }

  void _share(Tool tool) {
    final link = tool.websiteUrl ?? 'https://liz.app/tool/${tool.slug}';
    SharePlus.instance.share(
      ShareParams(text: 'Check out ${tool.name} on Liz — ${tool.tagline}\n$link'),
    );
  }
}

class _ToolBody extends ConsumerWidget {
  const _ToolBody({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final reviewsAsync = ref.watch(reviewsForToolProvider(tool.id));
    final postsAsync =
        ref.watch(postFeedProvider(PostFeedKey(toolId: tool.id)));

    return MaxWidth(
      maxWidth: 860,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToolLogo(tool: tool, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.name,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(tool.tagline,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 15, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PricingBadge(tool.pricingType),
              if (tool.priceNote != null)
                LizPill(label: tool.priceNote!, color: scheme.onSurfaceVariant),
              TrendBadge(tool),
              if (tool.isNew)
                const LizPill(label: 'NEW', color: LizColors.positive, filled: true),
              for (final p in tool.platforms)
                LizPill(label: p, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 16),

          // Actions
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BookmarkButton(toolId: tool.id, filledStyle: true),
              FollowButton(toolId: tool.id),
              if (tool.websiteUrl != null)
                FilledButton.icon(
                  onPressed: () => _launch(tool.websiteUrl!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Visit'),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // AI summary
          if (tool.aiSummary.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(LizRadius.md),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text('AI summary',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: scheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final bullet in tool.aiSummary)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(bullet, style: const TextStyle(height: 1.35))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Description
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(tool.description, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 28),

          // Ratings
          _SectionHeader(
            title: 'Ratings & reviews',
            trailing: TextButton.icon(
              onPressed: () => showReviewComposer(context, ref,
                  toolId: tool.id, toolName: tool.name),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('Write'),
            ),
          ),
          const SizedBox(height: 8),
          _RatingSummary(tool: tool),
          reviewsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(20), child: LoadingView()),
            error: (_, __) => const SizedBox.shrink(),
            data: (List<Review> reviews) => reviews.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No reviews yet — be the first.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < reviews.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ReviewTile(review: reviews[i]),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 28),

          // Community posts
          _SectionHeader(
            title: 'From the community',
            trailing: TextButton.icon(
              onPressed: () => showPostComposer(context, ref,
                  toolId: tool.id, toolName: tool.name),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Post'),
            ),
          ),
          const SizedBox(height: 8),
          postsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(20), child: LoadingView()),
            error: (_, __) => const SizedBox.shrink(),
            data: (posts) => posts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No posts about this tool yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : Column(
                    children: [
                      for (final p in posts) ...[
                        PostCard(post: p),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (tool.ratingCount == 0) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Text(tool.avgRating.toStringAsFixed(1),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RatingStars(tool.avgRating, size: 18),
            const SizedBox(height: 2),
            Text('${tool.ratingCount} rating${tool.ratingCount == 1 ? '' : 's'}',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
