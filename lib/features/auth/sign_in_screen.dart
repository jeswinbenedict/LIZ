import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/auth_gate.dart' show safeReturnPath;
import 'auth_frame.dart';
import 'sign_in_view.dart';

/// The sign-in page (`/signin`), in the Signal look (docs/DESIGN.md): the
/// form in the account pages' frame — a brand panel beside it on a wide
/// window, the wordmark above it on a narrow one.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, this.returnTo});

  /// The page the visitor asked for before the sign-in wall sent them here.
  final String? returnTo;

  /// From this width the brand panel has room beside a full-width form.
  static const splitWidth = AuthFrame.splitWidth;

  /// Back to where they were going. The router would get there too once it
  /// sees the session; going now saves a frame of the form after success.
  void _done(BuildContext context) {
    context.go(safeReturnPath(returnTo)?.toString() ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      scrolls: true,
      child: SignInView(
        onSignedIn: () => _done(context),
        padding: AuthFrame.formPadding(context),
      ),
    );
  }
}
