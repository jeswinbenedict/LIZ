import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/enabled_providers.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import 'auth_controller.dart';

/// Shared sign-in UI used by both the full [SignInScreen] and the modal sheet.
/// Reflects the "explore first" principle — this only appears when an identity
/// action needs it.
class SignInView extends ConsumerStatefulWidget {
  const SignInView({super.key, this.onSignedIn, this.prompt});

  /// Called after a successful sign-in (e.g. to pop a sheet and retry).
  final VoidCallback? onSignedIn;
  final String? prompt;

  @override
  ConsumerState<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<SignInView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Supabase enforces all of this server-side, but a round trip to be told
  /// "invalid credentials" for an empty box is a poor way to learn you left one
  /// blank. Returns the first problem, or null when the form can be submitted.
  ///
  /// Deliberately permissive on the address: the only definitive test of an
  /// email is sending to it, and an over-strict pattern rejects valid ones.
  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(email)) {
      return "That email address doesn't look right.";
    }
    if (_password.text.isEmpty) return 'Enter your password.';
    if (_isSignUp) {
      if (_password.text.length < 6) {
        return 'Use a password of at least 6 characters.';
      }
      if (_name.text.trim().isEmpty) {
        return 'Enter a display name so people know who you are.';
      }
    }
    return null;
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted && ref.read(isSignedInProvider)) widget.onSignedIn?.call();
    } on TwoStepRequiredException {
      // The password was right; the account also wants a code.
      final done = mounted && await showTwoStepCodeDialog(context) == true;
      if (done && mounted && ref.read(isSignedInProvider)) {
        widget.onSignedIn?.call();
      }
    } on LizException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Opens another page from this view.
  ///
  /// This view is shown both as a bottom sheet and as a full page. A sheet has
  /// to be dismissed first or it covers the screen being pushed; a page must
  /// not be — it is where Back should return to. onSignedIn cannot tell the two
  /// apart: on the page it means "signed in, leave", which is how the reset
  /// link first sent people to Discover. [keepSheet] is for pages that are
  /// read and closed, where dismissing would throw away the half-filled form;
  /// those push above the sheet on the root navigator instead.
  void _openPage(String path, {bool keepSheet = false}) {
    if (!keepSheet && ModalRoute.of(context) is PopupRoute) {
      Navigator.of(context).pop();
    }
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final isLive = ref.watch(isLiveBackendProvider);
    final scheme = Theme.of(context).colorScheme;
    // While this resolves, and if it fails, no social buttons are shown: the
    // email form below is a complete sign-in on its own.
    final providers =
        ref.watch(enabledAuthProvidersProvider).value ??
        EnabledAuthProviders.none;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(LizSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _isSignUp ? 'Create your account' : 'Welcome to Liz',
              style: LizText.title1.copyWith(color: context.liz.textPrimary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.prompt ??
                'Sign in to save tools, post, and follow what you love.',
            style: LizText.body.copyWith(color: context.liz.textSecondary),
          ),
          const SizedBox(height: LizSpacing.lg),

          // Only the providers this project has enabled. Offering one that is
          // switched off dead-ends on Supabase's raw error JSON.
          if (providers.google) ...[
            _SocialButton(
              icon: Icons.g_mobiledata,
              label: 'Continue with Google',
              onPressed: busy ? null : () => _guard(auth.signInWithGoogle),
            ),
          ],
          if (providers.apple && shouldOfferApple) ...[
            if (providers.google) const SizedBox(height: 10),
            _SocialButton(
              icon: Icons.apple,
              label: 'Continue with Apple',
              onPressed: busy ? null : () => _guard(auth.signInWithApple),
            ),
          ],
          // A lone "or" above the email form reads as a missing button.
          if (providers.hasSocial) ...[
            const SizedBox(height: LizSpacing.md),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: LizSpacing.md),
          ],

          if (_isSignUp) ...[
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _Message(text: _error!, color: context.liz.danger),
          ],
          if (_info != null) ...[
            const SizedBox(height: 12),
            _Message(text: _info!, color: context.liz.positive),
          ],

          const SizedBox(height: LizSpacing.md),
          FilledButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
            ),
            onPressed: busy
                ? null
                : () {
                    final problem = _validate();
                    if (problem != null) {
                      setState(() {
                        _error = problem;
                        _info = null;
                      });
                      return;
                    }
                    _guard(() async {
                      if (_isSignUp) {
                        await auth.signUp(
                          _email.text.trim(),
                          _password.text,
                          _name.text.trim(),
                        );
                      } else {
                        await auth.signInWithEmail(
                          _email.text.trim(),
                          _password.text,
                        );
                      }
                    });
                  },
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isSignUp ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 8),
          // Say what signing up agrees to before it happens, and let it be
          // read without losing what has been typed into the form.
          if (_isSignUp)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'By creating an account you agree to the',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: () => _openPage('/terms', keepSheet: true),
                  child: const Text('Terms'),
                ),
                Text('and', style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () => _openPage('/privacy', keepSheet: true),
                  child: const Text('Privacy policy'),
                ),
              ],
            ),
          if (!_isSignUp)
            TextButton(
              onPressed: busy || _email.text.trim().isEmpty
                  ? null
                  : () => _guard(() async {
                      await auth.sendMagicLink(_email.text.trim());
                      if (mounted) {
                        setState(
                          () => _info = 'Magic link sent — check your email.',
                        );
                      }
                    }),
              child: const Text('Email me a magic link'),
            ),
          // The moment someone needs this is the moment a password fails, so
          // it belongs here rather than behind a help page.
          if (!_isSignUp)
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      final email = _email.text.trim();
                      _openPage(
                        email.isEmpty
                            ? '/forgot-password'
                            : '/forgot-password?email='
                                  '${Uri.encodeQueryComponent(email)}',
                      );
                    },
              child: const Text('Forgot your password?'),
            ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() => _isSignUp = !_isSignUp),
            child: Text(
              _isSignUp
                  ? 'Already have an account? Sign in'
                  : "New here? Create an account",
            ),
          ),

          if (!isLive) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _guard(auth.signInAsDemo),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Skip — continue as demo user'),
            ),
            const SizedBox(height: 6),
            Text(
              'Running in demo mode (no backend connected). All actions work locally.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// A form message — an error or a confirmation — as a tinted panel, so it
/// reads as the form's answer rather than as stray coloured text.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final fill = Color.alphaBlend(color.withValues(alpha: 0.10), p.surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: fill,
        shape: LizRadius.shape(LizRadius.sm),
      ),
      child: Text(
        text,
        style: LizText.callout.copyWith(
          color: LizColors.legibleOn(color, fill),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        alignment: Alignment.center,
      ),
    );
  }
}

/// Shows the sign-in sheet and resolves true if the user ends up signed in.
Future<bool> showSignInSheet(BuildContext context, {String? prompt}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
          maxWidth: 480,
        ),
        child: SignInView(
          prompt: prompt,
          onSignedIn: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
  return context.mounted &&
      ProviderScope.containerOf(context).read(isSignedInProvider);
}

/// Asks for the six-digit code of an account with two-step verification, and
/// finishes the sign-in with it. True once signed in.
Future<bool?> showTwoStepCodeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TwoStepCodeDialog(),
  );
}

class _TwoStepCodeDialog extends ConsumerStatefulWidget {
  const _TwoStepCodeDialog();

  @override
  ConsumerState<_TwoStepCodeDialog> createState() => _TwoStepCodeDialogState();
}

class _TwoStepCodeDialogState extends ConsumerState<_TwoStepCodeDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeTwoStepSignIn(code);
      if (mounted) Navigator.of(context).pop(true);
    } on LizException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Two-step verification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter the code from your authenticator app.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(
              labelText: 'Code',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
