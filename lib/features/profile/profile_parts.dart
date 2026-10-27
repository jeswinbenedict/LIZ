import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/models/profile.dart';
import '../../shared/widgets/badges.dart';

/// The pieces a profile page is built from — your own (ProfileScreen) and
/// anyone else's (UserProfileScreen) — so the two read as the same page.

/// The avatar, the name as the page's heading, a quiet role badge, when they
/// joined, the bio, and the figures — set as type, not tiles. [trailing]
/// sits at the right of the name (Follow, on someone else's page).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.avatar,
    required this.figures,
    this.trailing,
  });

  final Profile profile;
  final Widget avatar;

  /// (count, noun) pairs — "12 saved". A null count shows a dash.
  final List<(int?, String)> figures;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = context.isPhone;
    final joined = DateFormat.yMMMM().format(profile.createdAt.toLocal());
    final role = switch (profile.role) {
      UserRole.admin => 'Admin',
      UserRole.moderator => 'Moderator',
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        SizedBox(width: phone ? 16 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          container: true,
                          header: true,
                          headingLevel: 1,
                          child: Text(
                            profile.displayName,
                            style: (phone ? LizText.title1 : LizText.largeTitle)
                                .copyWith(color: p.textPrimary),
                          ),
                        ),
                        if (role != null) LizPill(label: role),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.username}  ·  Joined $joined',
                style: LizText.subhead.copyWith(color: p.textSecondary),
              ),
              if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    profile.bio!,
                    style: LizText.body.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  for (final (value, label) in figures)
                    ProfileFigure(value: value, label: label),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "12 saved": the figure in ink, the noun in grey. A dash while unknown.
class ProfileFigure extends StatelessWidget {
  const ProfileFigure({super.key, required this.value, required this.label});
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value == null ? '—' : '$value',
            style: LizText.headline.copyWith(
              color: p.textPrimary,
              fontFeatures: LizText.tabular,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class ProfileHeading extends StatelessWidget {
  const ProfileHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      container: true,
      header: true,
      child: Text(
        text,
        style: LizText.title3.copyWith(color: context.liz.textPrimary),
      ),
    ),
  );
}

/// A section's frame, kept when it has rows.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: child,
    );
  }
}

/// An empty section keeps its frame: an icon, one sentence, and at most one
/// way forward.
class ProfileEmptyPanel extends StatelessWidget {
  const ProfileEmptyPanel({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return ProfilePanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        // The button sits beside the sentence where there is room for both,
        // and under it on a narrow screen or with large text.
        child: LayoutBuilder(
          builder: (context, box) {
            final button = action != null && onAction != null
                ? OutlinedButton(onPressed: onAction, child: Text(action!))
                : null;
            final sentence = Text(
              text,
              style: LizText.callout.copyWith(color: p.textSecondary),
            );
            final beside = box.maxWidth >= 440;
            return Row(
              crossAxisAlignment: beside
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: p.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: beside || button == null
                      ? sentence
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sentence,
                            const SizedBox(height: 12),
                            button,
                          ],
                        ),
                ),
                if (beside && button != null) ...[
                  const SizedBox(width: 12),
                  button,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
