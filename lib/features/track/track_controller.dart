import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models/tool.dart';

/// A set of ids the signed-in user has marked — bookmarked tools, followed
/// tools, followed people. A toggle changes the set only once the server has
/// agreed, not optimistically.
///
/// Rebuilt whenever the signed-in user changes, so one account's marks never
/// show under another. A Riverpod 3 notifier keeps its instance across a
/// rebuild, so a load still in flight for the previous account is discarded by
/// generation rather than by the instance going away.
abstract class _IdSetController extends Notifier<Set<String>> {
  int _generation = 0;

  Future<Set<String>> fetch();
  Future<bool> write(String id);

  @override
  Set<String> build() {
    ref.watch(currentUserProvider);
    _load();
    return const {};
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final ids = await fetch();
    if (ref.mounted && generation == _generation) state = ids;
  }

  bool contains(String id) => state.contains(id);

  /// Returns the new marked state. May throw [AuthRequiredException] for a
  /// guest, so the UI can prompt sign-in.
  Future<bool> toggle(String id) async {
    final added = await write(id);
    if (!ref.mounted) return added;
    state = added ? {...state, id} : (state.toSet()..remove(id));
    return added;
  }
}

/// Which tool ids the current user has bookmarked.
class BookmarkController extends _IdSetController {
  @override
  Future<Set<String>> fetch() =>
      ref.read(trackRepositoryProvider).bookmarkedToolIds();

  @override
  Future<bool> write(String id) =>
      ref.read(trackRepositoryProvider).toggleBookmark(id);

  Future<void> refresh() => _load();
}

final bookmarkControllerProvider =
    NotifierProvider<BookmarkController, Set<String>>(BookmarkController.new);

/// Which tool ids the current user follows.
class FollowController extends _IdSetController {
  @override
  Future<Set<String>> fetch() =>
      ref.read(trackRepositoryProvider).followedToolIds();

  @override
  Future<bool> write(String id) =>
      ref.read(trackRepositoryProvider).toggleFollowTool(id);
}

final followControllerProvider =
    NotifierProvider<FollowController, Set<String>>(FollowController.new);

/// Which user ids the current user follows.
class FollowUserController extends _IdSetController {
  @override
  Future<Set<String>> fetch() =>
      ref.read(trackRepositoryProvider).followedUserIds();

  @override
  Future<bool> write(String id) =>
      ref.read(trackRepositoryProvider).toggleFollowUser(id);
}

final followUserControllerProvider =
    NotifierProvider<FollowUserController, Set<String>>(
      FollowUserController.new,
    );

/// Bookmarked tools as full objects (for the Saved screen).
final bookmarkedToolsProvider = FutureProvider<List<Tool>>((ref) async {
  ref.watch(bookmarkControllerProvider); // refresh when the set changes
  return ref.watch(trackRepositoryProvider).bookmarkedTools();
});
