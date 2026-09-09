import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/post.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
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
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/community');
            }
          },
        ),
        title: const Text('Post'),
      ),
      body: postAsync.when(
        loading: () => const LoadingView(),
        error: (_, __) =>
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
      prompt: 'Sign in to comment.',
      action: () async {
        await ref
            .read(communityActionsProvider)
            .addComment(widget.post.id, text);
        _controller.clear();
        FocusScope.of(context).unfocus();
      },
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = widget.post;
    final author = post.author;
    final comments = ref.watch(commentsProvider(post.id));

    return MaxWidth(
      maxWidth: 720,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                // Post
                Row(
                  children: [
                    if (author != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => context.push('/user/${author.id}'),
                        child: UserAvatar(profile: author, radius: 20),
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
                            Text(
                              author?.displayName ?? 'Someone',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '@${author?.username ?? 'user'} · ${timeAgo(post.createdAt)}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.flag_outlined),
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
                const SizedBox(height: 12),
                Text(
                  post.content,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                if (post.toolId != null && post.toolName != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(LizRadius.sm),
                    onTap: () => context.push('/tool/${post.toolId}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(LizRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            post.toolName!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                LikeButton(
                  targetType: 'post',
                  targetId: post.id,
                  initialLiked: post.likedByMe,
                  initialCount: post.likeCount,
                ),
                const Divider(height: 24),
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                comments.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: LoadingView(),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'No comments yet — start the thread.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : Column(
                          children: [
                            for (final c in list) _CommentTile(comment: c),
                          ],
                        ),
                ),
              ],
            ),
          ),
          // Composer
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                8 + MediaQuery.viewInsetsOf(context).bottom,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = comment.author;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Text(
                      author?.displayName ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeAgo(comment.createdAt),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
