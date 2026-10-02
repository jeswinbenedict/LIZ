import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/enabled_providers.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/google_logo.dart';
import '../../shared/widgets/page_header.dart';
import 'auth_controller.dart';
import 'password_validation.dart';

/// The sign-in form, used by the full [SignInScreen] and by the sheet that
/// opens when a visitor does something that needs an account. It only ever
/// appears when an identity action needs it ("explore first").
///
/// One form for both ways in — a switch at the top chooses signing in or
/// creating an account — with the details a web form is judged on: Enter
/// submits, password managers fill it, the password can be shown, the error
/// is read out, and the way back from a forgotten password sits next to the
/// password field rather than under the button.
class SignInView extends ConsumerStatefulWidget {
  const SignInView({
    super.key,
    this.onSignedIn,
    this.prompt,
    this.padding = const EdgeInsets.all(LizSpacing.lg),
  });

  /// Called after a successful sign-in (e.g. to pop a sheet and retry).
  final VoidCallback? onSignedIn;

  /// Why sign-in is being asked for, in place of the default line.
  final String? prompt;

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<SignInView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    // The magic-link button depends on there being an address.
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The server enforces all of this, but a round trip to be told "invalid
  /// credentials" for an empty box is a poor way to learn you left one blank.
  /// Returns the first problem, or null when the form can be submitted.
  String? _validate() {
    final emailProblem = validateEmail(_email.text);
    if (emailProblem != null) return emailProblem;
    if (_isSignUp) {
      if (_name.text.trim().isEmpty) {
        return 'Enter a display name so people know who you are.';
      }
      return validateNewPassword(_password.text);
    }
    if (_password.text.isEmpty) return 'Enter your password.';
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
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    }
  }

  void _submit() {
    if (ref.read(authControllerProvider)) return;
    final problem = _validate();
    if (problem != null) {
      setState(() {
        _error = problem;
        _info = null;
      });
      return;
    }
    final auth = ref.read(authControllerProvider.notifier);
    _guard(() async {
      if (_isSignUp) {
        await auth.signUp(
          _email.text.trim(),
          _password.text,
          _name.text.trim(),
        );
      } else {
        await auth.signInWithEmail(_email.text.trim(), _password.text);
      }
      // Lets the browser's password manager offer to save what was typed.
      TextInput.finishAutofillContext();
    });
  }

  void _setMode(bool signUp) {
    if (signUp == _isSignUp) return;
    setState(() {
      _isSignUp = signUp;
      _error = null;
      _info = null;
    });
  }

  /// Opens another page from this view.
  ///
  /// This view is shown both as a bottom sheet and as a full page. A sheet has
  /// to be dismissed first or it covers the screen being pushed; a page must
  /// not be — it is where Back should return to. [keepSheet] is for pages that
  /// are read and closed, where dismissing would throw away the half-filled
  /// form; those push above the sheet on the root navigator instead.
  void _openPage(String path, {bool keepSheet = false}) {
    if (!keepSheet && ModalRoute.of(context) is PopupRoute) {
      Navigator.of(context).pop();
    }
    context.push(path);
  }

  void _forgotPassword() {
    final email = _email.text.trim();
    _openPage(
      email.isEmpty
          ? '/forgot-password'
          : '/forgot-password?email=${Uri.encodeQueryComponent(email)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final busy = ref.watch(authControllerProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final isLive = ref.watch(isLiveBackendProvider);
    // While this resolves, and if it fails, no social buttons are shown: the
    // email form below is a complete sign-in on its own.
    final providers =
        ref.watch(enabledAuthProvidersProvider).value ??
        EnabledAuthProviders.none;
    final small = LizText.footnote.copyWith(color: p.textSecondary);

    return SingleChildScrollView(
      padding: widget.padding,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                _isSignUp ? 'Create your account' : 'Welcome back',
                style: LizText.title1.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.prompt ??
                  (_isSignUp
                      ? 'Save tools, get alerts when they move, and write '
                            'reviews.'
                      : 'Sign in to your saved tools and alerts.'),
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: LizSpacing.lg),
            LizSegmented<bool>(
              segments: const {false: 'Sign in', true: 'Create account'},
              value: _isSignUp,
              onChanged: busy ? (_) {} : _setMode,
              expand: true,
            ),
            const SizedBox(height: LizSpacing.md),

            // Only the providers this project offers. A switched-off one
            // dead-ends on an error.
            if (providers.google)
              _ProviderButton(
                mark: const GoogleLogo(),
                label: 'Continue with Google',
                onPressed: busy ? null : () => _guard(auth.signInWithGoogle),
              ),
            if (providers.apple && shouldOfferApple) ...[
              if (providers.google) const SizedBox(height: 10),
              _ProviderButton(
                mark: Icon(Icons.apple, size: 20, color: p.textPrimary),
                label: 'Continue with Apple',
                onPressed: busy ? null : () => _guard(auth.signInWithApple),
              ),
            ],
            // A lone "or" above the email form reads as a missing button.
            if (providers.hasSocial) ...[
              const SizedBox(height: LizSpacing.md),
              Row(
                children: [
                  Expanded(child: Divider(color: p.hairline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR WITH EMAIL',
                      style: LizText.label.copyWith(color: p.textSecondary),
                    ),
                  ),
                  Expanded(child: Divider(color: p.hairline)),
                ],
              ),
              const SizedBox(height: LizSpacing.md),
            ],

            if (_isSignUp) ...[
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
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
              autocorrect: false,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _isSignUp
                    ? 'At least $minPasswordLength characters. A phrase '
                          'works well.'
                    : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            // The moment someone needs this is the moment a password fails,
            // so it sits under the field rather than behind a help page.
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _forgotPassword,
                  child: const Text('Forgot your password?'),
                ),
              )
            else
              const SizedBox(height: 4),

            if (_error != null) ...[
              const SizedBox(height: 8),
              _Message(
                text: _error!,
                color: p.danger,
                icon: Icons.error_outline,
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 8),
              _Message(
                text: _info!,
                color: p.positive,
                icon: Icons.check_circle_outline,
              ),
            ],

            const SizedBox(height: LizSpacing.md),
            FilledButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(50)),
              ),
              onPressed: busy ? null : _submit,
              child: busy
                  ? Semantics(
                      label: 'Working',
                      child: const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
                  Text('By creating an account you agree to the', style: small),
                  TextButton(
                    onPressed: () => _openPage('/terms', keepSheet: true),
                    child: const Text('Terms'),
                  ),
                  Text('and', style: small),
                  TextButton(
                    onPressed: () => _openPage('/privacy', keepSheet: true),
                    child: const Text('Privacy policy'),
                  ),
                ],
              )
            else
              TextButton(
                onPressed: busy || _email.text.trim().isEmpty
                    ? null
                    : () => _guard(() async {
                        await auth.sendMagicLink(_email.text.trim());
                        if (mounted) {
                          setState(
                            () => _info =
                                'Sign-in link sent. Open it in this browser.',
                          );
                        }
                      }),
                child: const Text('Email me a sign-in link instead'),
              ),

            if (!isLive) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _guard(auth.signInAsDemo),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Skip — continue as demo user'),
              ),
              const SizedBox(height: 6),
              Text(
                'Running in demo mode (no backend connected). All actions '
                'work locally.',
                textAlign: TextAlign.center,
                style: small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A form message — an error or a confirmation — as a tinted panel with an
/// icon, announced to screen readers when it appears.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final fill = Color.alphaBlend(color.withValues(alpha: 0.10), p.surface);
    final ink = LizColors.legibleOn(color, fill);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: fill,
          shape: LizRadius.shape(
            LizRadius.sm,
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: LizText.callout.copyWith(color: ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Continue with …": an outlined button with the provider's own mark.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.mark,
    required this.label,
    this.onPressed,
  });
  final Widget mark;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(child: SizedBox.square(dimension: 20, child: mark)),
          const SizedBox(width: 12),
          Text(label),
        ],
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
