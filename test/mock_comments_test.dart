import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/data/mock_data.dart';
import 'package:liz/core/repository/mock_repositories.dart';

/// The demo feed said "12 comments" under a post whose page said "No comments
/// yet". Every count now comes from the thread it counts.
void main() {
  test('each demo post has the thread its count promises', () async {
    final store = MockStore();
    for (final post in MockData.posts) {
      final thread = store.commentsByPost[post.id] ?? const [];
      expect(thread.length, post.commentCount, reason: post.id);
      for (final c in thread) {
        expect(c.postId, post.id);
        expect(c.createdAt.isAfter(post.createdAt), isTrue, reason: c.id);
      }
    }
    expect(MockData.posts.any((p) => p.commentCount > 0), isTrue);
  });
}
