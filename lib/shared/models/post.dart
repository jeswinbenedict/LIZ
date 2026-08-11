import 'json.dart';
import 'profile.dart';

class Post {
  const Post({
    required this.id,
    required this.userId,
    this.toolId,
    this.toolName,
    required this.content,
    this.imageUrl,
    required this.likeCount,
    required this.commentCount,
    required this.status,
    required this.createdAt,
    this.author,
    this.likedByMe = false,
  });

  final String id;
  final String userId;
  final String? toolId;
  final String? toolName; // convenience join for display
  final String content;
  final String? imageUrl;
  final int likeCount;
  final int commentCount;
  final String status; // active / hidden / removed
  final DateTime createdAt;
  final Profile? author;
  final bool likedByMe;

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: asString(j['id']),
        userId: asString(j['user_id']),
        toolId: asStringOrNull(j['tool_id']),
        toolName: asStringOrNull(j['tool_name']),
        content: asString(j['content']),
        imageUrl: asStringOrNull(j['image_url']),
        likeCount: asInt(j['like_count']),
        commentCount: asInt(j['comment_count']),
        status: asString(j['status'], 'active'),
        createdAt: asDate(j['created_at']),
        author: j['author'] is Map<String, dynamic>
            ? Profile.fromJson(j['author'] as Map<String, dynamic>)
            : (j['profiles'] is Map<String, dynamic>
                ? Profile.fromJson(j['profiles'] as Map<String, dynamic>)
                : null),
        likedByMe: asBool(j['liked_by_me']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'tool_id': toolId,
        'content': content,
        'image_url': imageUrl,
        'like_count': likeCount,
        'comment_count': commentCount,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
    String? status,
  }) =>
      Post(
        id: id,
        userId: userId,
        toolId: toolId,
        toolName: toolName,
        content: content,
        imageUrl: imageUrl,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        status: status ?? this.status,
        createdAt: createdAt,
        author: author,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}
