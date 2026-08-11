import 'json.dart';

enum UserRole {
  user,
  moderator,
  admin;

  static UserRole parse(String? v) => switch (v) {
        'admin' => UserRole.admin,
        'moderator' => UserRole.moderator,
        _ => UserRole.user,
      };

  bool get canModerate => this == UserRole.moderator || this == UserRole.admin;
}

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.role = UserRole.user,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final UserRole role;
  final DateTime createdAt;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: asString(j['id']),
        username: asString(j['username']),
        displayName: asString(j['display_name'], asString(j['username'])),
        avatarUrl: asStringOrNull(j['avatar_url']),
        bio: asStringOrNull(j['bio']),
        role: UserRole.parse(asStringOrNull(j['role'])),
        createdAt: asDate(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'bio': bio,
        'role': role.name,
        'created_at': createdAt.toIso8601String(),
      };
}
