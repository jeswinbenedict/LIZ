import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/auth/mock_auth_repository.dart';
import 'package:liz/core/repository/mock_repositories.dart';
import 'package:liz/shared/models/post.dart';

/// A post opened from a link used to be found by reading the newest 100 posts
/// and looking through them, so a link to anything older opened as "not
/// found". It is asked for by id now.

void main() {
  Post post(String id, DateTime at, {String status = 'active'}) => Post(
    id: id,
    userId: 'u-maya',
    content: 'A post',
    likeCount: 0,
    commentCount: 0,
    status: status,
    createdAt: at,
  );

  MockCommunityRepository repoWith(int newer) {
    final store = MockStore();
    // The oldest post, then [newer] posts after it.
    final oldest = post('oldest', DateTime(2020));
    store.posts
      ..clear()
      ..add(oldest)
      ..addAll([
        for (var i = 0; i < newer; i++)
          post('p-new-$i', DateTime(2026, 1, 1, 0, i)),
      ]);
    return MockCommunityRepository(store, MockAuthRepository());
  }

  test('a post older than the newest hundred is still found', () async {
    final repo = repoWith(150);
    expect((await repo.post('oldest'))?.id, 'oldest');

    final newestHundred = await repo.feed(limit: 100);
    expect(
      newestHundred.items.any((p) => p.id == 'oldest'),
      isFalse,
      reason: 'the old lookup would have missed it',
    );
  });

  test('a missing or hidden post is null, not an error', () async {
    final store = MockStore();
    store.posts.add(post('gone', DateTime(2026), status: 'hidden'));
    final repo = MockCommunityRepository(store, MockAuthRepository());

    expect(await repo.post('no-such-post'), isNull);
    expect(await repo.post('gone'), isNull);
  });
}
