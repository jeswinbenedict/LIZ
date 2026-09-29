import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/config/env.dart';
import 'package:liz/shared/widgets/tool_link.dart';

import 'support/tools.dart';

/// The share sheet used to say "Check out X on Liz" and then link to the
/// product's own website — sending people away from Liz — and when a tool had
/// no website it fell back to liz.app, a domain nobody owns.

void main() {
  test('a permalink is a clean path, the way the app now routes', () {
    // The app used the URL fragment (/#/tool/<id>) until it moved to path
    // URLs; a fragment link would now be rewritten by index.html, but a link
    // Liz hands out should not need rewriting.
    final link = Env.permalinkFrom('https://liz.example', '/tools/elevenlabs');
    expect(link, 'https://liz.example/tools/elevenlabs');
    expect(link, isNot(contains('#')));
  });

  test('a tool is addressed by its slug, and by id only without one', () {
    expect(toolPath(sampleTool(slug: 'elevenlabs')), '/tools/elevenlabs');
    expect(toolPath(sampleTool(id: 'abc', slug: '')), '/tool/abc');
  });

  test('trailing slashes never survive into a link', () {
    // Two slashes look broken even when they resolve.
    for (final base in [
      'https://liz.example/',
      'https://liz.example///',
      '  https://liz.example/  ',
    ]) {
      expect(
        Env.permalinkFrom(base, '/tools/abc'),
        'https://liz.example/tools/abc',
        reason: 'from "$base"',
      );
    }
  });

  test('no address means no link, rather than a broken one', () {
    expect(Env.permalinkFrom('', '/tools/abc'), isNull);
    expect(Env.permalinkFrom('   ', '/tools/abc'), isNull);
    expect(Env.permalinkFrom('https://liz.example', ''), isNull);
    expect(Env.permalinkFrom('https://liz.example', '/'), isNull);
  });
}
