import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/core/repository/repositories.dart';
import 'package:liz/core/telemetry/crash_reporter.dart';
import 'package:liz/features/admin/health_tab.dart';

/// Monitoring is only worth having if a failure is visible at a glance and a
/// crash says where it happened.

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LizTheme.app(),
        // In the app this sits inside the admin Scaffold; ListTile needs the
        // Material that provides.
        home: const Scaffold(body: HealthTab()),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  group('the panel', () {
    testWidgets('leads with a verdict, not a table to scan', (tester) async {
      await _pump(tester);

      // The mock health set has a warning and nothing failing.
      expect(find.textContaining('nothing failing'), findsOneWidget);
    });

    testWidgets('shows each signal with its measurement', (tester) async {
      await _pump(tester);

      expect(find.textContaining('Catalog freshness'), findsOneWidget);
      expect(find.textContaining('AI summary coverage'), findsOneWidget);
      // Percentages read as whole numbers when they are whole.
      expect(find.text('71'), findsOneWidget);
    });

    testWidgets('separates "the job ran" from "the work landed"', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Scheduled jobs'), findsOneWidget);
      expect(find.text('fetch-news-hourly'), findsOneWidget);
      // The distinction is the whole point of showing both.
      expect(find.textContaining('whether the work landed'), findsOneWidget);
    });

    testWidgets('says so plainly when there are no crashes', (tester) async {
      await _pump(tester);

      // Below the signal tiles: scroll to it, as an admin would.
      await tester.scrollUntilVisible(find.text('Nothing reported.'), 200);
      expect(find.text('Nothing reported.'), findsOneWidget);
    });
  });

  group('signal labels', () {
    test('read as words rather than column names', () {
      const cases = {
        'catalog_freshness_hours': 'catalog freshness (hours)',
        'ai_summary_coverage_pct': 'ai summary coverage %',
        'client_errors_24h': 'client errors (24h)',
        'open_reports': 'open reports',
      };
      for (final entry in cases.entries) {
        final signal = HealthSignal(
          signal: entry.key,
          status: 'ok',
          value: 0,
          detail: '',
        );
        expect(signal.label, entry.value);
      }
    });
  });

  group('crash reports', () {
    setUp(CrashReporter.resetForTest);

    test('carry the screen the reader was on', () async {
      CrashReporter.currentRoute = '/tool/abc';
      expect(CrashReporter.routeForTest, '/tool/abc');
    });

    test('group repeats of one fault under a single fingerprint', () {
      final stack = StackTrace.fromString(
        '#0      Foo.bar (package:liz/foo.dart:12:5)\n'
        '#1      Baz.qux (package:liz/baz.dart:40:9)',
      );
      // The same fault at a different line is still the same fault: line
      // numbers move between builds and would otherwise split one problem
      // into a new group on every release.
      final moved = StackTrace.fromString(
        '#0      Foo.bar (package:liz/foo.dart:18:5)\n'
        '#1      Baz.qux (package:liz/baz.dart:44:9)',
      );

      expect(
        CrashReporter.fingerprintOf(StateError('x'), stack),
        CrashReporter.fingerprintOf(StateError('x'), moved),
      );
      expect(
        CrashReporter.fingerprintOf(StateError('x'), stack),
        isNot(CrashReporter.fingerprintOf(ArgumentError('x'), stack)),
      );
    });
  });
}
