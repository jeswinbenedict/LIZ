import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A grouped list (docs/DESIGN.md §7): rows inside one rounded surface,
/// separated by hairlines inset past their icons — iOS Settings. For settings,
/// account pages and anything that is a short list of choices.
class LizGroup extends StatelessWidget {
  const LizGroup({super.key, this.title, this.footer, required this.children});

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                title!,
                style: LizText.label.copyWith(color: p.textSecondary),
              ),
            ),
          ),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: p.surface,
            shape: LizRadius.shape(
              LizRadius.md,
              side: BorderSide(color: p.hairline),
            ),
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(LizRadius.md),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(height: 1, color: p.hairline),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer!,
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// One row of a [LizGroup]: an icon tile, a title, and a value or a
/// chevron. [destructive] turns it red, for actions that cannot be undone.
class LizGroupRow extends StatelessWidget {
  const LizGroupRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.destructive = false,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    // Icons are white on a dark tile: in a list of settings, red on every
    // row would mean nothing. Only a destructive row is coloured.
    final tint = destructive ? p.danger : p.textPrimary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: ShapeDecoration(
                    color: destructive
                        ? p.danger.withValues(alpha: 0.12)
                        : p.surfaceHover,
                    shape: LizRadius.shape(
                      LizRadius.sm,
                      side: BorderSide(color: p.hairlineStrong),
                    ),
                  ),
                  child: Icon(icon, size: 17, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: LizText.body.copyWith(
                          color: destructive
                              ? LizColors.legibleOn(p.danger, p.surface)
                              : p.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value!,
                      style: LizText.callout.copyWith(color: p.textSecondary),
                    ),
                  ),
                ?trailing,
                if (onTap != null && showChevron && trailing == null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: p.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A [LizGroup] row with a switch: the same icon tile and insets as
/// [LizGroupRow], a title, an optional line, and the switch. Settings and
/// onboarding both use it.
class LizGroupSwitch extends StatelessWidget {
  const LizGroupSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    // Its own transparent Material: the group behind it is a coloured box,
    // which would otherwise hide the row's ink.
    return Material(
      type: MaterialType.transparency,
      child: MergeSemantics(
        child: SwitchListTile(
          // The same icon tile and insets as LizGroupRow, so the hairlines
          // between rows line up.
          contentPadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          horizontalTitleGap: 14,
          secondary: Container(
            width: 30,
            height: 30,
            decoration: ShapeDecoration(
              color: p.surfaceHover,
              shape: LizRadius.shape(
                LizRadius.sm,
                side: BorderSide(color: p.hairlineStrong),
              ),
            ),
            child: Icon(icon, size: 17, color: p.textPrimary),
          ),
          title: Text(
            title,
            style: LizText.body.copyWith(color: p.textPrimary),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
