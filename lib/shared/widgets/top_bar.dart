import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import 'liz_mark.dart';
import 'page_header.dart';

/// The bar on pages that open over the app — a tool, a comparison, alerts,
/// settings, a legal page. Two jobs:
///
/// * **A way back that always works.** The previous page when there is one;
///   [fallback] when the page was opened by its address (a shared link, a
///   reload), where a plain back button had nothing to go back to and was
///   not drawn at all.
/// * **Where you are, on wider windows.** "Liz / Discover / Lensflow": the
///   product's name, the way back up, and this page. A phone keeps the bar
///   to the back button, the page's title and its actions.
class LizTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LizTopBar({
    super.key,
    this.title,
    this.section,
    this.fallback = '/',
    this.actions = const [],
    this.titleIsHeading = true,
  });

  /// The page's name: shown in the bar on a phone and as the trail's last
  /// step on wider windows. Null while it is still loading.
  final String? title;

  /// The step between "Liz" and the page, with where it leads.
  final (String, String)? section;

  /// Where back goes when there is no history.
  final String fallback;

  final List<Widget> actions;

  /// Whether [title] is the page's level-1 heading. False for pages whose
  /// heading is in the page itself (a tool's name above its icon).
  final bool titleIsHeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = context.isPhone;
    Widget? name(TextStyle style) {
      final text = title;
      if (text == null) return null;
      return titleIsHeading
          ? PageHeading(text, style: style)
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
    }

    return AppBar(
      leading: BackButton(
        onPressed: () =>
            context.canPop() ? context.pop() : context.go(fallback),
      ),
      titleSpacing: phone ? null : 0,
      title: phone
          ? name(LizText.title3.copyWith(color: p.textPrimary))
          : _Trail(
              section: section,
              current: name(LizText.callout.copyWith(color: p.textPrimary)),
            ),
      shape: phone ? null : Border(bottom: BorderSide(color: p.hairline)),
      actions: [...actions, const SizedBox(width: 4)],
    );
  }
}

class _Trail extends StatelessWidget {
  const _Trail({this.section, this.current});
  final (String, String)? section;
  final Widget? current;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    const gap = SizedBox(width: 6);
    final sep = ExcludeSemantics(
      child: Text('/', style: LizText.callout.copyWith(color: p.textTertiary)),
    );
    final link = section;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LizMark.icon(size: 18),
        const SizedBox(width: 8),
        Text(
          'Liz',
          style: LizText.callout.copyWith(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (link != null) ...[
          gap,
          sep,
          gap,
          TextButton(
            onPressed: () => context.go(link.$2),
            style: TextButton.styleFrom(
              foregroundColor: p.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              minimumSize: const Size(0, 36),
              textStyle: LizText.callout,
            ),
            child: Text(link.$1),
          ),
        ],
        if (current != null) ...[gap, sep, gap, Flexible(child: current!)],
      ],
    );
  }
}
