import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/models/post.dart';
import '../../shared/models/review.dart';
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
                .toggleLike(targetType: widget.targetType, targetId: widget.targetId);
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
      icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
          size: 18, color: _liked ? LizColors.rising : scheme.onSurfaceVariant),
      label: Text(compactCount(_count),
          style: TextStyle(
              color: _liked ? LizColors.rising : scheme.onSurfaceVariant)),
      style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant, minimumSize: const Size(0, 36)),
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
  const reasons = [
    'Spam or misleading',
    'Harassment or hate',
    'Inappropriate content',
    'Off-topic',
    'Other',
  ];
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Report content',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ),
          for (final r in reasons)
            ListTile(
              title: Text(r),
              onTap: () => Navigator.of(ctx).pop(r),
            ),
        ],
      ),
    ),
  );
  if (reason == null) return;
  if (!context.mounted) return;
  await runGuardedAction(
    context,
    prompt: 'Sign in to report content.',
    action: () => ref.read(communityActionsProvider).report(
        targetType: targetType, targetId: targetId, reason: reason),
    onDone: () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Thanks — our team will review this.')));
      }
    },
  );
}

class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = post.author;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LizSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (author != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => context.push('/user/${author.id}'),
                    child: UserAvatar(profile: author, radius: 18),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: author == null
                        ? null
                        : () => context.push('/user/${author.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author?.displayName ?? 'Someone',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text('@${author?.username ?? 'user'} · ${timeAgo(post.createdAt)}',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => showReportSheet(context, ref,
                      targetType: 'post', targetId: post.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => context.push('/post/${post.id}'),
              child: Text(post.content, style: const TextStyle(height: 1.35)),
            ),
            if (post.toolId != null && post.toolName != null) ...[
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(LizRadius.sm),
                onTap: () => context.push('/tool/${post.toolId}'),
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
                      Text(post.toolName!,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
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
                  icon: Icon(Icons.mode_comment_outlined,
                      size: 18, color: scheme.onSurfaceVariant),
                  label: Text(compactCount(post.commentCount),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
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
              if (author != null)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push('/user/${author.id}'),
                  child: UserAvatar(profile: author, radius: 16),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: author == null
                          ? null
                          : () => context.push('/user/${author.id}'),
                      child: Text(author?.displayName ?? 'Reviewer',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Row(
                      children: [
                        RatingStars(review.rating.toDouble(), size: 14),
                        const SizedBox(width: 6),
                        Text(timeAgo(review.createdAt),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.flag_outlined, size: 18),
                onPressed: () => showReportSheet(context, ref,
                    targetType: 'review', targetId: review.id),
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
