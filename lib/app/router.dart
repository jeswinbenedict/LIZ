import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/telemetry/analytics.dart';
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
import '../features/tool_detail/alternatives_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/search_screen.dart';
import '../features/legal/legal_screen.dart';
import '../shared/widgets/states.dart';
import '../features/news/news_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/tool_detail/tool_detail_screen.dart';
import '../features/track/saved_screen.dart';
import 'auth_gate.dart';
import 'responsive/adaptive_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _discoverKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _newsKey = GlobalKey<NavigatorState>(debugLabel: 'news');
final _askKey = GlobalKey<NavigatorState>(debugLabel: 'ask');
final _savedKey = GlobalKey<NavigatorState>(debugLabel: 'saved');
final _profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

/// go_router configuration: every screen has a real URL (deep links + web),
/// with a stateful shell so each tab keeps its own navigation stack.
///
/// [gate] puts every page behind sign-in (see auth_gate.dart); the router
/// re-runs its redirect whenever the gate changes, so signing in or out moves
/// the visitor at once.
GoRouter buildRouter(AuthGate gate) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: gate,
    // Every navigation passes through here: the sign-in wall decides first,
    // and a page that is actually shown tells the crash reporter which screen
    // a later error came from, and counts as a view.
    redirect: (context, state) {
      final elsewhere = authRedirect(
        location: state.uri,
        restored: gate.restored,
        signedIn: gate.signedIn,
      );
      if (elsewhere != null) return elsewhere;
      CrashReporter.currentRoute = state.uri.toString();
      Analytics.pageView(state.uri);
      return null;
    },
    // A mistyped or stale link used to land on go_router's bare debug page:
    // unstyled text and nothing to do. This is a page of the app, with a way
    // back into it.
    errorBuilder: (context, state) => const NotFoundScreen(),
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
                // ?q= arrives from the search box, when what was typed
                // reads as a question rather than a name.
                pageBuilder: (c, s) => NoTransitionPage(
                  child: AskLizScreen(initialQuery: s.uri.queryParameters['q']),
                ),
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
      // A tool's page, by name: /tools/elevenlabs. The id form still resolves
      // for links shared before slugs, and for notifications carrying an id.
      GoRoute(
        path: '/tools/:slug',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => ToolDetailScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/alternatives/:slug',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => AlternativesScreen(slug: s.pathParameters['slug']!),
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
        path: startingPath,
        parentNavigatorKey: _rootKey,
        pageBuilder: (c, s) => const NoTransitionPage(child: StartingScreen()),
      ),
      GoRoute(
        path: '/signin',
        parentNavigatorKey: _rootKey,
        pageBuilder: (c, s) => NoTransitionPage(
          child: SignInScreen(returnTo: s.uri.queryParameters['from']),
        ),
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
