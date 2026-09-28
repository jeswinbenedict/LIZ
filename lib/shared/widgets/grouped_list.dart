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
              header: true,
              child: Text(
                title!.toUpperCase(),
                style: LizText.caption.copyWith(color: p.textSecondary),
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

/// One row of a [LizGroup]: a tinted icon tile, a title, and a value or a
/// chevron. [destructive] turns it red, for actions that cannot be undone.
class LizGroupRow extends StatelessWidget {
  const LizGroupRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.iconColor,
    this.destructive = false,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final tint = destructive ? p.danger : (iconColor ?? p.accent);
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
                    color: tint.withValues(alpha: 0.12),
                    shape: LizRadius.shape(8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: LizColors.legibleOn(
                      tint,
                      Color.alphaBlend(tint.withValues(alpha: 0.12), p.surface),
                      minimum: 3,
                    ),
                  ),
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
