/// Thrown by repositories when a guest attempts an identity action
/// (save / post / review / follow). The UI catches this to present the
/// sign-in sheet, then retries — implementing "explore first, log in only
/// when identity is needed".
class AuthRequiredException implements Exception {
  const AuthRequiredException([this.message = 'Sign in to continue']);
  final String message;
  @override
  String toString() => message;
}

/// A user-facing failure with a friendly message.
class LizException implements Exception {
  const LizException(this.message);
  final String message;
  @override
  String toString() => message;
}
