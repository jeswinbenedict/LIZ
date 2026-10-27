import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import 'auth_frame.dart';
import 'password_validation.dart';

/// Asks for the address to send a reset link to.
///
/// Until now a forgotten password had no route back in at all: the repository
/// had no reset method and no screen offered one. The only recovery was a
/// magic link, which needs an SMTP provider that is not configured either.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = validateEmail(_email.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on LizException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Once sent, the way back is the button under the message.
          if (!_sent) ...[const AuthBackLink(), const SizedBox(height: 12)],
          if (_sent) _Sent(email: _email.text.trim()) else _form(context),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'Reset your password',
          subtitle:
              'Enter the address you signed up with and we will send you a '
              'link to choose a new password.',
        ),
        const SizedBox(height: LizSpacing.lg),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _busy ? null : _send(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AuthMessage(
            text: _error!,
            color: p.danger,
            icon: Icons.error_outline,
          ),
        ],
        const SizedBox(height: LizSpacing.md),
        AuthSubmitButton(
          label: 'Send reset link',
          busy: _busy,
          onPressed: _send,
        ),
      ],
    );
  }
}

/// The confirmation.
///
/// Says the same thing whether or not an account exists at that address.
/// Telling someone "no account found" turns this form into a way to check who
/// has one, and a reset form is exactly where a person would go looking.
class _Sent extends StatelessWidget {
  const _Sent({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          title: 'Check your inbox',
          subtitle: 'The link to choose a new password is on its way.',
        ),
        const SizedBox(height: LizSpacing.lg),
        AuthMessage(
          text:
              'If $email has an account, a reset link is on its way. '
              'It expires in an hour.',
          color: p.positive,
          icon: Icons.mark_email_read_outlined,
        ),
        const SizedBox(height: 16),
        Text(
          'Nothing arrived? Check spam, and make sure you typed the address '
          'you signed up with.',
          style: LizText.footnote.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: LizSpacing.lg),
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
