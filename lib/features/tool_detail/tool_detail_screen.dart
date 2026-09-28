import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/tool_logo.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../community/composers.dart';
import '../track/bookmark_button.dart';
import '../track/follow_button.dart';
import 'similar_tools.dart';
import 'tool_updates.dart';

class ToolDetailScreen extends ConsumerWidget {
  const ToolDetailScreen({super.key, required this.toolId});
  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolAsync = ref.watch(toolByIdProvider(toolId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
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
        error: (_, _) =>
            ErrorView(onRetry: () => ref.invalidate(toolByIdProvider(toolId))),
        data: (tool) => tool == null
            ? const EmptyView(
                icon: Icons.help_outline,
                title: 'Tool not found',
                message: 'It may have been removed.',
              )
            : _ToolBody(tool: tool),
      ),
    );
  }

  void _share(Tool tool) {
    // "Check out X on Liz" used to link to the product's own website, so
    // sharing sent people away from Liz — and when a tool had no website it
    // fell back to liz.app, a domain nobody owns. Share Liz's own page for the
    // tool, and only fall back to the product's site if Liz has no address to
    // give (a native build with no SITE_URL).
    final link = Env.toolPermalink(tool.id) ?? tool.websiteUrl;
    final text = 'Check out ${tool.name} on Liz — ${tool.tagline}';
    SharePlus.instance.share(
      ShareParams(text: link == null ? text : '$text\n$link'),
    );
  }
}

/// A tool's page, laid out like an App Store product page (docs/DESIGN.md
/// §8): the icon, name and one call to action first; the facts a visitor
/// checks in a strip under it; then titled sections in a reading column.
class _ToolBody extends ConsumerWidget {
  const _ToolBody({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final reviewsAsync = ref.watch(reviewsForToolProvider(tool.id));
    final postsAsync = ref.watch(
      postFeedProvider(PostFeedKey(toolId: tool.id)),
    );
    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return MaxWidth(
      maxWidth: 760 + gutter * 2,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, phone ? 8 : 24, gutter, 48),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToolLogo(tool: tool, size: phone ? 76 : 96),
              SizedBox(width: phone ? 16 : 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            tool.name,
                            style: LizText.title1.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (tool.isNew) LizPill(label: 'New', color: p.accent),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tool.tagline,
                      style: LizText.body.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (phone)
            // One row on a phone: the call to action takes the width, and
            // save and follow sit beside it as icons, rather than wrapping
            // Follow onto a line of its own.
            Row(
              children: [
                if (tool.websiteUrl != null)
                  Expanded(
                    child: FilledButton.icon(
                      style: LizButtons.capsule,
                      onPressed: () => _launch(tool.websiteUrl!),
                      icon: const Icon(Icons.north_east, size: 18),
                      label: const Text('Visit website'),
                    ),
                  ),
                const SizedBox(width: 10),
                BookmarkButton(
                  toolId: tool.id,
                  filledStyle: true,
                  compact: true,
                ),
                const SizedBox(width: 10),
                FollowButton(toolId: tool.id, compact: true),
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (tool.websiteUrl != null)
                  FilledButton.icon(
                    style: LizButtons.capsule,
                    onPressed: () => _launch(tool.websiteUrl!),
                    icon: const Icon(Icons.north_east, size: 18),
                    label: const Text('Visit website'),
                  ),
                BookmarkButton(toolId: tool.id, filledStyle: true),
                FollowButton(toolId: tool.id),
              ],
            ),
          const SizedBox(height: 24),
          _InfoStrip(tool: tool),

          if (tool.aiSummary.isNotEmpty)
            _Section(
              title: 'Summary',
              badge: 'AI',
              child: Column(
                children: [
                  for (final bullet in tool.aiSummary)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 8, right: 12),
                            decoration: BoxDecoration(
                              color: p.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              bullet,
                              style: LizText.body.copyWith(
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          _Section(
            title: 'About',
            child: Text(
              tool.description,
              style: LizText.body.copyWith(
                color: p.textPrimary,
                height: 24 / 15,
              ),
            ),
          ),

          // Related products, matched on the embeddings already in the table.
          SimilarToolsSection(toolId: tool.id),

          // Live "what's new" for this tool — real releases / feature updates.
          ToolUpdatesSection(
            name: tool.name,
            slug: tool.slug,
            sourceUrl: tool.sourceUrl,
          ),

          _Section(
            title: 'Ratings & reviews',
            trailing: TextButton.icon(
              onPressed: () => showReviewComposer(
                context,
                ref,
                toolId: tool.id,
                toolName: tool.name,
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Write a review'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RatingSummary(tool: tool),
                reviewsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: LoadingView(),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (List<Review> reviews) => reviews.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No reviews yet — be the first.',
                            style: LizText.callout.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
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
              ],
            ),
          ),

          _Section(
            title: 'From the community',
            trailing: TextButton.icon(
              onPressed: () => showPostComposer(
                context,
                ref,
                toolId: tool.id,
                toolName: tool.name,
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Post'),
            ),
            child: postsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: LoadingView(),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (posts) => posts.isEmpty
                  ? Text(
                      'No posts about this tool yet.',
                      style: LizText.callout.copyWith(color: p.textSecondary),
                    )
                  : Column(
                      children: [
                        for (final post in posts) ...[
                          PostCard(post: post),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
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

/// The facts a visitor checks before anything else, in one strip between
/// hairlines: rating, price, category, standing — the App Store's info row.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final rated = tool.ratingCount > 0;
    final ranked = tool.trendRank != null;
    final cells = <Widget>[
      _InfoCell(
        label: 'Rating',
        value: rated ? tool.avgRating.toStringAsFixed(1) : '—',
        detail: rated
            ? '${compactCount(tool.ratingCount)} ratings'
            : 'No ratings yet',
        icon: rated ? Icons.star_rounded : null,
      ),
      _InfoCell(
        label: 'Price',
        value: tool.pricingType == PricingType.unknown
            ? 'Unknown'
            : tool.pricingType.label,
        detail: tool.priceNote ?? '',
        dot: pricingColor(context, tool.pricingType),
      ),
      _InfoCell(
        label: 'Category',
        value: categoryLabel(tool.category),
        detail: tool.platforms.join(', '),
      ),
      _InfoCell(
        label: 'Trending',
        value: ranked
            ? '#${tool.trendRank}'
            : compactCount(tool.trendScore.round()),
        detail: ranked ? 'in the catalog' : 'trend score',
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: p.hairline)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four across when they fit; on a phone, two by two.
          final perRow = constraints.maxWidth >= 520 ? 4 : 2;
          final rows = <Widget>[];
          for (var i = 0; i < cells.length; i += perRow) {
            if (i > 0) rows.add(Divider(height: 1, color: p.hairline));
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var j = i;
                      j < i + perRow && j < cells.length;
                      j++
                    ) ...[
                      if (j > i)
                        VerticalDivider(
                          width: 1,
                          indent: 12,
                          endIndent: 12,
                          color: p.hairline,
                        ),
                      Expanded(child: cells[j]),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        },
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.label,
    required this.value,
    required this.detail,
    this.icon,
    this.dot,
  });

  final String label;
  final String value;
  final String detail;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      label: detail.isEmpty ? '$label: $value' : '$label: $value, $detail',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: LizText.caption.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.title3.copyWith(
                      color: p.textPrimary,
                      fontFeatures: LizText.tabular,
                    ),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 3),
                  Icon(icon, size: 18, color: p.textPrimary),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              detail.isEmpty ? ' ' : detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled section of the tool page.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing,
    this.badge,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: LizText.title2.copyWith(color: p.textPrimary),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                LizPill(
                  label: badge!,
                  color: p.accent,
                  icon: Icons.auto_awesome,
                ),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    if (tool.ratingCount == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            tool.avgRating.toStringAsFixed(1),
            style: LizText.largeTitle.copyWith(
              color: p.textPrimary,
              fontSize: 44,
              fontFeatures: LizText.tabular,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RatingStars(tool.avgRating, size: 18),
              const SizedBox(height: 4),
              Text(
                'out of 5 · ${compactCount(tool.ratingCount)} '
                'rating${tool.ratingCount == 1 ? '' : 's'}',
                style: LizText.subhead.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
