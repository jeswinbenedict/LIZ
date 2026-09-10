import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/app_notification.dart';
import '../../shared/models/json.dart';
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
import '../errors.dart';
import 'repositories.dart';

int _decodeCursor(String? cursor) =>
    cursor == null ? 0 : int.tryParse(cursor) ?? 0;

String? _nextCursor(int offset, int limit, int received) =>
    received < limit ? null : '${offset + limit}';

/// Live discovery content backed by Supabase's auto REST API + RLS.
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(this._client);
  final SupabaseClient _client;

  static const _toolCols =
      'id,name,slug,tagline,description,ai_summary,website_url,logo_url,'
      'category,tags,platforms,pricing_type,price_note,source,source_url,'
      'launched_at,trend_score,view_count,save_count,avg_rating,rating_count,'
      'status,created_at,trend_rank';

  /// Everything a feed card draws, and nothing more. Dropping the description
  /// and the AI summary halves a page of the grid on the wire, and the model
  /// tolerates their absence — the tool page fetches the full row anyway.
  static const _toolCardCols =
      'id,name,slug,tagline,website_url,logo_url,category,tags,platforms,'
      'pricing_type,price_note,launched_at,trend_score,view_count,save_count,'
      'avg_rating,rating_count,status,created_at,trend_rank';

  @override
  Future<List<Category>> categories() async {
    final rows = await _client.from('categories').select().order('name');
    return (rows as List).map((e) => Category.fromJson(e)).toList();
  }

  @override
  Future<Paginated<Tool>> tools(ToolQuery q) async {
    final offset = _decodeCursor(q.cursor);
    final cols = q.includeProse ? _toolCols : _toolCardCols;
    var query = _client.from('tools').select(cols).eq('status', 'published');

    if (q.categorySlug != null) query = query.eq('category', q.categorySlug!);
    if (q.pricing != null) {
      query = query.eq('pricing_type', q.pricing!.name);
    }
    if (q.tag != null) query = query.contains('tags', [q.tag!]);
    if (q.search != null && q.search!.trim().isNotEmpty) {
      final s = q.search!.replaceAll(',', ' ');
      query = query.or('name.ilike.%$s%,tagline.ilike.%$s%');
    }

    final ordered = switch (q.sort) {
      ToolSort.trending => query.order('trend_score', ascending: false),
      ToolSort.newest => query.order('created_at', ascending: false),
      // "Rising early" is served by a computed view/RPC in production; the
      // client falls back to trend_score ordering here.
      ToolSort.rising =>
        query
            .order('trend_score', ascending: false)
            .order('save_count', ascending: true),
      ToolSort.topRated =>
        query
            .order('avg_rating', ascending: false)
            .order('rating_count', ascending: false),
    };

    final rows = await ordered.range(offset, offset + q.limit - 1);
    final items = (rows as List).map((e) => Tool.fromJson(e)).toList();
    return Paginated(
      items: items,
      cursor: _nextCursor(offset, q.limit, items.length),
    );
  }

  @override
  Future<Tool?> toolById(String id) async {
    final row = await _client
        .from('tools')
        .select(_toolCols)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Tool.fromJson(row);
  }

  @override
  Future<Tool?> toolBySlug(String slug) async {
    final row = await _client
        .from('tools')
        .select(_toolCols)
        .eq('slug', slug)
        .maybeSingle();
    return row == null ? null : Tool.fromJson(row);
  }

  @override
  Future<List<Tool>> compareTools(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('tools')
        .select(_toolCols)
        .inFilter('id', ids);
    return (rows as List).map((e) => Tool.fromJson(e)).toList();
  }

  @override
  Future<Paginated<NewsItem>> news({int limit = 20, String? cursor}) async {
    final offset = _decodeCursor(cursor);
    final rows = await _client
        .from('news')
        .select()
        .eq('status', 'published')
        .order('published_at', ascending: false)
        .range(offset, offset + limit - 1);
    final items = (rows as List).map((e) => NewsItem.fromJson(e)).toList();
    return Paginated(
      items: items,
      cursor: _nextCursor(offset, limit, items.length),
    );
  }

  @override
  Future<List<Tool>> searchTools(String query) async {
    final s = query.trim();
    if (s.isEmpty) return [];
    final rows = await _client
        .from('tools')
        .select(_toolCols)
        .eq('status', 'published')
        .or('name.ilike.%$s%,tagline.ilike.%$s%,description.ilike.%$s%')
        .limit(30);
    return (rows as List).map((e) => Tool.fromJson(e)).toList();
  }

  @override
  Future<List<Tool>> similarTools(String toolId) async {
    // The comparison runs in Postgres against the vectors already stored for
    // Ask Liz: no model call, no embedding sent over the wire, one index hit.
    final rows = await _client.rpc<dynamic>(
      'similar_tools',
      params: {'source_id': toolId},
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Tool.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

class SupabaseCommunityRepository implements CommunityRepository {
  SupabaseCommunityRepository(this._client, this._auth);
  final SupabaseClient _client;
  final AuthRepository _auth;

  String _requireUser() {
    final id = _auth.currentUserId;
    if (id == null) throw const AuthRequiredException();
    return id;
  }

  static const _postCols =
      '*, profiles:user_id(id,username,display_name,avatar_url,role,created_at)';
  static const _reviewCols =
      '*, profiles:user_id(id,username,display_name,avatar_url,role,created_at)';

  @override
  Future<Paginated<Post>> feed({
    bool trending = false,
    String? toolId,
    String? userId,
    int limit = 20,
    String? cursor,
  }) async {
    final offset = _decodeCursor(cursor);
    var query = _client.from('posts').select(_postCols).eq('status', 'active');
    if (toolId != null) query = query.eq('tool_id', toolId);
    if (userId != null) query = query.eq('user_id', userId);
    final ordered = trending
        ? query.order('like_count', ascending: false)
        : query.order('created_at', ascending: false);
    final rows = await ordered.range(offset, offset + limit - 1);
    final items = (rows as List)
        .map((e) => Post.fromJson({...e, 'author': e['profiles']}))
        .toList();
    return Paginated(
      items: items,
      cursor: _nextCursor(offset, limit, items.length),
    );
  }

  @override
  Future<Post> createPost({
    required String content,
    String? toolId,
    String? imageUrl,
  }) async {
    final uid = _requireUser();
    final row = await _client
        .from('posts')
        .insert({
          'user_id': uid,
          'tool_id': toolId,
          'content': content,
          'image_url': imageUrl,
          'status': 'active',
        })
        .select(_postCols)
        .single();
    return Post.fromJson({...row, 'author': row['profiles']});
  }

  @override
  Future<List<Comment>> comments(String postId) async {
    final rows = await _client
        .from('comments')
        .select(
          '*, profiles:user_id(id,username,display_name,avatar_url,role,created_at)',
        )
        .eq('post_id', postId)
        .eq('status', 'active')
        .order('created_at');
    return (rows as List)
        .map((e) => Comment.fromJson({...e, 'author': e['profiles']}))
        .toList();
  }

  @override
  Future<Comment> addComment(String postId, String body) async {
    final uid = _requireUser();
    final row = await _client
        .from('comments')
        .insert({
          'post_id': postId,
          'user_id': uid,
          'body': body,
          'status': 'active',
        })
        .select(
          '*, profiles:user_id(id,username,display_name,avatar_url,role,created_at)',
        )
        .single();
    return Comment.fromJson({...row, 'author': row['profiles']});
  }

  @override
  Future<List<Review>> reviewsForTool(String toolId) async {
    final rows = await _client
        .from('reviews')
        .select(_reviewCols)
        .eq('tool_id', toolId)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Review.fromJson({...e, 'author': e['profiles']}))
        .toList();
  }

  @override
  Future<List<Review>> reviewsByUser(String userId) async {
    final rows = await _client
        .from('reviews')
        .select(_reviewCols)
        .eq('user_id', userId)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Review.fromJson({...e, 'author': e['profiles']}))
        .toList();
  }

  @override
  Future<Profile?> profileById(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  @override
  Future<Review> upsertReview({
    required String toolId,
    required int rating,
    required String body,
  }) async {
    final uid = _requireUser();
    final row = await _client
        .from('reviews')
        .upsert({
          'user_id': uid,
          'tool_id': toolId,
          'rating': rating.clamp(1, 5),
          'body': body,
          'status': 'active',
        }, onConflict: 'user_id,tool_id')
        .select(_reviewCols)
        .single();
    return Review.fromJson({...row, 'author': row['profiles']});
  }

  @override
  Future<bool> toggleLike({
    required String targetType,
    required String targetId,
  }) async {
    final uid = _requireUser();
    final existing = await _client
        .from('likes')
        .select('id')
        .eq('user_id', uid)
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .maybeSingle();
    if (existing != null) {
      await _client.from('likes').delete().eq('id', existing['id']);
      return false;
    }
    await _client.from('likes').insert({
      'user_id': uid,
      'target_type': targetType,
      'target_id': targetId,
    });
    return true;
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    final uid = _requireUser();
    // Insert directly (RLS allows a user to file their own report); the
    // handle_report trigger applies the auto-hide threshold server-side. This
    // keeps reporting working without any Edge Function deployed.
    await _client.from('reports').insert({
      'reporter_id': uid,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
    });
  }
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Tool>> allTools() async {
    final rows = await _client
        .from('tools')
        .select(SupabaseContentRepository._toolCols)
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List).map((e) => Tool.fromJson(e)).toList();
  }

  @override
  Future<void> setToolStatus(String toolId, PublishStatus status) async {
    await _client
        .from('tools')
        .update({'status': status.value})
        .eq('id', toolId);
  }

  @override
  Future<List<NewsItem>> allNews() async {
    final rows = await _client
        .from('news')
        .select()
        .order('published_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => NewsItem.fromJson(e)).toList();
  }

  @override
  Future<List<Post>> flaggedPosts() async {
    final rows = await _client
        .from('posts')
        .select()
        .inFilter('status', ['hidden', 'active'])
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => Post.fromJson(e)).toList();
  }

  @override
  Future<void> setPostStatus(String postId, String status) async {
    await _client.from('posts').update({'status': status}).eq('id', postId);
  }

  @override
  Future<List<ReportEntry>> openReports() async {
    final rows = await _client
        .from('reports')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false);
    return (rows as List)
        .map(
          (e) => ReportEntry(
            id: e['id'].toString(),
            targetType: e['target_type'].toString(),
            targetId: e['target_id'].toString(),
            reason: (e['reason'] ?? '').toString(),
            preview: '',
            createdAt:
                DateTime.tryParse(e['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<void> resolveReport(String reportId) async {
    await _client
        .from('reports')
        .update({'status': 'resolved'})
        .eq('id', reportId);
  }

  @override
  Future<List<HealthSignal>> health() async {
    final rows = await _client.rpc<dynamic>('system_health');
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((e) {
      return HealthSignal(
        signal: asString(e['signal']),
        status: asString(e['status'], 'ok'),
        value: asDouble(e['value']),
        detail: asString(e['detail']),
      );
    }).toList();
  }

  @override
  Future<List<JobRun>> recentJobRuns({int limit = 20}) async {
    final rows = await _client.rpc<dynamic>(
      'recent_job_runs',
      params: {'limit_count': limit},
    );
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((e) {
      return JobRun(
        jobName: asString(e['job_name']),
        status: asString(e['status']),
        startedAt: asDate(e['started_at']),
        durationSeconds: asDouble(e['duration_s']),
        message: asString(e['message']),
      );
    }).toList();
  }

  @override
  Future<List<ErrorGroup>> recentErrors({int limit = 20}) async {
    final rows = await _client
        .from('error_summary')
        .select()
        .order('last_seen', ascending: false)
        .limit(limit);
    return (rows as List).whereType<Map>().map((e) {
      final route = asStringOrNull(e['latest_route']);
      return ErrorGroup(
        fingerprint: asString(e['fingerprint']),
        occurrences: asInt(e['occurrences']),
        affectedUsers: asInt(e['affected_users']),
        lastSeen: asDate(e['last_seen']),
        message: asString(e['latest_message']),
        route: route == null || route.isEmpty ? null : route,
      );
    }).toList();
  }
}

class SupabaseTrackRepository implements TrackRepository {
  SupabaseTrackRepository(this._client, this._auth);
  final SupabaseClient _client;
  final AuthRepository _auth;

  String _requireUser() {
    final id = _auth.currentUserId;
    if (id == null) throw const AuthRequiredException();
    return id;
  }

  @override
  Future<Set<String>> bookmarkedToolIds() async {
    final uid = _auth.currentUserId;
    if (uid == null) return {};
    final rows = await _client
        .from('bookmarks')
        .select('tool_id')
        .eq('user_id', uid);
    return (rows as List).map((e) => e['tool_id'].toString()).toSet();
  }

  @override
  Future<List<Tool>> bookmarkedTools() async {
    final uid = _auth.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('bookmarks')
        .select('tools(${SupabaseContentRepository._toolCardCols})')
        .eq('user_id', uid);
    return (rows as List)
        .where((e) => e['tools'] != null)
        .map((e) => Tool.fromJson(e['tools']))
        .toList();
  }

  @override
  Future<bool> toggleBookmark(String toolId) async {
    final uid = _requireUser();
    final existing = await _client
        .from('bookmarks')
        .select('id')
        .eq('user_id', uid)
        .eq('tool_id', toolId)
        .maybeSingle();
    if (existing != null) {
      await _client.from('bookmarks').delete().eq('id', existing['id']);
      return false;
    }
    await _client.from('bookmarks').insert({'user_id': uid, 'tool_id': toolId});
    return true;
  }

  @override
  Future<List<Collection>> collections() async {
    final uid = _auth.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('collections')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => Collection.fromJson(e)).toList();
  }

  @override
  Future<Collection> createCollection(String name) async {
    final uid = _requireUser();
    final row = await _client
        .from('collections')
        .insert({'user_id': uid, 'name': name})
        .select()
        .single();
    return Collection.fromJson(row);
  }

  @override
  Future<Set<String>> followedToolIds() => _followedIds('tool');

  @override
  Future<bool> toggleFollowTool(String toolId) => _toggleFollow('tool', toolId);

  @override
  Future<Set<String>> followedUserIds() => _followedIds('user');

  @override
  Future<bool> toggleFollowUser(String userId) => _toggleFollow('user', userId);

  // The follows table keys on follower_id (not user_id) — see 0001_schema.sql.
  Future<Set<String>> _followedIds(String targetType) async {
    final uid = _auth.currentUserId;
    if (uid == null) return {};
    final rows = await _client
        .from('follows')
        .select('target_id')
        .eq('follower_id', uid)
        .eq('target_type', targetType);
    return (rows as List).map((e) => e['target_id'].toString()).toSet();
  }

  Future<bool> _toggleFollow(String targetType, String targetId) async {
    final uid = _requireUser();
    final existing = await _client
        .from('follows')
        .select('id')
        .eq('follower_id', uid)
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .maybeSingle();
    if (existing != null) {
      await _client.from('follows').delete().eq('id', existing['id']);
      return false;
    }
    await _client.from('follows').insert({
      'follower_id': uid,
      'target_type': targetType,
      'target_id': targetId,
    });
    return true;
  }

  @override
  Future<List<AppNotification>> notifications({int limit = 50}) async {
    final uid = _auth.currentUserId;
    if (uid == null) return const [];
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final uid = _auth.currentUserId;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('id', id)
        .eq('user_id', uid);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final uid = _auth.currentUserId;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', uid)
        .eq('read', false);
  }
}
