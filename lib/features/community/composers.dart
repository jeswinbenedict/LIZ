import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/widgets/rating_stars.dart';
import '../auth/guard.dart';
import 'community_controller.dart';

/// Bottom sheet to write / edit a review for a tool (one per user per tool).
Future<void> showReviewComposer(
  BuildContext context,
  WidgetRef ref, {
  required String toolId,
  required String toolName,
  int initialRating = 0,
  String initialBody = '',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _ReviewComposer(
        toolId: toolId,
        toolName: toolName,
        initialRating: initialRating,
        initialBody: initialBody,
      ),
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
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody);
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LizSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rate ${widget.toolName}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Center(
            child: RatingInput(
              value: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Share what worked (or didn\'t)…',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _rating == 0 || _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await runGuardedAction(
                        context,
                        prompt: 'Sign in to leave a review.',
                        action: () => ref.read(communityActionsProvider).upsertReview(
                              toolId: widget.toolId,
                              rating: _rating,
                              body: _body.text.trim(),
                            ),
                        onDone: () {
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                      if (mounted) setState(() => _busy = false);
                    },
              child: _busy
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post review'),
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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _PostComposer(toolId: toolId, toolName: toolName),
    ),
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

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(LizSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share with the community',
              style: Theme.of(context).textTheme.titleLarge),
          if (widget.toolName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.link, size: 16),
                const SizedBox(width: 6),
                Text('Linked to ${widget.toolName}',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'What did you discover? Share your experience…',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: 'Add image (coming soon)',
                onPressed: null,
                icon: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _content.text.trim().isEmpty || _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await runGuardedAction(
                          context,
                          prompt: 'Sign in to post.',
                          action: () => ref.read(communityActionsProvider).createPost(
                                content: _content.text.trim(),
                                toolId: widget.toolId,
                              ),
                          onDone: () {
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        );
                        if (mounted) setState(() => _busy = false);
                      },
                child: _busy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
