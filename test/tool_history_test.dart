import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/tool_detail/tool_history.dart';
import 'package:liz/shared/models/tool_history.dart';

import 'support/tools.dart';

/// The signal line draws only what moved, and only once there is enough
/// history to be a line; the timeline tells a tool's story from facts Liz
/// holds. History starts on 29 September 2026, so early on most tools have
/// one or two points — the honest thing is to draw nothing.

SignalPoint _p(int day, {int? stars, int? hn, int saves = 0, int views = 0}) =>
    SignalPoint(
      day: DateTime.utc(2026, 9, day),
      ghStars: stars,
      hnPoints: hn,
      saves: saves,
      views: views,
    );

void main() {
  test('fewer than three days is not a line', () {
    expect(SignalSeries.pick([_p(29, stars: 10), _p(30, stars: 20)]), isNull);
  });

  test('stars are drawn when they move', () {
    final s = SignalSeries.pick([
      _p(28, stars: 100),
      _p(29, stars: 120),
      _p(30, stars: 150),
    ])!;
    expect(s.label, 'GitHub stars');
    expect(s.values, [100, 120, 150]);
  });

  test('a line runs oldest to newest, whatever order the days arrive in', () {
    // The live query once returned newest first, and every rising tool was
    // drawn falling.
    final s = SignalSeries.pick([
      _p(30, stars: 150),
      _p(29, stars: 120),
      _p(28, stars: 100),
    ])!;
    expect(s.values, [100, 120, 150]);
    expect(s.last > s.first, isTrue);
  });

  test('flat stars give way to what did move', () {
    final s = SignalSeries.pick([
      _p(28, stars: 100, saves: 0),
      _p(29, stars: 100, saves: 1),
      _p(30, stars: 100, saves: 3),
    ])!;
    expect(s.label, 'Interest on Liz');
  });

  test('nothing moved, nothing drawn', () {
    expect(
      SignalSeries.pick([_p(28, hn: 5), _p(29, hn: 5), _p(30, hn: 5)]),
      isNull,
    );
  });

  testWidgets('the timeline runs newest first', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LizTheme.app(),
          home: Scaffold(
            body: ToolTimelineSection(
              tool: sampleTool(
                hnPoints: 228,
                hnPostedAt: DateTime.utc(2026, 9, 25, 14),
                createdAt: DateTime.utc(2026, 9, 26),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final seen = t.getTopLeft(find.text('First seen by Liz'));
    final launch = t.getTopLeft(
      find.text('Launched on Hacker News · 228 points'),
    );
    expect(
      seen.dy,
      lessThan(launch.dy),
      reason: 'seen on the 26th, launched the 25th',
    );
  });
}
