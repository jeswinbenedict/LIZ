import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../features/alerts/alerts_controller.dart';
import '../../shared/widgets/liz_mark.dart';
import '../../shared/widgets/user_avatar.dart';
import '../theme.dart';
import 'breakpoints.dart';

/// One destination in the app's navigation. The list order is the router's
/// branch order (router.dart); where it appears is decided per form factor.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.brand = false,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Drawn as the Liz mark instead of [icon]: the destination is Liz itself.
  final bool brand;
}

/// Indexed by branch. Community has no entry on purpose (see router.dart);
/// adding it back is one entry here and one branch there.
const kNavDestinations = <NavDestinationSpec>[
  NavDestinationSpec(
    label: 'Discover',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  NavDestinationSpec(
    label: 'News',
    icon: Icons.article_outlined,
    selectedIcon: Icons.article,
  ),
  NavDestinationSpec(
    label: 'Ask Liz',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    brand: true,
  ),
  NavDestinationSpec(
    label: 'Repos',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
  ),
  NavDestinationSpec(
    label: 'Saved',
    icon: Icons.bookmark_border,
    selectedIcon: Icons.bookmark,
  ),
  NavDestinationSpec(
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

// Branch indices, named, so the sidebar's grouping reads as intent.
const _discover = 0, _news = 1, _ask = 2, _repos = 3, _saved = 4, _profile = 5;

/// Tab bar on phones, a rail on tablets, a sidebar on desktop — chosen by
/// width, never by device (docs/DESIGN.md §7).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⌘K / Ctrl+K opens search from anywhere, as it does across the web.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            context.push('/search'),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            context.push('/search'),
      },
      child: Focus(
        autofocus: true,
        child: switch (context.formFactor) {
          FormFactor.phone => _PhoneScaffold(
            shell: navigationShell,
            onSelect: _go,
          ),
          FormFactor.tablet => _RailScaffold(
            shell: navigationShell,
            onSelect: _go,
          ),
          FormFactor.desktop => _SidebarScaffold(
            shell: navigationShell,
            onSelect: _go,
          ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone: a glass tab bar.
// ---------------------------------------------------------------------------

class _PhoneScaffold extends StatelessWidget {
  const _PhoneScaffold({required this.shell, required this.onSelect});
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      extendBody: true,
      bottomNavigationBar: GlassBar(
        edge: GlassEdge.top,
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in kNavDestinations)
              NavigationDestination(
                icon: d.brand ? const LizMark.icon() : Icon(d.icon),
                selectedIcon: d.brand
                    ? const LizMark.icon()
                    : Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Which edge of a glass bar carries its hairline.
enum GlassEdge { top, bottom }

/// The bar material (docs/DESIGN.md §5): the canvas at 92% over a blur, so
/// the bar stays solid enough to read while content scrolls underneath, with
/// one hairline where it meets the page.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.edge = GlassEdge.bottom,
  });
  final Widget child;
  final GlassEdge edge;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Stack(
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.canvas.withValues(alpha: 0.92),
              ),
              child: child,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: edge == GlassEdge.top ? 0 : null,
          bottom: edge == GlassEdge.bottom ? 0 : null,
          child: const GlowLine(strength: 0.85),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet: an icon rail.
// ---------------------------------------------------------------------------

class _RailScaffold extends StatelessWidget {
  const _RailScaffold({required this.shell, required this.onSelect});
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 72,
            decoration: BoxDecoration(
              color: p.canvas.withValues(alpha: 0.62),
              border: Border(right: BorderSide(color: p.hairline)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const LizMark(size: 30),
                  const SizedBox(height: 20),
                  _RailButton(
                    icon: Icons.search,
                    label: 'Search',
                    onTap: () => context.push('/search'),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < kNavDestinations.length; i++)
                    _RailButton(
                      icon: shell.currentIndex == i
                          ? kNavDestinations[i].selectedIcon
                          : kNavDestinations[i].icon,
                      label: kNavDestinations[i].label,
                      brand: kNavDestinations[i].brand,
                      selected: shell.currentIndex == i,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: _PageArea(shell: shell)),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    this.brand = false,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final bool brand;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: label,
        child: Semantics(
          container: true,
          selected: selected,
          button: true,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: selected ? p.surfaceHover : Colors.transparent,
            shape: LizRadius.shape(LizRadius.sm),
            child: InkWell(
              customBorder: LizRadius.shape(LizRadius.sm),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 48,
                child: brand
                    ? LizMark.icon(
                        size: 22,
                        color: selected ? p.textPrimary : p.textSecondary,
                      )
                    : Icon(
                        icon,
                        size: 22,
                        color: selected ? p.textPrimary : p.textSecondary,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop: a grouped sidebar.
// ---------------------------------------------------------------------------

class _SidebarScaffold extends StatelessWidget {
  const _SidebarScaffold({required this.shell, required this.onSelect});
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    Widget item(int branch) => _SideItem(
      spec: kNavDestinations[branch],
      selected: shell.currentIndex == branch,
      onTap: () => onSelect(branch),
    );

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: p.canvas.withValues(alpha: 0.62),
              border: Border(right: BorderSide(color: p.hairline)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: LizWordmark(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: _SidebarSearch(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                      children: [
                        const _GroupLabel('Browse'),
                        item(_discover),
                        item(_ask),
                        item(_news),
                        item(_repos),
                        const SizedBox(height: 20),
                        const _GroupLabel('Library'),
                        item(_saved),
                        const _AlertsItem(),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: p.hairline),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _AccountItem(
                      selected: shell.currentIndex == _profile,
                      onTap: () => onSelect(_profile),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _PageArea(shell: shell)),
        ],
      ),
    );
  }
}

/// The page beside the rail or sidebar, in a semantics container of its own.
///
/// Every page route carries a BlockSemantics barrier, which drops whatever
/// was painted before it in the same container. Without this boundary that
/// was the whole sidebar — screen readers could not see Discover, News or
/// Saved, only the page.
class _PageArea extends StatelessWidget {
  const _PageArea({required this.shell});
  final Widget shell;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, explicitChildNodes: true, child: shell);
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Semantics(
        container: true,
        header: true,
        child: Text(
          text,
          style: LizText.label.copyWith(color: context.liz.textSecondary),
        ),
      ),
    );
  }
}

/// A sidebar row: icon and label. The selected row is a neutral raised pill
/// with white text and icon; the others are secondary grey until hovered.
class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.icon,
    this.brand = false,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });
  final IconData icon;
  final bool brand;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected ? p.surfaceHover : Colors.transparent,
          shape: LizRadius.shape(LizRadius.sm),
          child: InkWell(
            customBorder: LizRadius.shape(LizRadius.sm),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    if (brand)
                      LizMark.icon(
                        size: 18,
                        color: selected ? p.textPrimary : p.textSecondary,
                      )
                    else
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? p.textPrimary : p.textSecondary,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.callout.copyWith(
                          color: selected ? p.textPrimary : p.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    ?trailing,
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

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });
  final NavDestinationSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SideRow(
    icon: selected ? spec.selectedIcon : spec.icon,
    brand: spec.brand,
    label: spec.label,
    selected: selected,
    onTap: onTap,
  );
}

class _AlertsItem extends ConsumerWidget {
  const _AlertsItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(isSignedInProvider)
        ? ref.watch(unreadAlertsProvider)
        : 0;
    final p = context.liz;
    return _SideRow(
      icon: unread > 0 ? Icons.notifications : Icons.notifications_none,
      label: 'Alerts',
      onTap: () => context.push('/alerts'),
      trailing: unread == 0
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: ShapeDecoration(
                color: p.accentFill,
                shape: const StadiumBorder(),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                semanticsLabel: '$unread unread',
                style: LizText.footnote.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: LizText.tabular,
                ),
              ),
            ),
    );
  }
}

class _AccountItem extends ConsumerWidget {
  const _AccountItem({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final user = ref.watch(currentUserProvider);
    return Material(
      color: selected ? p.surfaceHover : Colors.transparent,
      shape: LizRadius.shape(LizRadius.sm),
      child: InkWell(
        customBorder: LizRadius.shape(LizRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (user != null)
                ExcludeSemantics(child: UserAvatar(profile: user, radius: 16))
              else
                CircleAvatar(
                  radius: 16,
                  backgroundColor: p.surfaceHover,
                  child: Icon(Icons.person, size: 18, color: p.textSecondary),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Sign in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.callout.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user == null
                          ? 'Save and follow tools'
                          : '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.footnote.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, size: 18, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search as a field, not an icon: it is the main thing a discovery app does.
class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      container: true,
      button: true,
      label: 'Search tools',
      excludeSemantics: true,
      child: Material(
        color: p.canvas,
        shape: LizRadius.shape(
          LizRadius.sm,
          side: BorderSide(color: p.hairlineStrong),
        ),
        child: InkWell(
          customBorder: LizRadius.shape(LizRadius.sm),
          onTap: () => context.push('/search'),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(Icons.search, size: 18, color: p.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search',
                    style: LizText.callout.copyWith(color: p.textSecondary),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: p.surfaceMuted,
                    shape: LizRadius.shape(
                      LizRadius.xs,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                  child: const _ShortcutHint(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "⌘K", drawn with an icon: the bundled font has no ⌘ glyph.
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint();

  @override
  Widget build(BuildContext context) {
    final color = context.liz.textSecondary;
    return Semantics(
      container: true,
      label: 'Command K',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_command_key, size: 12, color: color),
          Text('K', style: LizText.footnote.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brand.
// ---------------------------------------------------------------------------

/// The brand mark and name, for sidebars and phone top bars.
class LizWordmark extends StatelessWidget {
  const LizWordmark({super.key, this.size = 24});

  /// The mark's height; the word is set to match it.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Beside the word the mark is decoration; announcing both would say the
    // name twice.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: LizMark(size: size)),
        SizedBox(width: size * 0.3),
        // Lowercase, bold and set tight: the l of the word repeats the stem
        // of the mark beside it.
        Semantics(
          container: true,
          label: 'Liz',
          excludeSemantics: true,
          child: Text(
            'liz',
            style: LizText.title3.copyWith(
              color: context.liz.textPrimary,
              fontSize: size * 0.95,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -size * 0.03,
            ),
          ),
        ),
      ],
    );
  }
}
