import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/telemetry/crash_reporter.dart';
import '../features/admin/admin_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/ask_liz/ask_liz_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/post_detail_screen.dart';
import '../features/compare/compare_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/search_screen.dart';
import '../features/legal/legal_screen.dart';
import '../features/news/news_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/tool_detail/tool_detail_screen.dart';
import '../features/track/saved_screen.dart';
import 'responsive/adaptive_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _discoverKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _newsKey = GlobalKey<NavigatorState>(debugLabel: 'news');
final _askKey = GlobalKey<NavigatorState>(debugLabel: 'ask');
final _savedKey = GlobalKey<NavigatorState>(debugLabel: 'saved');
final _profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

/// go_router configuration: every screen has a real URL (deep links + web),
/// with a stateful shell so each tab keeps its own navigation stack.
GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    // Not a redirect in the usual sense — it never returns a destination. It
    // is the one place every navigation passes through, which makes it where
    // the crash reporter learns which screen a later error came from.
    redirect: (context, state) {
      CrashReporter.currentRoute = state.uri.toString();
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AdaptiveShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _discoverKey,
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: DiscoverScreen()),
                routes: [
                  GoRoute(
                    path: 'category/:slug',
                    builder: (c, s) => DiscoverScreen(
                      initialCategory: s.pathParameters['slug'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _newsKey,
            routes: [
              GoRoute(
                path: '/news',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: NewsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _askKey,
            routes: [
              GoRoute(
                path: '/ask',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: AskLizScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _savedKey,
            routes: [
              GoRoute(
                path: '/saved',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: SavedScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: ProfileScreen()),
                routes: [
                  GoRoute(
                    path: 'settings',
                    parentNavigatorKey: _rootKey,
                    builder: (c, s) => const SettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/tool/:id',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => ToolDetailScreen(toolId: s.pathParameters['id']!),
      ),
      // Community has no nav entry: an empty forum reads worse than none at
      // all until there are people in it. The screen stays reachable by link
      // so existing URLs keep working and restoring the tab is one line.
      GoRoute(
        path: '/community',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const CommunityScreen(),
      ),
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => PostDetailScreen(postId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/user/:id',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => UserProfileScreen(userId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        builder: (c, s) =>
            SearchScreen(initialQuery: s.uri.queryParameters['q']),
      ),
      GoRoute(
        path: '/compare',
        parentNavigatorKey: _rootKey,
        builder: (c, s) {
          final ids = (s.uri.queryParameters['ids'] ?? '')
              .split(',')
              .where((e) => e.isNotEmpty)
              .toList();
          return CompareScreen(toolIds: ids);
        },
      ),
      GoRoute(
        path: '/alerts',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const AlertsScreen(),
      ),
      GoRoute(
        path: '/signin',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const SignInScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        parentNavigatorKey: _rootKey,
        builder: (c, s) =>
            ForgotPasswordScreen(initialEmail: s.uri.queryParameters['email']),
      ),
      // Where a reset link lands. Supabase turns the token into a session
      // before this builds, so the screen only has to set the new password.
      GoRoute(
        path: '/reset-password',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const LegalScreen(document: LegalDocument.privacy),
      ),
      GoRoute(
        path: '/terms',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const LegalScreen(document: LegalDocument.terms),
      ),
      GoRoute(
        path: '/admin',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const AdminScreen(),
      ),
    ],
  );
}
