import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

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
  });
  final IconData icon;
  final String title;
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
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: LizText.title3.copyWith(color: p.textPrimary),
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

/// Shown for any address the app does not know.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyView(
        icon: Icons.explore_off_outlined,
        title: 'This page is not here',
        message: 'The link may be mistyped, or the page may have moved.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go to Discover'),
        ),
      ),
    );
  }
}
