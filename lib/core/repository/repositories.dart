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
    this.pricing,
  });

  final ToolSort sort;
  final String? categorySlug;
  final String? tag;
  final String? search;
  final int limit;
  final String? cursor;

  /// Show only tools at this price. Null means any.
  final PricingType? pricing;

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

  /// Tools close to this one by meaning, nearest first. May be empty when
  /// nothing in the catalog is genuinely close — see migration 0023.
  Future<List<Tool>> similarTools(String toolId);
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

/// One measured signal about whether Liz is working.
class HealthSignal {
  const HealthSignal({
    required this.signal,
    required this.status,
    required this.value,
    required this.detail,
  });

  final String signal;

  /// 'ok', 'warn' or 'fail'. Only 'fail' wakes anyone.
  final String status;
  final double value;
  final String detail;

  /// The signal name as a person would read it.
  String get label => signal
      .replaceAll('_pct', ' %')
      .replaceAll('_hours', ' (hours)')
      .replaceAll('_24h', ' (24h)')
      .replaceAll('_', ' ');
}

/// One run of a scheduled job, as pg_cron recorded it.
class JobRun {
  const JobRun({
    required this.jobName,
    required this.status,
    required this.startedAt,
    required this.durationSeconds,
    required this.message,
  });

  final String jobName;
  final String status;
  final DateTime startedAt;
  final double durationSeconds;
  final String message;
}

/// A distinct client fault, with how often it has happened.
class ErrorGroup {
  const ErrorGroup({
    required this.fingerprint,
    required this.occurrences,
    required this.affectedUsers,
    required this.lastSeen,
    required this.message,
    this.route,
  });

  final String fingerprint;
  final int occurrences;
  final int affectedUsers;
  final DateTime lastSeen;
  final String message;
  final String? route;
}

/// What slice of the catalog an admin is looking at.
class AdminToolQuery {
  const AdminToolQuery({
    this.status,
    this.search,
    this.limit = 50,
    this.offset = 0,
  });

  /// Null means every status.
  final PublishStatus? status;
  final String? search;
  final int limit;
  final int offset;

  AdminToolQuery copyWith({
    PublishStatus? status,
    bool clearStatus = false,
    String? search,
    int? offset,
  }) => AdminToolQuery(
    status: clearStatus ? null : (status ?? this.status),
    search: search ?? this.search,
    limit: limit,
    offset: offset ?? this.offset,
  );

  @override
  bool operator ==(Object other) =>
      other is AdminToolQuery &&
      other.status == status &&
      other.search == search &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(status, search, limit, offset);
}

/// Admin / moderation surface (role-gated by RLS in production).
abstract interface class AdminRepository {
  /// A page of the catalog, filtered and searchable.
  ///
  /// Replaces a flat "newest 200", which could not reach a 653-row catalog at
  /// all — the pending queue it was meant to drain sat entirely outside it.
  Future<Paginated<Tool>> adminTools(AdminToolQuery query);

  /// Publish or hide many tools at once. Reviewing a backlog one popup menu at
  /// a time is why the backlog existed.
  Future<void> setToolStatuses(List<String> toolIds, PublishStatus status);

  Future<void> setToolStatus(String toolId, PublishStatus status);
  Future<List<NewsItem>> allNews();
  Future<List<Post>> flaggedPosts();
  Future<void> setPostStatus(String postId, String status);
  Future<List<ReportEntry>> openReports();
  Future<void> resolveReport(String reportId);

  /// Whether the parts of Liz that run unattended are still working.
  Future<List<HealthSignal>> health();

  /// Whether the scheduled jobs ran at all. Freshness says the work landed;
  /// this says the attempt was made, which is how "broken" is told apart from
  /// "nothing new to fetch".
  Future<List<JobRun>> recentJobRuns({int limit = 20});

  /// Distinct client faults, most recent first.
  Future<List<ErrorGroup>> recentErrors({int limit = 20});
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
