import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models/tool.dart';

/// Tracks which tool IDs the current user has bookmarked. Reloads whenever the
/// signed-in user changes. Toggling rethrows [AuthRequiredException] for guests
/// so the UI can prompt sign-in.
class BookmarkController extends StateNotifier<Set<String>> {
  BookmarkController(this._ref) : super(const {}) {
    _load();
  }
  final Ref _ref;

  Future<void> _load() async {
    final ids = await _ref.read(trackRepositoryProvider).bookmarkedToolIds();
    if (mounted) state = ids;
  }

  Future<void> refresh() => _load();

  bool contains(String toolId) => state.contains(toolId);

  /// Returns the new bookmarked state. May throw [AuthRequiredException].
  Future<bool> toggle(String toolId) async {
    final added = await _ref.read(trackRepositoryProvider).toggleBookmark(toolId);
    state = added ? {...state, toolId} : (state.toSet()..remove(toolId));
    return added;
  }
}

final bookmarkControllerProvider =
    StateNotifierProvider<BookmarkController, Set<String>>((ref) {
  // Rebuild when auth changes so bookmarks reload for the new session.
  ref.watch(currentUserProvider);
  return BookmarkController(ref);
});

class FollowController extends StateNotifier<Set<String>> {
  FollowController(this._ref) : super(const {}) {
    _load();
  }
  final Ref _ref;

  Future<void> _load() async {
    final ids = await _ref.read(trackRepositoryProvider).followedToolIds();
    if (mounted) state = ids;
  }

  bool contains(String toolId) => state.contains(toolId);

  Future<bool> toggle(String toolId) async {
    final added =
        await _ref.read(trackRepositoryProvider).toggleFollowTool(toolId);
    state = added ? {...state, toolId} : (state.toSet()..remove(toolId));
    return added;
  }
}

final followControllerProvider =
    StateNotifierProvider<FollowController, Set<String>>((ref) {
  ref.watch(currentUserProvider);
  return FollowController(ref);
});

/// Tracks which user IDs the current user follows.
class FollowUserController extends StateNotifier<Set<String>> {
  FollowUserController(this._ref) : super(const {}) {
    _load();
  }
  final Ref _ref;

  Future<void> _load() async {
    final ids = await _ref.read(trackRepositoryProvider).followedUserIds();
    if (mounted) state = ids;
  }

  bool contains(String userId) => state.contains(userId);

  Future<bool> toggle(String userId) async {
    final added =
        await _ref.read(trackRepositoryProvider).toggleFollowUser(userId);
    state = added ? {...state, userId} : (state.toSet()..remove(userId));
    return added;
  }
}

final followUserControllerProvider =
    StateNotifierProvider<FollowUserController, Set<String>>((ref) {
  ref.watch(currentUserProvider);
  return FollowUserController(ref);
});

/// Bookmarked tools as full objects (for the Saved screen).
final bookmarkedToolsProvider = FutureProvider<List<Tool>>((ref) async {
  ref.watch(bookmarkControllerProvider); // refresh when the set changes
  return ref.watch(trackRepositoryProvider).bookmarkedTools();
});
