import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'breakpoints.dart';

class NavDestinationSpec {
  const NavDestinationSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const kNavDestinations = <NavDestinationSpec>[
  NavDestinationSpec(
      label: 'Discover', icon: Icons.explore_outlined, selectedIcon: Icons.explore),
  NavDestinationSpec(
      label: 'Community',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum),
  NavDestinationSpec(
      label: 'Ask Liz',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome),
  NavDestinationSpec(
      label: 'Saved',
      icon: Icons.bookmark_border,
      selectedIcon: Icons.bookmark),
  NavDestinationSpec(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person),
];

/// Wraps a [StatefulNavigationShell] and renders the right navigation affordance
/// for the current width: bottom bar (phone) → nav rail (tablet) → sidebar
/// (desktop). Never a stretched phone UI on desktop.
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
    final ff = context.formFactor;
    switch (ff) {
      case FormFactor.phone:
        return _PhoneScaffold(shell: navigationShell, onSelect: _go);
      case FormFactor.tablet:
        return _RailScaffold(
            shell: navigationShell, onSelect: _go, extended: false);
      case FormFactor.desktop:
        return _RailScaffold(
            shell: navigationShell, onSelect: _go, extended: true);
    }
  }
}

class _PhoneScaffold extends StatelessWidget {
  const _PhoneScaffold({required this.shell, required this.onSelect});
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final d in kNavDestinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _RailScaffold extends StatelessWidget {
  const _RailScaffold({
    required this.shell,
    required this.onSelect,
    required this.extended,
  });
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          _SideNav(
            shell: shell,
            onSelect: onSelect,
            extended: extended,
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.shell,
    required this.onSelect,
    required this.extended,
  });
  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = extended ? 240.0 : 84.0;
    return Container(
      width: width,
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: extended ? 20 : 12, vertical: 20),
              child: _Wordmark(compact: !extended),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 8),
                children: [
                  for (var i = 0; i < kNavDestinations.length; i++)
                    _NavTile(
                      spec: kNavDestinations[i],
                      selected: shell.currentIndex == i,
                      extended: extended,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.spec,
    required this.selected,
    required this.extended,
    required this.onTap,
  });
  final NavDestinationSpec spec;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    final content = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.symmetric(
          horizontal: extended ? 14 : 0, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(LizRadius.md),
      ),
      child: Row(
        mainAxisAlignment:
            extended ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(selected ? spec.selectedIcon : spec.icon, color: fg, size: 24),
          if (extended) ...[
            const SizedBox(width: 14),
            Text(
              spec.label,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LizRadius.md),
        onTap: onTap,
        child: extended
            ? content
            : Tooltip(message: spec.label, child: content),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, LizColors.rising],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Text('L',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
    );
    if (compact) return Center(child: mark);
    return Row(
      children: [
        mark,
        const SizedBox(width: 12),
        Text('Liz',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 24)),
      ],
    );
  }
}

/// Small reusable brand wordmark for app bars.
class LizWordmark extends StatelessWidget {
  const LizWordmark({super.key});
  @override
  Widget build(BuildContext context) => const _Wordmark();
}
