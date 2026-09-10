import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/config/env.dart';

/// The share sheet used to say "Check out X on Liz" and then link to the
/// product's own website — sending people away from Liz — and when a tool had
/// no website it fell back to liz.app, a domain nobody owns.

void main() {
  test('a permalink routes the way the app actually routes', () {
    // The app reads the URL fragment, so a path-form link loads the home
    // screen and silently drops the tool.
    expect(Env.permalinkFrom('https://liz.example', 'x'), contains('/#/tool/'));
  });

  test('a permalink points at Liz, not at the product', () {
    expect(
      Env.permalinkFrom('https://liz.example', 'abc-123'),
      'https://liz.example/#/tool/abc-123',
    );
  });

  test('trailing slashes never survive into a link', () {
    // Two slashes look broken even when they resolve.
    for (final base in [
      'https://liz.example/',
      'https://liz.example///',
      '  https://liz.example/  ',
    ]) {
      expect(
        Env.permalinkFrom(base, 'abc'),
        'https://liz.example/#/tool/abc',
        reason: 'from "$base"',
      );
    }
  });

  test('no address means no link, rather than a broken one', () {
    expect(Env.permalinkFrom('', 'abc'), isNull);
    expect(Env.permalinkFrom('   ', 'abc'), isNull);
    expect(Env.permalinkFrom('https://liz.example', ''), isNull);
  });
}
