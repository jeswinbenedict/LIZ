import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../errors.dart';

/// Storage bucket names (see 0005_storage.sql).
class Buckets {
  const Buckets._();
  static const avatars = 'avatars';
  static const postImages = 'post-images';
}

/// Uploads user images to Supabase Storage. Files live under a per-user folder
/// so RLS lets a user write only within their own prefix; reads are public.
abstract interface class StorageService {
  /// Whether uploads are possible (false in mock mode with no backend).
  bool get available;

  /// Uploads [bytes] to [bucket] and returns the public URL.
  Future<String> uploadImage({
    required String bucket,
    required Uint8List bytes,
    required String ext,
    String contentType = 'image/jpeg',
  });
}

class SupabaseStorageService implements StorageService {
  SupabaseStorageService(this._client, this._auth);
  final SupabaseClient _client;
  final AuthRepository _auth;

  @override
  bool get available => true;

  @override
  Future<String> uploadImage({
    required String bucket,
    required Uint8List bytes,
    required String ext,
    String contentType = 'image/jpeg',
  }) async {
    final uid = _auth.currentUserId;
    if (uid == null) throw const AuthRequiredException();
    final safeExt = ext.replaceAll(RegExp(r'[^a-z0-9]'), '').toLowerCase();
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.$safeExt';
    final path = '$uid/$name';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

/// Mock mode: no backend to upload to.
class MockStorageService implements StorageService {
  @override
  bool get available => false;

  @override
  Future<String> uploadImage({
    required String bucket,
    required Uint8List bytes,
    required String ext,
    String contentType = 'image/jpeg',
  }) async {
    throw const LizException(
        'Image upload needs the live backend (run in Supabase mode).');
  }
}
