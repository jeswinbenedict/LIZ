import 'json.dart';

class Collection {
  const Collection({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    this.toolCount = 0,
  });

  final String id;
  final String userId;
  final String name;
  final DateTime createdAt;
  final int toolCount;

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: asString(j['id']),
        userId: asString(j['user_id']),
        name: asString(j['name']),
        createdAt: asDate(j['created_at']),
        toolCount: asInt(j['tool_count']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'created_at': createdAt.toIso8601String(),
      };
}
