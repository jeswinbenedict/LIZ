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
        appBar: AppBar(title: const Text('Admin')),
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
          appBar: AppBar(
            title: const Text('Admin console'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Health', icon: Icon(Icons.monitor_heart_outlined)),
                Tab(text: 'Content', icon: Icon(Icons.inventory_2_outlined)),
                Tab(text: 'News', icon: Icon(Icons.newspaper_outlined)),
                Tab(text: 'Moderation', icon: Icon(Icons.flag_outlined)),
              ],
            ),
          ),
          body: MaxWidth(
            maxWidth: 1000,
            child: const TabBarView(
              children: [HealthTab(), ContentTab(), NewsTab(), ModerationTab()],
            ),
          ),
        ),
      ),
    );
  }
}
