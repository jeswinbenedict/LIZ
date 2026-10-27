import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../app/theme.dart';
import 'grouped_list.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(40),
      child: CircularProgressIndicator(),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.headingLevel = 2,
  });
  final IconData icon;
  final String title;

  /// 1 when the state is the whole page (not found), 2 inside a page.
  final int headingLevel;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Center(
      // Scrollable so the illustration and its message survive a short box —
      // an empty state inside a filtered list can have very little height, and
      // an overflow stripe is a worse answer than a little scrolling.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(LizSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // docs/DESIGN.md §7, Empty state: an icon in a soft circle, a
              // title, one sentence, at most one action.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.hairline),
                ),
                child: Icon(icon, size: 26, color: p.textSecondary),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  children: [
                    Semantics(
                      container: true,
                      header: true,
                      headingLevel: headingLevel,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: LizText.title3.copyWith(color: p.textPrimary),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: LizText.callout.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message ?? 'Please try again.',
      action: FilledButton(
        style: LizButtons.tonal(context.liz),
        onPressed: onRetry,
        child: const Text('Try again'),
      ),
    );
  }
}

/// Shown for any address the app does not know (docs/DESIGN.md §8): the
/// wordmark, what happened and at which address, the two ways back in, and
/// the main places as a short list.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.path});

  /// The address that was asked for.
  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final asked = path != null && path!.isNotEmpty && path != '/';
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  link: true,
                  label: 'Liz, Discover',
                  child: InkWell(
                    onTap: () => context.go('/'),
                    customBorder: LizRadius.shape(LizRadius.sm),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: ExcludeSemantics(child: LizWordmark(size: 24)),
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: p.hairline),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: phone ? 20 : 32,
                    vertical: 40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Error 404',
                          style: LizText.subhead.copyWith(
                            color: p.textSecondary,
                            fontFeatures: LizText.tabular,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          container: true,
                          header: true,
                          headingLevel: 1,
                          child: Text(
                            'This page is not here',
                            style: (phone ? LizText.title1 : LizText.largeTitle)
                                .copyWith(color: p.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          asked
                              ? 'Nothing lives at $path. The link may be '
                                    'mistyped, or the page may have moved.'
                              : 'The link may be mistyped, or the page may '
                                    'have moved.',
                          style: LizText.body.copyWith(color: p.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: () => context.go('/'),
                              child: const Text('Go to Discover'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/search'),
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('Search tools'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        LizGroup(
                          title: 'Or go to',
                          children: [
                            LizGroupRow(
                              icon: Icons.question_answer_outlined,
                              title: 'Ask Liz',
                              onTap: () => context.go('/ask'),
                            ),
                            LizGroupRow(
                              icon: Icons.article_outlined,
                              title: 'News',
                              onTap: () => context.go('/news'),
                            ),
                            LizGroupRow(
                              icon: Icons.bookmark_outline,
                              title: 'Saved',
                              onTap: () => context.go('/saved'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
