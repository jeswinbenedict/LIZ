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

/// How a tool feed is ordered. `rising` implements the "rising early" idea:
/// high velocity but still low absolute popularity.
enum ToolSort { trending, newest, rising, topRated }

/// Query parameters for the discover feed.
class ToolQuery {
  const ToolQuery({
    this.sort = ToolSort.trending,
    this.categorySlug,
    this.tag,
    this.search,
    this.limit = 20,
    this.cursor,
    this.includeProse = false,
  });

  final ToolSort sort;
  final String? categorySlug;
  final String? tag;
  final String? search;
  final int limit;
  final String? cursor;

  /// Whether the long description and AI summary are needed.
  ///
  /// A feed card shows neither, and together they are roughly half the bytes
  /// of a tool row — so a page of the grid ships twice what it draws unless
  /// the caller says it actually reads them.
  final bool includeProse;

  ToolQuery copyWith({
    ToolSort? sort,
    String? categorySlug,
    String? tag,
    String? search,
    String? cursor,
  }) => ToolQuery(
    sort: sort ?? this.sort,
    categorySlug: categorySlug ?? this.categorySlug,
    tag: tag ?? this.tag,
    search: search ?? this.search,
    limit: limit,
    cursor: cursor,
    includeProse: includeProse,
  );
}

/// Discovery content: tools, categories, news, search.
abstract interface class ContentRepository {
  Future<List<Category>> categories();
  Future<Paginated<Tool>> tools(ToolQuery query);
  Future<Tool?> toolById(String id);
  Future<Tool?> toolBySlug(String slug);
  Future<List<Tool>> compareTools(List<String> ids);
  Future<Paginated<NewsItem>> news({int limit = 20, String? cursor});

  /// Full-text-ish search across tools (name, tagline, tags).
  Future<List<Tool>> searchTools(String query);
}

/// Community: posts, reviews, comments, likes, reports.
abstract interface class CommunityRepository {
  Future<Paginated<Post>> feed({
    bool trending = false,
    String? toolId,
    String? userId,
    int limit = 20,
    String? cursor,
  });
  Future<Post> createPost({
    required String content,
    String? toolId,
    String? imageUrl,
  });
  Future<List<Comment>> comments(String postId);
  Future<Comment> addComment(String postId, String body);

  Future<List<Review>> reviewsForTool(String toolId);
  Future<List<Review>> reviewsByUser(String userId);

  /// Fetch a single public profile by id (for viewing other users).
  Future<Profile?> profileById(String userId);

  /// Upsert the current user's review for a tool (one per user/tool).
  Future<Review> upsertReview({
    required String toolId,
    required int rating,
    required String body,
  });

  /// Toggle a like on a post/review/comment. Returns the new liked state.
  Future<bool> toggleLike({
    required String targetType,
    required String targetId,
  });

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  });
}

/// A reported item awaiting moderation.
class ReportEntry {
  const ReportEntry({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.preview,
    required this.createdAt,
  });
  final String id;
  final String targetType;
  final String targetId;
  final String reason;
  final String preview;
  final DateTime createdAt;
}

/// Admin / moderation surface (role-gated by RLS in production).
abstract interface class AdminRepository {
  Future<List<Tool>> allTools();
  Future<void> setToolStatus(String toolId, PublishStatus status);
  Future<List<NewsItem>> allNews();
  Future<List<Post>> flaggedPosts();
  Future<void> setPostStatus(String postId, String status);
  Future<List<ReportEntry>> openReports();
  Future<void> resolveReport(String reportId);
}

/// Track / follow: bookmarks, collections, follows.
abstract interface class TrackRepository {
  Future<Set<String>> bookmarkedToolIds();
  Future<List<Tool>> bookmarkedTools();
  Future<bool> toggleBookmark(String toolId);

  Future<List<Collection>> collections();
  Future<Collection> createCollection(String name);

  Future<Set<String>> followedToolIds();
  Future<bool> toggleFollowTool(String toolId);

  Future<Set<String>> followedUserIds();
  Future<bool> toggleFollowUser(String userId);

  /// Alerts for the signed-in user, newest first. Empty for a guest — there is
  /// nobody to have alerts about.
  Future<List<AppNotification>> notifications({int limit = 50});
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
}
