import 'json.dart';
import 'profile.dart';

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.status,
    required this.createdAt,
    this.author,
  });

  final String id;
  final String postId;
  final String userId;
  final String body;
  final String status;
  final DateTime createdAt;
  final Profile? author;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: asString(j['id']),
        postId: asString(j['post_id']),
        userId: asString(j['user_id']),
        body: asString(j['body']),
        status: asString(j['status'], 'active'),
        createdAt: asDate(j['created_at']),
        author: j['author'] is Map<String, dynamic>
            ? Profile.fromJson(j['author'] as Map<String, dynamic>)
            : (j['profiles'] is Map<String, dynamic>
                ? Profile.fromJson(j['profiles'] as Map<String, dynamic>)
                : null),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'post_id': postId,
        'user_id': userId,
        'body': body,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
