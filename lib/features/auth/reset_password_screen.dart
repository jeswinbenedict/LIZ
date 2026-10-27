import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/firebase_auth_repository.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/liz_notice.dart';
import 'auth_frame.dart';
import 'password_validation.dart';

/// Where a reset link lands: choose the new password.
///
/// Two ways to arrive: from a Firebase reset link, when its emails point here
/// (Firebase console → Authentication → Templates → custom action URL), with
/// the reset code in the address; or signed in, to change the password. With
/// neither, the link was stale or opened somewhere else, and saying so is more
/// useful than a form that fails on submit.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.resetCode});

  /// The code from a reset link; read from the address when not given.
  final String? resetCode;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  bool _reveal = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = validateNewPassword(
      _password.text,
      confirmation: _confirm.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (mounted) setState(() => _done = true);
    } on LizException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not set the password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final viaLink = (widget.resetCode ?? passwordResetCodeIn(Uri.base)) != null;

    return AuthFrame(
      child: _done
          ? _Done(signedIn: signedIn)
          : !signedIn && !viaLink
          ? const _Expired()
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'Choose a new password',
          subtitle:
              'Pick something you will remember. Length beats punctuation — '
              'a short phrase is stronger than a word with symbols in it.',
        ),
        const SizedBox(height: LizSpacing.lg),
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: !_reveal,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            helperText: 'At least $minPasswordLength characters.',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _reveal ? 'Hide password' : 'Show password',
              icon: Icon(
                _reveal
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: !_reveal,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          LizNotice(text: _error!, color: p.danger, icon: Icons.error_outline),
        ],
        const SizedBox(height: LizSpacing.md),
        AuthSubmitButton(
          label: 'Set password',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeading(
          title: 'Password changed',
          subtitle: signedIn
              ? 'You are signed in with the new one.'
              : 'Sign in with the new one.',
        ),
        const SizedBox(height: LizSpacing.lg),
        AuthSubmitButton(
          label: signedIn ? 'Go to Liz' : 'Sign in',
          onPressed: () => context.go(signedIn ? '/' : '/signin'),
        ),
      ],
    );
  }
}

/// No session means the link was stale, already used, or opened somewhere
/// other than where it was requested. Saying that is more useful than a form
/// that only fails once it is filled in.
class _Expired extends StatelessWidget {
  const _Expired();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'This link has expired',
          subtitle:
              'Reset links last an hour and work once. Ask for a new one and '
              'it will arrive in a moment.',
        ),
        const SizedBox(height: LizSpacing.lg),
        AuthSubmitButton(
          label: 'Send a new link',
          onPressed: () => context.go('/forgot-password'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: () => context.go('/signin'),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
