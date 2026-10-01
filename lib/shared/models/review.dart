import 'json.dart';
import 'profile.dart';

class Review {
  const Review({
    required this.id,
    required this.userId,
    required this.toolId,
    required this.rating,
    required this.body,
    required this.status,
    required this.createdAt,
    this.author,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  final String id;
  final String userId;
  final String toolId;
  final int rating; // 1..5
  final String body;
  final String status; // active / hidden
  final DateTime createdAt;

  /// Optional joined author (present on reads that expand the relation).
  final Profile? author;
  final int likeCount;
  final bool likedByMe;

  factory Review.fromJson(Map<String, dynamic> j) => Review(
    id: asString(j['id']),
    userId: asString(j['user_id']),
    toolId: asString(j['tool_id']),
    rating: asInt(j['rating']).clamp(1, 5),
    body: asString(j['body']),
    status: asString(j['status'], 'active'),
    createdAt: asDate(j['created_at']),
    author: j['author'] is Map<String, dynamic>
        ? Profile.fromJson(j['author'] as Map<String, dynamic>)
        : (j['profiles'] is Map<String, dynamic>
              ? Profile.fromJson(j['profiles'] as Map<String, dynamic>)
              : null),
    likeCount: asInt(j['like_count']),
    likedByMe: asBool(j['liked_by_me']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'tool_id': toolId,
    'rating': rating,
    'body': body,
    'status': status,
    'created_at': createdAt.toIso8601String(),
  };

  Review copyWith({int? likeCount, bool? likedByMe, String? status}) => Review(
    id: id,
    userId: userId,
    toolId: toolId,
    rating: rating,
    body: body,
    status: status ?? this.status,
    createdAt: createdAt,
    author: author,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
  );
}
