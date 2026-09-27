import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/post.dart';
import '../../shared/models/profile.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';

/// Key for a community feed query.
@immutable
class PostFeedKey {
  const PostFeedKey({this.trending = false, this.toolId, this.userId});
  final bool trending;
  final String? toolId;
  final String? userId;

  @override
  bool operator ==(Object other) =>
      other is PostFeedKey &&
      other.trending == trending &&
      other.toolId == toolId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(trending, toolId, userId);
}

/// Community post feed (first page). Kept simple with pull-to-refresh; the
/// repository supports cursoring for future infinite scroll.
final postFeedProvider = FutureProvider.autoDispose
    .family<List<Post>, PostFeedKey>((ref, key) async {
      final page = await ref
          .watch(communityRepositoryProvider)
          .feed(trending: key.trending, toolId: key.toolId, userId: key.userId);
      return page.items;
    });

final toolByIdProvider = FutureProvider.autoDispose.family<Tool?, String>((
  ref,
  id,
) async {
  return ref.watch(contentRepositoryProvider).toolById(id);
});

final reviewsForToolProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, toolId) async {
      return ref.watch(communityRepositoryProvider).reviewsForTool(toolId);
    });

final reviewsByUserProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, userId) async {
      return ref.watch(communityRepositoryProvider).reviewsByUser(userId);
    });

/// A single post by id (for the post detail screen). Scans the newest feed —
/// fine for the current scale and keeps the repository API lean.
final postByIdProvider = FutureProvider.autoDispose.family<Post?, String>((
  ref,
  postId,
) async {
  // Asked for by id. It used to read the newest 100 posts and look through
  // them, so a link to anything older opened as "not found".
  return ref.watch(communityRepositoryProvider).post(postId);
});

/// Comments for a post.
final commentsProvider = FutureProvider.autoDispose
    .family<List<Comment>, String>((ref, postId) async {
      return ref.watch(communityRepositoryProvider).comments(postId);
    });

/// A public profile by id (for viewing other users).
final profileByIdProvider = FutureProvider.autoDispose.family<Profile?, String>(
  (ref, userId) async {
    return ref.watch(communityRepositoryProvider).profileById(userId);
  },
);

/// Imperative actions for community interactions. Throws
/// [AuthRequiredException] to guests so the UI can prompt sign-in.
class CommunityActions {
  CommunityActions(this._ref);
  final Ref _ref;

  Future<Post> createPost({
    required String content,
    String? toolId,
    String? imageUrl,
  }) async {
    final post = await _ref
        .read(communityRepositoryProvider)
        .createPost(content: content, toolId: toolId, imageUrl: imageUrl);
    _invalidateFeeds(toolId: toolId);
    return post;
  }

  Future<Comment> addComment(String postId, String body) async {
    final comment = await _ref
        .read(communityRepositoryProvider)
        .addComment(postId, body);
    _ref.invalidate(commentsProvider(postId));
    _ref.invalidate(postByIdProvider(postId));
    _ref.invalidate(postFeedProvider); // refresh comment counts
    return comment;
  }

  Future<Review> upsertReview({
    required String toolId,
    required int rating,
    required String body,
  }) async {
    final review = await _ref
        .read(communityRepositoryProvider)
        .upsertReview(toolId: toolId, rating: rating, body: body);
    _ref.invalidate(reviewsForToolProvider(toolId));
    _ref.invalidate(toolByIdProvider(toolId));
    return review;
  }

  Future<bool> toggleLike({
    required String targetType,
    required String targetId,
  }) {
    return _ref
        .read(communityRepositoryProvider)
        .toggleLike(targetType: targetType, targetId: targetId);
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) {
    return _ref
        .read(communityRepositoryProvider)
        .report(targetType: targetType, targetId: targetId, reason: reason);
  }

  void _invalidateFeeds({String? toolId}) {
    _ref.invalidate(postFeedProvider);
  }
}

final communityActionsProvider = Provider<CommunityActions>(
  (ref) => CommunityActions(ref),
);
