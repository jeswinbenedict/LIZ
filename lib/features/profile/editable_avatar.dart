import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/storage/storage_service.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/user_avatar.dart';

/// The signed-in user's avatar with a tap-to-change photo affordance.
/// Uploads to the `avatars` bucket and updates their profile.
class EditableAvatar extends ConsumerStatefulWidget {
  const EditableAvatar({super.key, required this.profile, this.radius = 34});
  final Profile profile;
  final double radius;

  @override
  ConsumerState<EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends ConsumerState<EditableAvatar> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _change() async {
    final storage = ref.read(storageServiceProvider);
    if (!storage.available) {
      _toast('Avatar upload needs the live backend.');
      return;
    }
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final url = await storage.uploadImage(
        bucket: Buckets.avatars,
        bytes: bytes,
        ext: ext,
        contentType: ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg',
      );
      await ref.read(authRepositoryProvider).updateProfile(avatarUrl: url);
      _toast('Photo updated');
    } catch (_) {
      _toast('Couldn\'t update photo.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _busy ? null : _change,
      child: Stack(
        children: [
          UserAvatar(profile: widget.profile, radius: widget.radius),
          if (_busy)
            Positioned.fill(
              child: CircleAvatar(
                radius: widget.radius,
                backgroundColor: Colors.black.withValues(alpha: 0.4),
                child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: const Icon(Icons.photo_camera,
                  size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
