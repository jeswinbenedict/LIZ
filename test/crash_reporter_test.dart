import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/telemetry/crash_reporter.dart';

/// A crash reporter earns its place only if it groups repeats and refuses to
/// flood. A render loop can raise the same error every frame, and a client that
/// spends the session posting identical rows is its own outage.

void main() {
  setUp(CrashReporter.resetForTest);

  test('an image that will not load is not a crash', () {
    expect(
      CrashReporter.isExpected(
        FlutterErrorDetails(
          exception: Exception('Failed to create image from Image.decode'),
          library: 'image resource service',
        ),
      ),
      isTrue,
    );
    expect(
      CrashReporter.isExpected(
        FlutterErrorDetails(
          exception: StateError('boom'),
          library: 'widgets library',
        ),
      ),
      isFalse,
    );
  });

  group('fingerprinting', () {
    test('the same fault in the same place groups together', () {
      final stack = StackTrace.fromString(
        '#0 Foo.bar (package:liz/foo.dart:12:5)\n'
        '#1 Baz.qux (package:liz/baz.dart:44:9)',
      );
      expect(
        CrashReporter.fingerprintOf(StateError('boom'), stack),
        CrashReporter.fingerprintOf(StateError('boom'), stack),
      );
    });

    test('line numbers moving between builds does not split the group', () {
      final before = StackTrace.fromString(
        '#0 Foo.bar (package:liz/foo.dart:12:5)',
      );
      final after = StackTrace.fromString(
        '#0 Foo.bar (package:liz/foo.dart:98:2)',
      );

      expect(
        CrashReporter.fingerprintOf(StateError('boom'), before),
        CrashReporter.fingerprintOf(StateError('boom'), after),
        reason: 'the same bug after an unrelated edit is still one bug',
      );
    });

    test('different faults stay apart', () {
      final stack = StackTrace.fromString(
        '#0 Foo.bar (package:liz/foo.dart:12:5)',
      );
      expect(
        CrashReporter.fingerprintOf(StateError('boom'), stack),
        isNot(CrashReporter.fingerprintOf(ArgumentError('bad'), stack)),
      );
    });

    test('a different call site is a different fault', () {
      expect(
        CrashReporter.fingerprintOf(
          StateError('x'),
          StackTrace.fromString('#0 A.a (package:liz/a.dart:1:1)'),
        ),
        isNot(
          CrashReporter.fingerprintOf(
            StateError('x'),
            StackTrace.fromString('#0 B.b (package:liz/b.dart:1:1)'),
          ),
        ),
      );
    });

    test('a missing stack trace still produces a stable key', () {
      expect(
        CrashReporter.fingerprintOf(StateError('boom'), null),
        CrashReporter.fingerprintOf(StateError('boom'), null),
      );
      expect(CrashReporter.fingerprintOf(StateError('boom'), null), isNotEmpty);
    });
  });

  group('reporting', () {
    test('never throws, whatever it is handed', () async {
      // Errors during reporting must not become a second failure for the user.
      await expectLater(
        CrashReporter.report(StateError('boom'), StackTrace.current),
        completes,
      );
      await expectLater(CrashReporter.report('a bare string', null), completes);
    });

    test('reports nothing when there is no backend to report to', () async {
      // Tests run without Supabase credentials, so this is the mock-mode path.
      await CrashReporter.report(StateError('boom'), StackTrace.current);
      expect(CrashReporter.sentCount, 0);
    });
  });
}
