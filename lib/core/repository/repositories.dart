import '../../shared/models/app_notification.dart';
import '../../shared/models/category.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/news_item.dart';
import '../../shared/models/paginated.dart';
import '../../shared/models/post.dart';
import '../../shared/models/profile.dart';
import '../../shared/models/review.dart';
import '../../shared/models/tool.dart';
import '../../shared/models/tool_history.dart';
import '../../shared/models/user_prefs.dart';

/// How a tool feed is ordered. `rising` implements the "rising early" idea:
/// high velocity but still low absolute popularity.
/// How a list of tools is ordered.
///
/// `rising` is momentum: measured growth over the last seven days (migration
/// 0037). There used to be a separate "trending" order over all-time totals,
/// but those totals were seeded, not measured, and the two orders were never
/// meaningfully different.
enum ToolSort { rising, newest, topRated }

/// Query parameters for the discover feed.
class ToolQuery {
  const ToolQuery({
    this.sort = ToolSort.rising,
    this.categorySlug,
    this.tag,
    this.search,
    this.limit = 20,
    this.cursor,
    this.includeProse = false,
    this.pricing,
    this.movingOnly = false,
    this.newWithinDays,
    this.categorySlugs,
  });

  final ToolSort sort;

  /// Any of these categories (the For you shelf). Null means no filter.
  final List<String>? categorySlugs;
  final String? categorySlug;
  final String? tag;
  final String? search;
  final int limit;
  final String? cursor;

  /// Show only tools at this price. Null means any.
  final PricingType? pricing;

  /// Only tools with measurable growth this week. The Rising chart sets this
  /// so it shows fewer rows rather than padding itself with tools that are
  /// not moving at all.
  final bool movingOnly;

  /// Only tools Liz first saw within this many days.
  final int? newWithinDays;

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
    pricing: pricing,
    movingOnly: movingOnly,
    newWithinDays: newWithinDays,
    categorySlugs: categorySlugs,
  );
}

/// A tool an article names, as much as a link to it needs.
typedef HeadlineTool = ({String id, String name, String slug});

/// An article and the catalog tools its headline names.
class ToolHeadline {
  const ToolHeadline(this.item, this.tools);
  final NewsItem item;
  final List<HeadlineTool> tools;
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
  Future<List<Tool>> searchTools(String query, {PricingType? pricing});

  /// Tools close to this one by meaning, nearest first. May be empty when
  /// nothing in the catalog is genuinely close — see migration 0023.
  Future<List<Tool>> similarTools(String toolId);

  /// A longer list for "Alternatives to X" and the compare picker: up to
  /// twelve neighbours with a wider similarity window than the strip.
  Future<List<Tool>> alternativeTools(String toolId);

  /// Published articles whose headline names this tool, newest first.
  /// Linked in Postgres as each article arrives (migrations 0052–0053).
  Future<List<NewsItem>> newsForTool(String toolId, {int limit = 5});

  /// The latest published articles that name any tool in the catalog, each
  /// with the tools it names — Discover's "In the news".
  Future<List<ToolHeadline>> toolHeadlines({int limit = 6});

  /// One point per day for the last [days] days, oldest first
  /// (tool_signal_snapshots). History starts on 29 September 2026.
  Future<List<SignalPoint>> signalHistory(String toolId, {int days = 30});

  /// The same for several tools in one request, keyed by tool id.
  Future<Map<String, List<SignalPoint>>> signalHistories(
    List<String> toolIds, {
    int days = 14,
  });

  /// Price changes, newest first (migration 0044).
  Future<List<ToolChange>> toolChanges(String toolId);
}

/// Community: posts, reviews, comments, likes, reports.
abstract interface class CommunityRepository {
  /// One active post, or null if it does not exist or has been hidden.
  Future<Post?> post(String id);

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

/// Something taken off the page, and what it said.
class HiddenItem {
  const HiddenItem({
    required this.targetType,
    required this.targetId,
    required this.preview,
    required this.createdAt,
  });

  final String targetType;
  final String targetId;
  final String preview;
  final DateTime createdAt;
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

  /// The newest articles in every status, for moderation.
  Future<List<NewsItem>> allNews();

  /// Hide or restore an article. The feed is scraped from eight sources and
  /// occasionally pulls in something that should not be on the page; until now
  /// the only way to take it down was the database console.
  Future<void> setNewsStatus(String newsId, PublishStatus status);

  /// Hide or restore anything a reader can report: a post, a review, a
  /// comment or a tool.
  ///
  /// Replaces a post-only version. The moderation queue could dismiss a report
  /// about a review but had no way to act on it — and reviews are shown on
  /// every tool page, so a moderator could not take a bad one down.
  Future<void> setContentHidden(
    String targetType,
    String targetId, {
    required bool hidden,
  });

  /// Community content currently hidden, newest first.
  ///
  /// The report trigger hides things on its own once enough established
  /// accounts agree, and nothing used to show what it had taken down. This is
  /// where a moderator confirms that or puts it back.
  Future<List<HiddenItem>> hiddenContent();
  Future<List<ReportEntry>> openReports();
  Future<void> resolveReport(String reportId);

  /// Whether the parts of Liz that run unattended are still working.
  Future<List<HealthSignal>> health();

  /// Whether the scheduled jobs ran at all. Freshness says the work landed;
  /// this says the attempt was made, which is how "broken" is told apart from
  /// "nothing new to fetch".
  Future<List<JobRun>> recentJobRuns({int limit = 20});

  /// What people did on Liz over the last [days], counted from the event log
  /// (migration 0037): visitors, views, website visits, saves, searches,
  /// sign-ups, and visitors who came back on another day.
  Future<Map<String, int>> usageSummary({int days = 7});

  /// Distinct client faults, most recent first.
  Future<List<ErrorGroup>> recentErrors({int limit = 20});
}

/// Track / follow: saved tools (which are also what alerts watch) and the
/// people someone follows.
abstract interface class TrackRepository {
  Future<Set<String>> bookmarkedToolIds();
  Future<List<Tool>> bookmarkedTools();
  Future<bool> toggleBookmark(String toolId);

  Future<Set<String>> followedUserIds();
  Future<bool> toggleFollowUser(String userId);

  /// Alerts for the signed-in user, newest first. Empty for a guest — there is
  /// nobody to have alerts about.
  Future<List<AppNotification>> notifications({int limit = 50});
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();

  /// The signed-in user's private preferences, or null when they have set
  /// none (or nobody is signed in).
  Future<UserPrefs?> preferences();

  /// Saves the signed-in user's preferences. Requires a session.
  Future<void> savePreferences(UserPrefs prefs);
}
