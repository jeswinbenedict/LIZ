/// What a password and an email address have to look like before we bother
/// the server about them.
///
/// Kept apart from the screens so the rules can be argued with in a test, and
/// so the reset form and the sign-up form cannot drift into disagreeing about
/// what counts as a valid password.
library;

/// Deliberately permissive. A regex strict enough to reject every invalid
/// address also rejects real ones — plus-addressing, new top-level domains,
/// unicode — and being told your own email is wrong is worse than a bounced
/// message.
final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

String? validateEmail(String raw) {
  final email = raw.trim();
  if (email.isEmpty) return 'Enter your email address.';
  if (!_emailShape.hasMatch(email)) {
    return "That email address doesn't look right.";
  }
  return null;
}

/// The floor Supabase itself enforces. Matching it here means someone finds
/// out while they are typing rather than after a round trip.
const int minPasswordLength = 8;

/// Checks a new password, and its confirmation when one is given.
///
/// Length only. Composition rules — a digit, a symbol, mixed case — push
/// people towards `Password1!` and away from the long memorable phrases that
/// are actually harder to guess.
String? validateNewPassword(String password, {String? confirmation}) {
  if (password.isEmpty) return 'Choose a password.';
  if (password.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters.';
  }
  if (confirmation != null && password != confirmation) {
    return 'Those two passwords do not match.';
  }
  return null;
}
