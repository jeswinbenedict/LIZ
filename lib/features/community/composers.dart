import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/storage/storage_service.dart';
import '../../shared/widgets/liz_sheet.dart';
import '../../shared/widgets/rating_stars.dart';
import '../auth/guard.dart';
import 'community_controller.dart';

String _mimeFor(String ext) {
  switch (ext.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    default:
      return 'image/jpeg';
  }
}

/// Bottom sheet to write / edit a review for a tool (one per user per tool).
Future<void> showReviewComposer(
  BuildContext context,
  WidgetRef ref, {
  required String toolId,
  required String toolName,
  int initialRating = 0,
  String initialBody = '',
}) async {
  await showLizSheet<void>(
    context,
    builder: (ctx) => _ReviewComposer(
      toolId: toolId,
      toolName: toolName,
      initialRating: initialRating,
      initialBody: initialBody,
    ),
  );
}

class _ReviewComposer extends ConsumerStatefulWidget {
  const _ReviewComposer({
    required this.toolId,
    required this.toolName,
    required this.initialRating,
    required this.initialBody,
  });
  final String toolId;
  final String toolName;
  final int initialRating;
  final String initialBody;

  @override
  ConsumerState<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends ConsumerState<_ReviewComposer> {
  late int _rating = widget.initialRating;
  late final TextEditingController _body = TextEditingController(
    text: widget.initialBody,
  );
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    await runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to leave a review.',
      action: () => ref
          .read(communityActionsProvider)
          .upsertReview(
            toolId: widget.toolId,
            rating: _rating,
            body: _body.text.trim(),
          ),
      onDone: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    const words = ['Tap a star', 'Poor', 'Fair', 'Good', 'Very good', 'Great'];
    return LizSheet(
      title: widget.initialRating == 0
          ? 'Review ${widget.toolName}'
          : 'Edit your review',
      subtitle:
          'Your rating and a few words for the next person deciding. One '
          'review per tool; you can change it later.',
      actions: [
        OutlinedButton(
          style: LizSheetButtons.outlined,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: LizSheetButtons.filled,
          onPressed: _rating == 0 || _busy ? null : _post,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Post review'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your rating',
            style: LizText.subhead.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-6, 0),
                child: RatingInput(
                  value: _rating,
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                words[_rating.clamp(0, 5)],
                style: LizText.callout.copyWith(
                  color: _rating == 0 ? p.textSecondary : p.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Your review (optional)',
              hintText: 'What worked, and what didn’t?',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to create a community post, optionally linked to a tool.
Future<void> showPostComposer(
  BuildContext context,
  WidgetRef ref, {
  String? toolId,
  String? toolName,
}) async {
  await showLizSheet<void>(
    context,
    builder: (ctx) => _PostComposer(toolId: toolId, toolName: toolName),
  );
}

class _PostComposer extends ConsumerStatefulWidget {
  const _PostComposer({this.toolId, this.toolName});
  final String? toolId;
  final String? toolName;

  @override
  ConsumerState<_PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends ConsumerState<_PostComposer> {
  final _content = TextEditingController();
  bool _busy = false;
  Uint8List? _imageBytes;
  String _imageExt = 'jpg';

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (!ref.read(storageServiceProvider).available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload needs the live backend.')),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageExt = picked.name.split('.').last.toLowerCase();
    });
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    await runGuardedAction(
      context,
      ref: ref,
      prompt: 'Sign in to post.',
      action: () async {
        String? imageUrl;
        final bytes = _imageBytes;
        if (bytes != null) {
          imageUrl = await ref
              .read(storageServiceProvider)
              .uploadImage(
                bucket: Buckets.postImages,
                bytes: bytes,
                ext: _imageExt,
                contentType: _mimeFor(_imageExt),
              );
        }
        await ref
            .read(communityActionsProvider)
            .createPost(
              content: _content.text.trim(),
              toolId: widget.toolId,
              imageUrl: imageUrl,
            );
      },
      onDone: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return LizSheet(
      title: 'New post',
      subtitle: widget.toolName != null
          ? 'Linked to ${widget.toolName}. Everyone on Liz can read it.'
          : 'A find, a question, a comparison. Everyone on Liz can read it.',
      actions: [
        OutlinedButton(
          style: LizSheetButtons.outlined,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: LizSheetButtons.filled,
          onPressed: _content.text.trim().isEmpty || _busy ? null : _post,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Post'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _content,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'What did you discover?',
            ),
          ),
          const SizedBox(height: 8),
          if (_imageBytes != null)
            Stack(
              children: [
                ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(LizRadius.md),
                  child: Image.memory(
                    _imageBytes!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    semanticLabel: 'Selected image',
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove image',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _imageBytes = null),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textSecondary,
                ),
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Add an image'),
              ),
            ),
        ],
      ),
    );
  }
}
