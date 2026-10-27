import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/post.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/top_bar.dart';
import '../../shared/widgets/user_avatar.dart';
import '../auth/guard.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(postByIdProvider(postId));

    return Scaffold(
      appBar: const LizTopBar(
        title: 'Post',
        section: ('Community', '/community'),
        fallback: '/community',
      ),
      body: postAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) =>
            ErrorView(onRetry: () => ref.invalidate(postByIdProvider(postId))),
        data: (post) => post == null
            ? const EmptyView(
                icon: Icons.forum_outlined,
                title: 'Post not found',
                message: 'It may have been removed.',
              )
            : _PostDetailBody(post: post),
      ),
    );
  }
}

class _PostDetailBody extends ConsumerStatefulWidget {
  const _PostDetailBody({required this.post});
  final Post post;

  @override
  ConsumerState<_PostDetailBody> createState() => _PostDetailBodyState();
}

class _PostDetailBodyState extends ConsumerState<_PostDetailBody> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to comment.',
      action: () async {
        await ref
            .read(communityActionsProvider)
            .addComment(widget.post.id, text);
        _controller.clear();
        if (mounted) FocusScope.of(context).unfocus();
      },
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final post = widget.post;
    final author = post.author;
    final comments = ref.watch(commentsProvider(post.id));
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final phone = context.isPhone;
    final count = comments.value?.length ?? post.commentCount;

    return Column(
      children: [
        Expanded(
          child: MaxWidth(
            maxWidth: 720 + gutter * 2,
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, phone ? 12 : 32, gutter, 32),
              children: [
                // The post, framed like it is in the feed, set larger.
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: p.surface,
                    shape: LizRadius.shape(
                      LizRadius.lg,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AuthorLink(
                                author: author,
                                avatarRadius: 20,
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
                                      '@${author?.username ?? 'user'} · '
                                      '${timeAgo(post.createdAt)}',
                                      style: LizText.footnote.copyWith(
                                        color: p.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.flag_outlined, size: 20),
                              tooltip: 'Report',
                              onPressed: () => showReportSheet(
                                context,
                                ref,
                                targetType: 'post',
                                targetId: post.id,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            post.content,
                            style: LizText.body.copyWith(
                              color: p.textPrimary,
                              fontSize: 17,
                              height: 1.5,
                            ),
                          ),
                        ),
                        if (post.toolId != null && post.toolName != null) ...[
                          const SizedBox(height: 14),
                          ToolLinkChip(
                            toolId: post.toolId!,
                            name: post.toolName!,
                          ),
                        ],
                        const SizedBox(height: 6),
                        LikeButton(
                          targetType: 'post',
                          targetId: post.id,
                          initialLiked: post.likedByMe,
                          initialCount: post.likeCount,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Semantics(
                  container: true,
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Comments',
                          style: LizText.title3.copyWith(color: p.textPrimary),
                        ),
                        if (count > 0)
                          TextSpan(
                            text: '  $count',
                            style: LizText.title3.copyWith(
                              color: p.textSecondary,
                              fontWeight: FontWeight.w500,
                              fontFeatures: LizText.tabular,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                comments.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: LoadingView(),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) => DecoratedBox(
                    decoration: ShapeDecoration(
                      color: p.surface,
                      shape: LizRadius.shape(
                        LizRadius.md,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No comments yet — start the thread.',
                              style: LizText.callout.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                if (i > 0)
                                  Divider(height: 1, color: p.hairline),
                                _CommentTile(comment: list[i]),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The reply box, along the foot of the page.
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 720 + gutter * 2),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    10,
                    gutter,
                    10 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Add a comment…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Post comment',
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final author = comment.author;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The avatar is the link to the commenter; the name beside it is
          // part of the comment. Sized and labelled as a control, not a
          // 32px picture read out as initials.
          if (author != null)
            Semantics(
              button: true,
              label: '${author.displayName}, profile',
              container: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.push('/user/${author.id}'),
                child: ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: UserAvatar(profile: author, radius: 16),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 48),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: author?.displayName ?? 'User',
                          style: LizText.subhead.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  ${timeAgo(comment.createdAt)}',
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.body,
                    style: LizText.callout.copyWith(color: p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
