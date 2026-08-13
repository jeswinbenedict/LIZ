import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/models/category.dart';
import '../shared/models/profile.dart';
import 'auth/auth_repository.dart';
// Re-export so widgets can import a single file for query types.
export 'repository/repositories.dart' show ToolQuery, ToolSort;
import 'auth/mock_auth_repository.dart';
import 'auth/supabase_auth_repository.dart';
import 'config/env.dart';
import 'storage/storage_service.dart';
import 'repository/mock_repositories.dart';
import 'repository/repositories.dart';
import 'repository/supabase_repositories.dart';

/// The initialized Supabase client, or null in mock mode. Set once at startup
/// (see main.dart) via an override so the rest of the tree can read it.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return Env.useSupabase ? Supabase.instance.client : null;
});

/// Single source of truth for whether we're on the live backend.
final isLiveBackendProvider = Provider<bool>((ref) => Env.useSupabase);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    final repo = SupabaseAuthRepository(client);
    ref.onDispose(repo.dispose);
    return repo;
  }
  return MockAuthRepository();
});

/// Reactive current profile. Null = browsing as guest.
final currentProfileProvider = StreamProvider<Profile?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return auth.authStateChanges();
}, dependencies: const []);

/// Convenience: synchronous current profile (may briefly be null before the
/// stream emits). Prefer [currentProfileProvider] where async state matters.
final currentUserProvider = Provider<Profile?>((ref) {
  return ref.watch(currentProfileProvider).valueOrNull ??
      ref.watch(authRepositoryProvider).currentProfile;
});

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// Shared in-memory store for mock mode (ignored on the live backend).
final _mockStoreProvider = Provider<MockStore>((ref) => MockStore());

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseContentRepository(client);
  return MockContentRepository(ref.watch(_mockStoreProvider));
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authRepositoryProvider);
  if (client != null) return SupabaseCommunityRepository(client, auth);
  return MockCommunityRepository(ref.watch(_mockStoreProvider), auth);
});

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authRepositoryProvider);
  if (client != null) return SupabaseTrackRepository(client, auth);
  return MockTrackRepository(ref.watch(_mockStoreProvider), auth);
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseAdminRepository(client);
  return MockAdminRepository(ref.watch(_mockStoreProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authRepositoryProvider);
  if (client != null) return SupabaseStorageService(client, auth);
  return MockStorageService();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(contentRepositoryProvider).categories();
});
