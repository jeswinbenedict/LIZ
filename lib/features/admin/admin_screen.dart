import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/widgets/states.dart';
import 'content_tab.dart';
import 'health_tab.dart';
import 'moderation_tab.dart';
import 'news_tab.dart';
import 'two_step_gate.dart';
import '../../app/theme.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/top_bar.dart';

/// Web-focused moderation console. Role-gated: non-admins are turned away
/// (defense-in-depth on top of RLS, which is the real enforcement), and a
/// moderator passes a two-step code check first (TwoStepGate).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    if (profile == null || !profile.role.canModerate) {
      return Scaffold(
        appBar: const LizTopBar(title: 'Admin'),
        body: EmptyView(
          icon: Icons.lock_outline,
          title: 'Admins only',
          message: 'You don\'t have permission to view this page.',
          action: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go home'),
          ),
        ),
      );
    }

    return TwoStepGate(
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: const LizTopBar(
            title: 'Admin console',
            section: ('Profile', '/profile'),
            fallback: '/profile',
            titleIsHeading: false,
          ),
          body: Builder(
            builder: (context) {
              final p = context.liz;
              final gutter = LizSpacing.gutter(
                MediaQuery.sizeOf(context).width,
              );
              return MaxWidth(
                maxWidth: 1080 + gutter * 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: 'Admin console',
                      subtitle: context.isPhone
                          ? null
                          : 'Whether Liz is healthy, what is waiting for '
                                'review, and what readers reported.',
                      bottom: 12,
                    ),
                    // Tabs in line with the content, a hairline under them.
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: p.hairline)),
                        ),
                        child: const TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          padding: EdgeInsets.zero,
                          labelPadding: EdgeInsets.only(right: 24),
                          dividerHeight: 0,
                          tabs: [
                            _AdminTab(Icons.monitor_heart_outlined, 'Health'),
                            _AdminTab(Icons.inventory_2_outlined, 'Content'),
                            _AdminTab(Icons.newspaper_outlined, 'News'),
                            _AdminTab(Icons.flag_outlined, 'Moderation'),
                          ],
                        ),
                      ),
                    ),
                    const Expanded(
                      child: TabBarView(
                        children: [
                          HealthTab(),
                          ContentTab(),
                          NewsTab(),
                          ModerationTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A tab: its icon beside its name rather than stacked over it.
class _AdminTab extends StatelessWidget {
  const _AdminTab(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tab(
    height: 48,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
    ),
  );
}
