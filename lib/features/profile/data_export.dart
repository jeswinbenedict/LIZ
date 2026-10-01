import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/files/download.dart';
import '../../core/providers.dart';
import '../../shared/models/app_notification.dart';

/// Everything Liz holds about the signed-in person, as one JSON document.
///
/// People could delete their account but not take a copy of what was in it;
/// several privacy laws (GDPR Art. 20 among them) expect both. This gathers
/// what they can see of themselves through the same queries the app uses, so
/// row-level security is what decides what is included — never more than
/// they could already read.
///
/// Usage events are not included: they are keyed to a random browser id, not
/// to the account, and the person cannot read them. The privacy policy says
/// so.
Future<Map<String, dynamic>> collectMyData(Ref ref) async {
  final profile = ref.read(currentUserProvider);
  if (profile == null) throw StateError('Not signed in');
  final track = ref.read(trackRepositoryProvider);
  final community = ref.read(communityRepositoryProvider);

  final saved = await track.bookmarkedTools();
  final followedPeople = await track.followedUserIds();
  final prefs = await track.preferences();
  final reviews = await community.reviewsByUser(profile.id);
  final posts = await community.feed(userId: profile.id, limit: 500);
  final notifications = await track.notifications(limit: 500);

  return {
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'about':
        'Your data from Liz. Usage counts are not included: they are '
        'tied to a random browser id rather than your account.',
    'profile': profile.toJson(),
    'preferences': prefs?.toJson(),
    'saved_tools': [
      for (final t in saved) {'id': t.id, 'name': t.name, 'slug': t.slug},
    ],
    'following_people': followedPeople.toList(),
    'reviews': [for (final r in reviews) r.toJson()],
    'posts': [for (final p in posts.items) p.toJson()],
    'notifications': [for (final n in notifications) _notification(n)],
  };
}

Map<String, dynamic> _notification(AppNotification n) => {
  'type': n.type,
  'title': n.title,
  'body': n.body,
  'read': n.read,
  'created_at': n.createdAt.toIso8601String(),
};

/// Exports and hands the file to the browser. Returns false where there is
/// no browser to save it.
final exportMyDataProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    final data = await collectMyData(ref);
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    return downloadBytes(
      Uint8List.fromList(utf8.encode(text)),
      'liz-data-$stamp.json',
      'application/json',
    );
  };
});
