import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/models/post.dart';
import '../../shared/models/profile.dart';
import '../../shared/models/review.dart';
import '../../shared/widgets/liz_sheet.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/user_avatar.dart';
import '../auth/guard.dart';
import 'community_controller.dart';

/// Like/upvote toggle with optimistic local state.
class LikeButton extends ConsumerStatefulWidget {
  const LikeButton({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.initialLiked,
    required this.initialCount,
  });
  final String targetType;
  final String targetId;
  final bool initialLiked;
  final int initialCount;

  @override
  ConsumerState<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends ConsumerState<LikeButton> {
  late bool _liked = widget.initialLiked;
  late int _count = widget.initialCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: () => runGuardedAction(
        context,
        ref: ref,
        prompt: 'Sign in to like posts.',
        action: () async {
          // Optimistic
          setState(() {
            _liked = !_liked;
            _count += _liked ? 1 : -1;
          });
          try {
            final serverLiked = await ref
                .read(communityActionsProvider)
                .toggleLike(
                  targetType: widget.targetType,
                  targetId: widget.targetId,
                );
            if (mounted && serverLiked != _liked) {
              setState(() {
                _liked = serverLiked;
              });
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _liked = !_liked;
                _count += _liked ? 1 : -1;
              });
            }
            rethrow;
          }
        },
      ),
      icon: Icon(
        _liked ? Icons.favorite : Icons.favorite_border,
        size: 18,
        color: _liked ? LizColors.rising : scheme.onSurfaceVariant,
      ),
      label: Text(
        compactCount(_count),
        style: TextStyle(
          color: _liked ? LizColors.rising : scheme.onSurfaceVariant,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        minimumSize: const Size(0, 36),
      ),
    );
  }
}

/// Presents the report sheet and submits the chosen reason.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
}) async {
  final reason = await showLizSheet<String>(
    context,
    builder: (ctx) => _ReportSheet(what: targetType == 'post' ? 'post' : null),
  );
  if (reason == null) return;
  if (!context.mounted) return;
  await runGuardedAction(
    context,
    ref: ref,
    prompt: 'Sign in to report content.',
    action: () => ref
        .read(communityActionsProvider)
        .report(targetType: targetType, targetId: targetId, reason: reason),
    onDone: () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks — our team will review this.')),
        );
      }
    },
  );
}

/// Why something is being reported: one reason, chosen, then sent — a
/// report is not something to file by a slip of the thumb.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({this.what});

  /// "post", or null for anything else.
  final String? what;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = [
    ('Spam or misleading', 'Ads, scams, or claims that are not true.'),
    ('Harassment or hate', 'Attacks a person or a group.'),
    ('Inappropriate content', 'Sexual, violent or otherwise not for here.'),
    ('Off-topic', 'Nothing to do with AI tools.'),
    ('Other', 'Something else a moderator should see.'),
  ];
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return LizSheet(
      title: widget.what == null ? 'Report' : 'Report this ${widget.what}',
      subtitle: 'A moderator will look at it. Choose the closest reason.',
      actions: [
        OutlinedButton(
          style: LizSheetButtons.outlined,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: LizSheetButtons.filled,
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(_reason),
          child: const Text('Send report'),
        ),
      ],
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(LizRadius.md),
          child: RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(
              children: [
                for (var i = 0; i < _reasons.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.hairline),
                  RadioListTile<String>(
                    value: _reasons[i].$1,
                    contentPadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
                    controlAffinity: ListTileControlAffinity.trailing,
                    title: Text(
                      _reasons[i].$1,
                      style: LizText.body.copyWith(color: p.textPrimary),
                    ),
                    subtitle: Text(
                      _reasons[i].$2,
                      style: LizText.footnote.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final author = post.author;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AuthorLink(
                    author: author,
                    avatarRadius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author?.displayName ?? 'Someone',
                          style: LizText.callout.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '@${author?.username ?? 'user'} · ${timeAgo(post.createdAt)}',
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Report this post',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => showReportSheet(
                    context,
                    ref,
                    targetType: 'post',
                    targetId: post.id,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => context.push('/post/${post.id}'),
                child: Text(
                  post.content,
                  style: LizText.body.copyWith(color: p.textPrimary),
                ),
              ),
            ),
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(LizRadius.md),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  imageBuilder: (context, image) => Semantics(
                    label: 'Image attached to this post',
                    image: true,
                    child: Image(image: image, fit: BoxFit.cover),
                  ),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            if (post.toolId != null && post.toolName != null) ...[
              const SizedBox(height: 10),
              ToolLinkChip(toolId: post.toolId!, name: post.toolName!),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                LikeButton(
                  targetType: 'post',
                  targetId: post.id,
                  initialLiked: post.likedByMe,
                  initialCount: post.likeCount,
                ),
                TextButton.icon(
                  onPressed: () => context.push('/post/${post.id}'),
                  icon: Icon(
                    Icons.mode_comment_outlined,
                    size: 18,
                    color: p.textSecondary,
                  ),
                  label: Text(
                    compactCount(post.commentCount),
                    style: LizText.footnote.copyWith(
                      color: p.textSecondary,
                      fontFeatures: LizText.tabular,
                    ),
                  ),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewTile extends ConsumerWidget {
  const ReviewTile({super.key, required this.review});
  final Review review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = review.author;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AuthorLink(
                  author: author,
                  avatarRadius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author?.displayName ?? 'Reviewer',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Row(
                        children: [
                          RatingStars(review.rating.toDouble(), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            timeAgo(review.createdAt),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Report this review',
                icon: const Icon(Icons.flag_outlined, size: 18),
                onPressed: () => showReportSheet(
                  context,
                  ref,
                  targetType: 'review',
                  targetId: review.id,
                ),
              ),
            ],
          ),
          if (review.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.body, style: const TextStyle(height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// Who wrote something: avatar and name as one link to their profile.
///
/// They were two links, each smaller than a fingertip — a 32px avatar and a
/// one-line name — and a screen reader announced the first as "MC". One target
/// at least 48px tall, read as the person's name, fixes both.
class AuthorLink extends StatelessWidget {
  const AuthorLink({
    super.key,
    required this.author,
    required this.avatarRadius,
    required this.child,
  });

  final Profile? author;
  final double avatarRadius;

  /// The name and whatever sits under it (handle, time, rating).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final who = author;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(LizRadius.sm),
        onTap: who == null ? null : () => context.push('/user/${who.id}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (who != null) ...[
                ExcludeSemantics(
                  child: UserAvatar(profile: who, radius: avatarRadius),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tool a post is about, as a link to its page.
///
/// Drawn as a compact chip but hit as a 48px-tall target: it was 36px, under
/// the size a finger can reliably land on.
class ToolLinkChip extends StatelessWidget {
  const ToolLinkChip({super.key, required this.toolId, required this.name});
  final String toolId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(LizRadius.sm),
      onTap: () => context.push('/tool/$toolId'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(LizRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
