import 'dart:math' as math;

import '../../shared/models/app_notification.dart';
import '../../shared/models/category.dart';
import '../../shared/models/collection.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/news_item.dart';
import '../../shared/models/paginated.dart';
import '../../shared/models/post.dart';
import '../../shared/models/profile.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';
import '../auth/auth_repository.dart';
import '../data/mock_data.dart';
import '../errors.dart';
import 'repositories.dart';

/// Shared mutable in-memory store so all three mock repos see the same data
/// within a session (a post you create shows up in feeds immediately).
class MockStore {
  MockStore()
    : tools = [...MockData.tools],
      posts = [...MockData.posts],
      reviews = [...MockData.reviews],
      news = [...MockData.news];

  final List<Tool> tools;
  final List<Post> posts;
  final List<Review> reviews;
  final List<NewsItem> news;
  final Map<String, List<Comment>> commentsByPost = {};

  final Set<String> bookmarks = {};
  final Set<String> follows = {}; // followed tool ids
  final Set<String> userFollows = {}; // followed user ids
  final Set<String> likes = {}; // "$type:$id"
  final List<Collection> collections = [];

  /// Seeded so the alerts screen shows what a real one looks like without a
  /// backend — one unread, one already seen.
  final List<AppNotification> notifications = [
    AppNotification(
      id: 'n-1',
      type: 'pricing',
      title: 'Descript changed its pricing',
      body: 'Free is now Freemium.',
      route: '/tool/t-1',
      read: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    AppNotification(
      id: 'n-2',
      type: 'trending',
      title: 'Otter.ai is climbing',
      body: 'It just entered the top 10 on Liz.',
      route: '/tool/t-2',
      read: true,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  /// Seeded so the admin moderation queue isn't empty in demo mode.
  final List<ReportEntry> reports = [
    ReportEntry(
      id: 'rep-1',
      targetType: 'post',
      targetId: 'p-6',
      reason: 'Off-topic',
      preview: 'PSA: if you deal with messy CSVs…',
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  int _seq = 0;

  String nextId(String prefix) =>
      '$prefix-mock-${_seq++}-'
      '${DateTime.now().microsecondsSinceEpoch}';
}

int _decodeCursor(String? cursor) =>
    cursor == null ? 0 : int.tryParse(cursor) ?? 0;

Paginated<T> _page<T>(List<T> all, int offset, int limit) {
  final slice = all.skip(offset).take(limit).toList();
  final next = offset + limit;
  return Paginated(items: slice, cursor: next < all.length ? '$next' : null);
}

class MockContentRepository implements ContentRepository {
  MockContentRepository(this._store);
  final MockStore _store;

  @override
  Future<List<Category>> categories() async => MockData.categories;

  double _risingScore(Tool t) {
    // High momentum, still low absolute popularity → surface it early.
    final popularityPenalty = math.log(t.saveCount + 10) * 6;
    final recency = math.max(
      0,
      20 - DateTime.now().difference(t.createdAt).inDays,
    );
    return t.trendScore + recency - popularityPenalty;
  }

  @override
  Future<Paginated<Tool>> tools(ToolQuery q) async {
    Iterable<Tool> list = _store.tools.where(
      (t) => t.status == PublishStatus.published,
    );

    if (q.categorySlug != null) {
      list = list.where((t) => t.category == q.categorySlug);
    }
    if (q.tag != null) {
      list = list.where((t) => t.tags.contains(q.tag));
    }
    if (q.pricing != null) {
      list = list.where((t) => t.pricingType == q.pricing);
    }
    if (q.search != null && q.search!.trim().isNotEmpty) {
      final s = q.search!.toLowerCase();
      list = list.where(
        (t) =>
            t.name.toLowerCase().contains(s) ||
            t.tagline.toLowerCase().contains(s) ||
            t.tags.any((tag) => tag.contains(s)),
      );
    }

    final sorted = list.toList();
    switch (q.sort) {
      case ToolSort.trending:
        sorted.sort((a, b) => b.trendScore.compareTo(a.trendScore));
      case ToolSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ToolSort.rising:
        sorted.sort((a, b) => _risingScore(b).compareTo(_risingScore(a)));
      case ToolSort.topRated:
        sorted.sort((a, b) {
          final r = b.avgRating.compareTo(a.avgRating);
          return r != 0 ? r : b.ratingCount.compareTo(a.ratingCount);
        });
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _page(sorted, _decodeCursor(q.cursor), q.limit);
  }

  @override
  Future<Tool?> toolById(String id) async {
    try {
      return _store.tools.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Tool?> toolBySlug(String slug) async {
    try {
      return _store.tools.firstWhere((t) => t.slug == slug);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Tool>> compareTools(List<String> ids) async =>
      _store.tools.where((t) => ids.contains(t.id)).toList();

  @override
  Future<Paginated<NewsItem>> news({int limit = 20, String? cursor}) async {
    final sorted = [..._store.news]
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return _page(sorted, _decodeCursor(cursor), limit);
  }

  @override
  Future<List<Tool>> searchTools(String query) async {
    final s = query.toLowerCase().trim();
    if (s.isEmpty) return [];
    return _store.tools.where((t) {
      return t.name.toLowerCase().contains(s) ||
          t.tagline.toLowerCase().contains(s) ||
          t.description.toLowerCase().contains(s) ||
          t.tags.any((tag) => tag.contains(s)) ||
          t.category.contains(s);
    }).toList();
  }
}

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository(this._store, this._auth);
  final MockStore _store;
  final AuthRepository _auth;

  Profile _requireUser() {
    final p = _auth.currentProfile;
    if (p == null) throw const AuthRequiredException();
    return p;
  }

  bool _liked(String type, String id) => _store.likes.contains('$type:$id');

  @override
  Future<Paginated<Post>> feed({
    bool trending = false,
    String? toolId,
    String? userId,
    int limit = 20,
    String? cursor,
  }) async {
    Iterable<Post> list = _store.posts.where((p) => p.status == 'active');
    if (toolId != null) list = list.where((p) => p.toolId == toolId);
    if (userId != null) list = list.where((p) => p.userId == userId);
    final sorted = list
        .map((p) => p.copyWith(likedByMe: _liked('post', p.id)))
        .toList();
    if (trending) {
      sorted.sort(
        (a, b) => (b.likeCount + b.commentCount).compareTo(
          a.likeCount + a.commentCount,
        ),
      );
    } else {
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _page(sorted, _decodeCursor(cursor), limit);
  }

  @override
  Future<Post> createPost({
    required String content,
    String? toolId,
    String? imageUrl,
  }) async {
    final user = _requireUser();
    String? toolName;
    if (toolId != null) {
      toolName = _store.tools
          .where((t) => t.id == toolId)
          .map((t) => t.name)
          .firstOrNull;
    }
    final post = Post(
      id: _store.nextId('p'),
      userId: user.id,
      toolId: toolId,
      toolName: toolName,
      content: content,
      imageUrl: imageUrl,
      likeCount: 0,
      commentCount: 0,
      status: 'active',
      createdAt: DateTime.now(),
      author: user,
    );
    _store.posts.insert(0, post);
    return post;
  }

  @override
  Future<List<Comment>> comments(String postId) async =>
      _store.commentsByPost[postId] ?? [];

  @override
  Future<Comment> addComment(String postId, String body) async {
    final user = _requireUser();
    final comment = Comment(
      id: _store.nextId('c'),
      postId: postId,
      userId: user.id,
      body: body,
      status: 'active',
      createdAt: DateTime.now(),
      author: user,
    );
    (_store.commentsByPost[postId] ??= []).add(comment);
    final idx = _store.posts.indexWhere((p) => p.id == postId);
    if (idx >= 0) {
      _store.posts[idx] = _store.posts[idx].copyWith(
        commentCount: _store.posts[idx].commentCount + 1,
      );
    }
    return comment;
  }

  @override
  Future<List<Review>> reviewsForTool(String toolId) async {
    final list =
        _store.reviews
            .where((r) => r.toolId == toolId && r.status == 'active')
            .map((r) => r.copyWith(likedByMe: _liked('review', r.id)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<List<Review>> reviewsByUser(String userId) async => _store.reviews
      .where((r) => r.userId == userId && r.status == 'active')
      .toList();

  @override
  Future<Profile?> profileById(String userId) async {
    final me = _auth.currentProfile;
    if (me != null && me.id == userId) return me;
    try {
      return MockData.profiles.firstWhere((p) => p.id == userId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Review> upsertReview({
    required String toolId,
    required int rating,
    required String body,
  }) async {
    final user = _requireUser();
    final existing = _store.reviews.indexWhere(
      (r) => r.toolId == toolId && r.userId == user.id,
    );
    final review = Review(
      id: existing >= 0 ? _store.reviews[existing].id : _store.nextId('r'),
      userId: user.id,
      toolId: toolId,
      rating: rating.clamp(1, 5),
      body: body,
      status: 'active',
      createdAt: DateTime.now(),
      author: user,
    );
    if (existing >= 0) {
      _store.reviews[existing] = review;
    } else {
      _store.reviews.insert(0, review);
    }
    _recomputeRating(toolId);
    return review;
  }

  void _recomputeRating(String toolId) {
    final rs = _store.reviews.where(
      (r) => r.toolId == toolId && r.status == 'active',
    );
    if (rs.isEmpty) return;
    final avg = rs.map((r) => r.rating).reduce((a, b) => a + b) / rs.length;
    final idx = _store.tools.indexWhere((t) => t.id == toolId);
    if (idx >= 0) {
      _store.tools[idx] = _store.tools[idx].copyWith(
        avgRating: double.parse(avg.toStringAsFixed(2)),
        ratingCount: rs.length,
      );
    }
  }

  @override
  Future<bool> toggleLike({
    required String targetType,
    required String targetId,
  }) async {
    _requireUser();
    final key = '$targetType:$targetId';
    final nowLiked = !_store.likes.contains(key);
    if (nowLiked) {
      _store.likes.add(key);
    } else {
      _store.likes.remove(key);
    }
    if (targetType == 'post') {
      final idx = _store.posts.indexWhere((p) => p.id == targetId);
      if (idx >= 0) {
        _store.posts[idx] = _store.posts[idx].copyWith(
          likeCount: _store.posts[idx].likeCount + (nowLiked ? 1 : -1),
        );
      }
    } else if (targetType == 'review') {
      final idx = _store.reviews.indexWhere((r) => r.id == targetId);
      if (idx >= 0) {
        _store.reviews[idx] = _store.reviews[idx].copyWith(
          likeCount: _store.reviews[idx].likeCount + (nowLiked ? 1 : -1),
        );
      }
    }
    return nowLiked;
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    _requireUser();
    // In mock mode we just acknowledge; the Supabase impl records + auto-hides.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

class MockAdminRepository implements AdminRepository {
  MockAdminRepository(this._store);
  final MockStore _store;

  @override
  Future<List<Tool>> allTools() async =>
      [..._store.tools]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> setToolStatus(String toolId, PublishStatus status) async {
    final idx = _store.tools.indexWhere((t) => t.id == toolId);
    if (idx >= 0)
      _store.tools[idx] = _store.tools[idx].copyWith(status: status);
  }

  @override
  Future<List<NewsItem>> allNews() async => [..._store.news];

  @override
  Future<List<Post>> flaggedPosts() async {
    final ids = _store.reports
        .where((r) => r.targetType == 'post')
        .map((r) => r.targetId)
        .toSet();
    return _store.posts.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<void> setPostStatus(String postId, String status) async {
    final idx = _store.posts.indexWhere((p) => p.id == postId);
    if (idx >= 0)
      _store.posts[idx] = _store.posts[idx].copyWith(status: status);
  }

  @override
  Future<List<ReportEntry>> openReports() async => [..._store.reports];

  @override
  Future<void> resolveReport(String reportId) async {
    _store.reports.removeWhere((r) => r.id == reportId);
  }
}

class MockTrackRepository implements TrackRepository {
  MockTrackRepository(this._store, this._auth);
  final MockStore _store;
  final AuthRepository _auth;

  void _requireUser() {
    if (_auth.currentProfile == null) throw const AuthRequiredException();
  }

  @override
  Future<Set<String>> bookmarkedToolIds() async => {..._store.bookmarks};

  @override
  Future<List<Tool>> bookmarkedTools() async =>
      _store.tools.where((t) => _store.bookmarks.contains(t.id)).toList();

  @override
  Future<bool> toggleBookmark(String toolId) async {
    _requireUser();
    final added = !_store.bookmarks.contains(toolId);
    if (added) {
      _store.bookmarks.add(toolId);
    } else {
      _store.bookmarks.remove(toolId);
    }
    final idx = _store.tools.indexWhere((t) => t.id == toolId);
    if (idx >= 0) {
      _store.tools[idx] = _store.tools[idx].copyWith(
        saveCount: _store.tools[idx].saveCount + (added ? 1 : -1),
      );
    }
    return added;
  }

  @override
  Future<List<Collection>> collections() async => _store.collections;

  @override
  Future<Collection> createCollection(String name) async {
    _requireUser();
    final c = Collection(
      id: _store.nextId('col'),
      userId: _auth.currentUserId!,
      name: name,
      createdAt: DateTime.now(),
    );
    _store.collections.add(c);
    return c;
  }

  @override
  Future<Set<String>> followedToolIds() async => {..._store.follows};

  @override
  Future<bool> toggleFollowTool(String toolId) async {
    _requireUser();
    final added = !_store.follows.contains(toolId);
    if (added) {
      _store.follows.add(toolId);
    } else {
      _store.follows.remove(toolId);
    }
    return added;
  }

  @override
  Future<Set<String>> followedUserIds() async => {..._store.userFollows};

  @override
  Future<bool> toggleFollowUser(String userId) async {
    _requireUser();
    final added = !_store.userFollows.contains(userId);
    if (added) {
      _store.userFollows.add(userId);
    } else {
      _store.userFollows.remove(userId);
    }
    return added;
  }

  @override
  Future<List<AppNotification>> notifications({int limit = 50}) async {
    if (_auth.currentProfile == null) return const [];
    return _store.notifications.take(limit).toList();
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final i = _store.notifications.indexWhere((n) => n.id == id);
    if (i >= 0) {
      _store.notifications[i] = _store.notifications[i].copyWith(read: true);
    }
  }

  @override
  Future<void> markAllNotificationsRead() async {
    for (var i = 0; i < _store.notifications.length; i++) {
      _store.notifications[i] = _store.notifications[i].copyWith(read: true);
    }
  }
}
