import 'json.dart';

/// Something that happened while you were away.
///
/// The database stores the wording in `payload` rather than deriving it in the
/// client, so a notification reads the same however it is delivered — in the
/// list, in a push, or in a digest — and old ones do not silently change their
/// meaning when the app is updated.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.route,
  });

  final String id;

  /// What kind of event this was: `pricing`, `trending`, `comment`, `follow`.
  /// Unknown types still render — the title and body carry the meaning.
  final String type;
  final String title;
  final String body;

  /// Where tapping it should go, e.g. `/tool/<id>`. Null when there is
  /// nowhere useful to send someone.
  final String? route;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final payload = j['payload'];
    final p = payload is Map
        ? payload.cast<String, dynamic>()
        : const <String, dynamic>{};
    final route = asStringOrNull(p['route']);
    return AppNotification(
      id: asString(j['id']),
      type: asString(j['type']),
      title: asString(p['title']),
      body: asString(p['body']),
      route: route == null || route.isEmpty ? null : route,
      read: asBool(j['read']),
      createdAt: asDate(j['created_at']),
    );
  }

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    route: route,
    read: read ?? this.read,
    createdAt: createdAt,
  );
}
