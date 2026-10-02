import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import 'pressable.dart';

/// A page's title block (docs/DESIGN.md §7, Top bar): a large title in the
/// page, an optional line under it, and optional trailing actions. Phones get
/// a slightly smaller title, since a 32px word crowds a 390px screen.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.bottom = 20,
    this.eyebrow,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double bottom;

  /// A short monospace line above the title; see [Eyebrow].
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        context.isPhone ? 8 : 36,
        gutter,
        bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Eyebrow(eyebrow!),
                  const SizedBox(height: 10),
                ],
                Semantics(
                  container: true,
                  header: true,
                  headingLevel: 1,
                  child: Text(
                    title,
                    style:
                        (context.isPhone ? LizText.title1 : LizText.largeTitle)
                            .copyWith(color: p.textPrimary),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: LizText.body.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

/// A section title inside a page, with an optional line and action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.padding,
    this.eyebrow,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  /// A short monospace line above the title; see [Eyebrow].
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(gutter, 28, gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Eyebrow(eyebrow!),
                  const SizedBox(height: 6),
                ],
                Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    title,
                    style: LizText.title2.copyWith(color: p.textPrimary),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: LizText.callout.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// The small monospace line above a title ("// MOMENTUM, NOT HYPE"), in red
/// with a faint glow: Signal's instrument-label voice. Capitals as written.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Text(
      text,
      style: LizText.label.copyWith(
        color: p.accent,
        letterSpacing: 1.6,
        shadows: [Shadow(color: p.glow.withValues(alpha: 0.7), blurRadius: 8)],
      ),
    );
  }
}

/// Looks like a search field and opens search. Used where a page should
/// invite a search without owning its results.
class SearchLauncher extends StatelessWidget {
  const SearchLauncher({
    super.key,
    this.hint = 'Search tools, e.g. “transcribe meetings”',
    this.large = false,
  });

  final String hint;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final height = large ? 52.0 : 44.0;
    return Semantics(
      button: true,
      label: 'Search tools',
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: LizRadius.shape(
          large ? LizRadius.md : LizRadius.sm,
          side: BorderSide(color: p.hairlineStrong),
        ),
        child: InkWell(
          customBorder: LizRadius.shape(large ? LizRadius.md : LizRadius.sm),
          onTap: () => context.push('/search'),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                SizedBox(width: large ? 16 : 12),
                Icon(
                  Icons.search,
                  size: large ? 22 : 20,
                  color: p.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (large ? LizText.body : LizText.callout).copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ),
                if (context.isDesktop)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_command_key,
                          size: 13,
                          color: p.textSecondary,
                        ),
                        Text(
                          'K',
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A segmented control (docs/DESIGN.md §7): an outlined track, with the
/// chosen segment lit — a red edge on a faint red fill. Drawn 36px tall, but each segment's hit area is
/// the full 48 — the platform minimum for a finger.
class LizSegmented<T> extends StatelessWidget {
  const LizSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Fill the width with equal segments (a form's mode switch) instead of
  /// sizing to the labels.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final duration = LizMotion.of(context, LizMotion.standard);
    final segmentWidgets = [
      for (final entry in segments.entries)
        _Segment(
          label: entry.value,
          selected: entry.key == value,
          duration: duration,
          onTap: () => onChanged(entry.key),
        ),
    ];
    if (expand) {
      return SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.surface,
                  shape: LizRadius.shape(
                    LizRadius.sm,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
              ),
            ),
            Row(children: [for (final s in segmentWidgets) Expanded(child: s)]),
          ],
        ),
      );
    }
    // Scrolls sideways when it is wider than the room it is given: four
    // segments do not fit a 320-pixel phone, and overflowing is worse.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.surface,
                  shape: LizRadius.shape(
                    LizRadius.sm,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: segmentWidgets),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    // A radio in a group: a screen reader says which one is chosen, which
    // it does not for a button marked selected.
    return Pressable(
      onTap: onTap,
      builder: (context, focused) => Semantics(
        checked: selected,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: label,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: duration,
                curve: LizMotion.ease,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected ? p.accentSoft : Colors.transparent,
                  shape: LizRadius.shape(
                    LizRadius.xs,
                    side: selected
                        ? BorderSide(color: p.accent)
                        : BorderSide.none,
                  ),
                  shadows: [
                    if (focused) ...focusRing(p),
                    if (selected) ...LizShadows.glow(p, strength: 0.35),
                  ],
                ),
                child: Text(
                  label,
                  style: LizText.subhead.copyWith(
                    color: selected ? p.textPrimary : p.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone top bar: glass, pinned, with the wordmark and a few actions.
/// Wider layouts put the title in the page and navigation in the sidebar.
class PhoneTopBar extends StatelessWidget {
  const PhoneTopBar({super.key, this.actions = const [], this.title});
  final List<Widget> actions;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 56,
      backgroundColor: Colors.transparent,
      titleSpacing: 16,
      flexibleSpace: const GlassBar(child: SizedBox.expand()),
      title: title ?? const LizWordmark(size: 24),
      actions: [...actions, const SizedBox(width: 4)],
    );
  }
}

/// A filter pill (docs/DESIGN.md §7): an outline when off, lit when on — a
/// red edge on a faint red fill. Drawn 32px tall with a 48px hit area.
class LizFilterPill extends StatelessWidget {
  const LizFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingIcon,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final fg = selected ? p.textPrimary : p.textSecondary;
    final duration = LizMotion.of(context, LizMotion.quick);
    return Pressable(
      onTap: onTap,
      builder: (context, focused) => Semantics(
        button: true,
        selected: selected,
        label: semanticLabel ?? label,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 48,
            // widthFactor 1: size to the pill, not to whatever width a Wrap
            // or Column offers, which centred it on a line of its own.
            child: Align(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: duration,
                height: 32,
                padding: EdgeInsets.only(
                  left: icon != null ? 10 : 14,
                  right: trailingIcon != null ? 10 : 14,
                ),
                decoration: ShapeDecoration(
                  color: selected ? p.accentSoft : p.surface,
                  shape: LizRadius.shape(
                    LizRadius.xs,
                    side: BorderSide(
                      color: selected ? p.accent : p.hairlineStrong,
                    ),
                  ),
                  shadows: [
                    if (focused) ...focusRing(p),
                    if (selected) ...LizShadows.glow(p, strength: 0.3),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 15, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: LizText.subhead.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 4),
                      Icon(trailingIcon, size: 16, color: fg),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
