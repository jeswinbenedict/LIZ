import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/features/admin/admin_screen.dart';
import 'package:liz/features/alerts/alerts_screen.dart';
import 'package:liz/features/ask_liz/ask_liz_screen.dart';
import 'package:liz/features/auth/forgot_password_screen.dart';
import 'package:liz/features/auth/reset_password_screen.dart';
import 'package:liz/features/auth/sign_in_screen.dart';
import 'package:liz/features/community/community_screen.dart';
import 'package:liz/features/community/post_detail_screen.dart';
import 'package:liz/features/compare/compare_screen.dart';
import 'package:liz/features/discover/discover_screen.dart';
import 'package:liz/features/discover/search_screen.dart';
import 'package:liz/features/legal/legal_screen.dart';
import 'package:liz/features/news/news_screen.dart';
import 'package:liz/features/profile/profile_screen.dart';
import 'package:liz/features/profile/settings_screen.dart';
import 'package:liz/features/profile/user_profile_screen.dart';
import 'package:liz/features/tool_detail/alternatives_screen.dart';
import 'package:liz/features/tool_detail/tool_detail_screen.dart';
import 'package:liz/features/track/saved_screen.dart';

/// Every screen, in the settings that break layouts and the checks that make an
/// interface unusable to someone.
///
/// Layout: a 320-wide phone (the narrowest still in circulation), text at 1.5x
/// (within the range the platform accessibility settings offer), and a tablet
/// in portrait. Accessibility: Flutter's guidelines for labelled controls and
/// contrast, in both themes.
///
/// Each runs signed out and signed in, because half of these screens are two
/// different screens depending on which: Profile is a sign-in prompt for a
/// guest and an account page for a member, and the admin console is a refusal
/// or four tabs. The signed-in account is the mock's demo user, an admin, so
/// the most controls are on screen.
///
/// This replaced two sweeps that covered seven screens between them. Adding a
/// screen to the app means adding it here.

final _screens = <String, Widget>{
  'Discover': const DiscoverScreen(),
  'Search': const SearchScreen(initialQuery: 'video'),
  'Ask Liz': const AskLizScreen(),
  'Tool detail': const ToolDetailScreen(toolId: 't-1'),
  'Compare': const CompareScreen(toolIds: ['t-1', 't-2']),
  'Alternatives': const AlternativesScreen(slug: 'scriptly'),
  'News': const NewsScreen(),
  'Saved': const SavedScreen(),
  'Alerts': const AlertsScreen(),
  'Profile': const ProfileScreen(),
  'User profile': const UserProfileScreen(userId: 'u-maya'),
  'Settings': const SettingsScreen(),
  'Sign in': const SignInScreen(),
  'Forgot password': const ForgotPasswordScreen(),
  'Reset password': const ResetPasswordScreen(),
  'Community': const CommunityScreen(),
  'Post': const PostDetailScreen(postId: 'p-1'),
  'Admin': const AdminScreen(),
  'Privacy policy': const LegalScreen(document: LegalDocument.privacy),
  'Terms': const LegalScreen(document: LegalDocument.terms),
};

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen, {
  required bool signedIn,
  Size size = const Size(390, 844),
  double textScale = 1.0,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  if (signedIn) {
    // The mock takes a moment to "sign in", which the fake clock would never
    // let pass without real time.
    await tester.runAsync(
      () => container.read(authRepositoryProvider).signInAsDemo(),
    );
  }

  // Inside a router, as in the app: some screens navigate as they build.
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => screen)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: dark ? LizTheme.dark() : LizTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return container;
}

/// Unmount before disposing: cached providers hold timers that the container
/// cancels on dispose, and the framework checks for strays as the tree ends.
Future<void> _finish(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

void main() {
  for (final signedIn in [false, true]) {
    final who = signedIn ? 'signed in' : 'signed out';

    for (final entry in _screens.entries) {
      group('${entry.key}, $who', () {
        testWidgets('fits a 320-wide phone', (tester) async {
          final c = await _pump(
            tester,
            entry.value,
            signedIn: signedIn,
            size: const Size(320, 640),
          );
          expect(tester.takeException(), isNull);
          await _finish(tester, c);
        });

        testWidgets('survives text scaled to 1.5x', (tester) async {
          final c = await _pump(
            tester,
            entry.value,
            signedIn: signedIn,
            size: const Size(375, 812),
            textScale: 1.5,
          );
          expect(tester.takeException(), isNull);
          await _finish(tester, c);
        });

        testWidgets('fits a tablet in portrait', (tester) async {
          final c = await _pump(
            tester,
            entry.value,
            signedIn: signedIn,
            size: const Size(834, 1112),
          );
          expect(tester.takeException(), isNull);
          await _finish(tester, c);
        });

        for (final dark in [false, true]) {
          testWidgets(
            'meets the accessibility guidelines, ${dark ? 'dark' : 'light'}',
            (tester) async {
              final handle = tester.ensureSemantics();
              final c = await _pump(
                tester,
                entry.value,
                signedIn: signedIn,
                dark: dark,
              );
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              // 48x48 is the platform minimum for something a finger has to
              // hit. Theme-independent, so checked once.
              if (!dark) {
                await expectLater(
                  tester,
                  meetsGuideline(androidTapTargetGuideline),
                );
              }
              await _finish(tester, c);
              handle.dispose();
            },
          );
        }
      });
    }
  }
}
