import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/auth/firebase_auth_repository.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(isSignedInProvider);
    final viaLink = (widget.resetCode ?? passwordResetCodeIn(Uri.base)) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: MaxWidth(
        maxWidth: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LizSpacing.lg),
          child: _done
              ? _Done(scheme: scheme, signedIn: signedIn)
              : !signedIn && !viaLink
              ? _Expired(scheme: scheme)
              : _form(scheme),
        ),
      ),
    );
  }

  Widget _form(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick something you will remember. Length beats punctuation — a '
          'short phrase is stronger than a word with symbols in it.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: !_reveal,
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _reveal ? 'Hide password' : 'Show password',
              icon: Icon(
                _reveal
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: !_reveal,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Set password'),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.scheme, required this.signedIn});
  final ColorScheme scheme;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
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
            children: [
              const Icon(Icons.check_circle_outline, color: LizColors.positive),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  signedIn
                      ? 'Password changed. You are signed in.'
                      : 'Password changed. Sign in with the new one.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go to Liz'),
        ),
      ],
    );
  }
}

/// No session means the link was stale, already used, or opened somewhere
/// other than where it was requested. Saying that is more useful than a form
/// that only fails once it is filled in.
class _Expired extends StatelessWidget {
  const _Expired({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: context.liz.caution.withValues(alpha: 0.10),
            shape: LizRadius.shape(LizRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link_off, color: context.liz.caution),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This link has expired',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reset links last an hour and work once. Ask for a new '
                      'one and it will arrive in a moment.',
                      style: TextStyle(color: context.liz.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/forgot-password'),
          child: const Text('Send a new link'),
        ),
      ],
    );
  }
}
