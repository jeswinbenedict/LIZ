import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import 'password_validation.dart';
import '../../shared/widgets/page_header.dart';

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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/signin'),
        ),
        title: const PageHeading('Reset your password'),
      ),
      body: MaxWidth(
        maxWidth: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LizSpacing.lg),
          child: _sent ? _Sent(email: _email.text.trim()) : _form(scheme),
        ),
      ),
    );
  }

  Widget _form(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the address you signed up with and we will send you a link '
          'to choose a new password.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _send(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send reset link'),
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: LizColors.positive.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(LizRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.mark_email_read_outlined,
                color: LizColors.positive,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Check your inbox',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If $email has an account, a reset link is on its way. '
                      'It expires in an hour.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Nothing arrived? Check spam, and make sure you typed the address '
          'you signed up with.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => context.go('/signin'),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
