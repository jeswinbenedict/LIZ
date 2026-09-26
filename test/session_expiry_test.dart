import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/auth/session_expiry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tokens last an hour and Liz is the kind of thing left open in a tab, so a
/// session dying mid-use is an ordinary Tuesday. It used to surface as
/// "Something went wrong", with no hint that signing in again was the fix.

void main() {
  group('is the session gone', () {
    test('a 401 or 403 from auth counts', () {
      expect(
        isSessionExpired(AuthException('nope', statusCode: '401')),
        isTrue,
      );
      expect(
        isSessionExpired(AuthException('nope', statusCode: '403')),
        isTrue,
      );
    });

    test('the phrasings Supabase actually uses count', () {
      for (final message in [
        'JWT expired',
        'Token is expired',
        'invalid claim: missing sub claim',
        'Session from session_id claim in JWT does not exist',
        'Refresh Token Not Found',
      ]) {
        expect(
          isSessionExpired(AuthException(message)),
          isTrue,
          reason: message,
        );
      }
    });

    test("PostgREST's own code for a dead token counts", () {
      expect(
        isSessionExpired(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        isTrue,
      );
    });

    test('a 401 from an edge function counts', () {
      expect(isSessionExpired(const FunctionException(status: 401)), isTrue);
    });
  });

  group('is not the session gone', () {
    test('row-level security refusing a valid session does not count', () {
      // 42501 is RLS saying no to something signing in again cannot fix.
      // Treating it as expiry would send someone round a loop.
      expect(
        isSessionExpired(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ),
        isFalse,
      );
    });

    test('an ordinary failure does not count', () {
      expect(isSessionExpired(Exception('network unreachable')), isFalse);
      expect(isSessionExpired(const FunctionException(status: 500)), isFalse);
      expect(isSessionExpired(const FunctionException(status: 429)), isFalse);
      expect(
        isSessionExpired(
          const PostgrestException(message: 'duplicate key', code: '23505'),
        ),
        isFalse,
      );
    });

    test('a validation error mentioning a token does not count', () {
      expect(
        isSessionExpired(Exception('token must be 6 characters')),
        isFalse,
      );
    });
  });
}
