import 'package:flutter/material.dart';
import '../../shared/widgets/liz_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/page_title.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../community/composers.dart';
import '../compare/compare_sheet.dart';
import '../track/bookmark_button.dart';
import 'maker_badge.dart';
import 'similar_tools.dart';
import 'tool_history.dart';
import 'tool_news.dart';
import 'tool_updates.dart';

class ToolDetailScreen extends ConsumerWidget {
  const ToolDetailScreen({super.key, this.toolId, this.slug})
    : assert(toolId != null || slug != null);

  /// One of the two: `/tools/<slug>` for links people read, `/tool/<id>` for
  /// older links and notifications.
  final String? toolId;
  final String? slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = slug != null
        ? toolBySlugProvider(slug!)
        : toolByIdProvider(toolId!);
    final toolAsync = ref.watch(provider);

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
        error: (_, _) => ErrorView(onRetry: () => ref.invalidate(provider)),
        data: (tool) => tool == null
            ? const EmptyView(
                icon: Icons.help_outline,
                title: 'Tool not found',
                message: 'It may have been removed.',
              )
            : PageTitle(
                // The same title the prerendered page carries.
                title: PageTitle.forTool(tool.name, tool.tagline),
                child: _ViewRecorder(
                  toolId: tool.id,
                  child: _ToolBody(tool: tool),
                ),
              ),
      ),
    );
  }

  void _share(Tool tool) {
    // "Check out X on Liz" used to link to the product's own website, so
    // sharing sent people away from Liz — and when a tool had no website it
    // fell back to liz.app, a domain nobody owns. Share Liz's own page for the
    // tool, and only fall back to the product's site if Liz has no address to
    // give (a native build with no SITE_URL).
    final link = Env.permalink(toolPath(tool)) ?? tool.websiteUrl;
    final text = 'Check out ${tool.name} on Liz — ${tool.tagline}';
    Analytics.track('share', toolId: tool.id);
    SharePlus.instance.share(
      ShareParams(text: link == null ? text : '$text\n$link'),
    );
  }
}

/// Records one view of the tool when its page opens — not on every rebuild.
/// Views are one of the signals Rising ranks by, and the server counts a
/// visitor at most once per tool per half hour.
class _ViewRecorder extends StatefulWidget {
  const _ViewRecorder({required this.toolId, required this.child});
  final String toolId;
  final Widget child;

  @override
  State<_ViewRecorder> createState() => _ViewRecorderState();
}

class _ViewRecorderState extends State<_ViewRecorder> {
  @override
  void initState() {
    super.initState();
    Analytics.track('tool_view', toolId: widget.toolId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Visit website" as a real link: it opens in a new tab, can be
/// middle-clicked or copied, and shows its address on hover — and the visit
/// is counted, since sending someone to a tool is the strongest interest Liz
/// sees.
class _VisitButton extends StatelessWidget {
  const _VisitButton({required this.tool, this.expand = false});
  final Tool tool;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(tool.websiteUrl ?? '');
    if (uri == null) return const SizedBox.shrink();
    final button = Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, follow) => FilledButton.icon(
        style: LizButtons.capsule,
        onPressed: () {
          Analytics.track('outbound_click', toolId: tool.id);
          follow?.call();
        },
        icon: const Icon(Icons.north_east, size: 18),
        label: const Text('Visit website'),
      ),
    );
    return expand ? Expanded(child: button) : button;
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

    final header = <Widget>[
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
                      container: true,
                      header: true,
                      headingLevel: 1,
                      child: Text(
                        tool.name,
                        style: LizText.title1.copyWith(color: p.textPrimary),
                      ),
                    ),
                    if (tool.isNew) LizPill(label: 'New', color: p.accent),
                  ],
                ),
                const SizedBox(height: 4),
                Semantics(
                  container: true,
                  child: Text(
                    tool.tagline,
                    style: LizText.body.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (phone)
        // One row on a phone: the call to action takes the width, and
        // save sits beside it as an icon.
        Row(
          children: [
            if (tool.websiteUrl != null) _VisitButton(tool: tool, expand: true),
            const SizedBox(width: 10),
            // Saving is watching: saved tools get change alerts
            // (migration 0044), so there is no separate Follow.
            BookmarkButton(toolId: tool.id, filledStyle: true, compact: true),
            const SizedBox(width: 10),
            IconButton.filled(
              style: LizButtons.tonal(context.liz).merge(
                const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(44, 44)),
                ),
              ),
              tooltip: 'Compare with similar tools',
              onPressed: () => showCompareSheet(context, tool),
              icon: const Icon(Icons.compare_arrows, size: 20),
            ),
          ],
        )
      else
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (tool.websiteUrl != null) _VisitButton(tool: tool),
            BookmarkButton(toolId: tool.id, filledStyle: true),
            FilledButton.icon(
              style: LizButtons.tonal(context.liz).merge(LizButtons.capsule),
              onPressed: () => showCompareSheet(context, tool),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Compare'),
            ),
          ],
        ),
      const SizedBox(height: 24),
    ];
    // The facts and the signal: on a wide screen they stand in a rail beside
    // the reading column, so they stay in view while the page is read.
    final rail = <Widget>[
      _InfoStrip(tool: tool),
      // How it is moving — Signal's lead, before the words about it.
      ToolSignalsSection(tool: tool),
      _SignalLinks(tool: tool),
    ];
    final body = <Widget>[
      if (tool.imageUrl != null) _Preview(tool: tool),

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
                          style: LizText.body.copyWith(color: p.textPrimary),
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
          style: LizText.body.copyWith(color: p.textPrimary, height: 24 / 15),
        ),
      ),

      // What has happened to it.
      ToolTimelineSection(tool: tool),

      // Related products, matched on the embeddings already in the table.
      SimilarToolsSection(toolId: tool.id, slug: tool.slug),

      // Headlines from the news feed that name this tool.
      ToolNewsSection(toolId: tool.id, name: tool.name),

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
                        style: LizText.callout.copyWith(color: p.textSecondary),
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
          loading: () =>
              const Padding(padding: EdgeInsets.all(20), child: LoadingView()),
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

      // For the people who made it: a badge linking back here.
      MakerBadgeRow(tool: tool),
    ];

    // Selectable, so a name, a price note or a paragraph can be copied — which
    // the canvas-drawn page otherwise does not allow.
    return LayoutBuilder(
      builder: (context, box) {
        // Liz is used mostly in a desktop browser: there a single 760 column
        // left two thirds of a wide window empty.
        if (box.maxWidth < 1100) {
          return MaxWidth(
            maxWidth: 760 + gutter * 2,
            child: SelectionArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  phone ? 8 : 24,
                  gutter,
                  48,
                ),
                children: [...header, ...rail, ...body],
              ),
            ),
          );
        }
        return MaxWidth(
          maxWidth: 1200 + gutter * 2,
          child: SelectionArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
                      children: [...header, ...body],
                    ),
                  ),
                  const SizedBox(width: 40),
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
                      children: rail,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The facts a visitor checks before anything else, in one strip between
/// hairlines: rating, price, category, and either what is moving this week or
/// when Liz first saw the tool — the App Store's info row.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final rated = tool.ratingCount > 0;
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
      // A rank only when something measurable moved, and always with what
      // moved. It used to be a position computed from invented totals.
      if (tool.isRising)
        _InfoCell(
          label: 'Rising',
          value: tool.trendRank != null ? '#${tool.trendRank}' : 'This week',
          detail: tool.trendReason!,
          icon: Icons.trending_up,
        )
      else
        _InfoCell(
          label: 'First seen',
          value: DateFormat('d MMM').format(tool.createdAt.toLocal()),
          detail: DateFormat('y').format(tool.createdAt.toLocal()),
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
              style: LizText.label.copyWith(color: p.textSecondary),
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
                container: true,
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
                  leading: const LizMark.icon(),
                ),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          // Its own node, so a screen reader meets the heading first and
          // then the text, rather than the text as the label of a group.
          Semantics(container: true, child: child),
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

/// Where the numbers come from, as links: the repository and its stars, the
/// Hacker News thread and its points. A figure a reader can check.
class _SignalLinks extends StatelessWidget {
  const _SignalLinks({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final github = tool.githubUri;
    final hn = tool.hackerNewsUri;
    final links = <Widget>[
      if (github != null)
        _SourceLink(
          uri: github,
          icon: Icons.star_outline_rounded,
          label: tool.ghStars == null
              ? 'On GitHub'
              : '${compactCount(tool.ghStars!)} stars on GitHub',
        ),
      if (hn != null)
        _SourceLink(
          uri: hn,
          icon: Icons.forum_outlined,
          label: tool.hnPoints == null
              ? 'Discussed on Hacker News'
              : '${compactCount(tool.hnPoints!)} points'
                    '${(tool.hnComments ?? 0) > 0 ? ' · ${compactCount(tool.hnComments!)} comments' : ''}'
                    ' on Hacker News',
        ),
    ];
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 4, runSpacing: 0, children: links),
    );
  }
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({
    required this.uri,
    required this.icon,
    required this.label,
  });
  final Uri uri;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, follow) => TextButton.icon(
        onPressed: follow,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// What the product looks like, from the image its own site declares for
/// link previews. Only the picture: if it will not load, the page closes up
/// rather than showing a broken frame.
class _Preview extends StatefulWidget {
  const _Preview({required this.tool});
  final Tool tool;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final p = context.liz;
    final shape = LizRadius.shape(
      LizRadius.md,
      side: BorderSide(color: p.hairline),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Semantics(
        image: true,
        label: 'Preview of ${widget.tool.name}',
        child: AspectRatio(
          // The shape link previews are made for (1200 x 630).
          aspectRatio: 1.91,
          child: DecoratedBox(
            decoration: ShapeDecoration(color: p.surfaceMuted, shape: shape),
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(LizRadius.md),
              child: Image.network(
                Env.proxiedImage(widget.tool.imageUrl!),
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _failed = true);
                  });
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
