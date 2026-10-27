import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/liz_notice.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/top_bar.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_frame.dart';

/// Where this session stands with two-step verification. Re-read after a
/// code is accepted.
final twoStepProvider = FutureProvider.autoDispose<TwoStep>(
  (ref) => ref.watch(authRepositoryProvider).twoStep(),
);

/// Stands in front of the admin console until this session has passed a code
/// check (migration 0042). With a password alone, a phished moderator account
/// could publish anything.
class TwoStepGate extends ConsumerWidget {
  const TwoStepGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(twoStepProvider)
        .when(
          loading: () => const Scaffold(body: LoadingView()),
          error: (_, _) => Scaffold(
            appBar: const LizTopBar(
              title: 'Admin console',
              section: ('Profile', '/profile'),
              fallback: '/profile',
            ),
            body: ErrorView(onRetry: () => ref.invalidate(twoStepProvider)),
          ),
          data: (state) => state.status == TwoStepStatus.verified
              ? child
              : _TwoStepPage(state: state),
        );
  }
}

class _TwoStepPage extends ConsumerStatefulWidget {
  const _TwoStepPage({required this.state});
  final TwoStep state;

  @override
  ConsumerState<_TwoStepPage> createState() => _TwoStepPageState();
}

class _TwoStepPageState extends ConsumerState<_TwoStepPage> {
  final _code = TextEditingController();
  TotpSetup? _setup;
  String? _error;
  bool _busy = false;
  bool _signInAgain = false;

  bool get _settingUp => widget.state.status == TwoStepStatus.needsSetup;

  @override
  void initState() {
    super.initState();
    if (_settingUp) _startSetup();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() => _busy = true);
    try {
      final setup = await ref.read(authRepositoryProvider).startTwoStepSetup();
      if (mounted) setState(() => _setup = setup);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _signInAgain = e is RecentSignInRequiredException;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signing out here lands on the sign-in page, which comes back to the
  /// console afterwards (auth_gate.dart).
  Future<void> _freshSignIn() =>
      ref.read(authControllerProvider.notifier).signOut();

  Future<void> _verify() async {
    final factorId = _setup?.factorId ?? widget.state.factorId;
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (factorId == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the six digits your app shows.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyTwoStep(factorId, code);
      ref.invalidate(twoStepProvider);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) =>
      e is LizException ? e.message : 'Something went wrong. Try again.';

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final setup = _setup;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final phone = context.isPhone;
    final showCode = !_settingUp || setup != null;

    return Scaffold(
      appBar: const LizTopBar(
        title: 'Two-step verification',
        section: ('Profile', '/profile'),
        fallback: '/profile',
        titleIsHeading: false,
      ),
      body: MaxWidth(
        maxWidth: 520 + gutter * 2,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, phone ? 16 : 48, gutter, 48),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: ShapeDecoration(
                  color: p.surfaceHover,
                  shape: LizRadius.shape(
                    LizRadius.md,
                    side: BorderSide(color: p.hairlineStrong),
                  ),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: 24,
                  color: p.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              container: true,
              header: true,
              headingLevel: 1,
              child: Text(
                _settingUp
                    ? 'Set up two-step verification'
                    : 'Enter your verification code',
                style: (phone ? LizText.title1 : LizText.largeTitle).copyWith(
                  color: p.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _settingUp
                  ? 'The admin console can publish and remove anything, so it '
                        'needs a code from an authenticator app as well as your '
                        'password. Google Authenticator, 1Password, Authy or '
                        'any other will do.'
                  : 'Open your authenticator app and enter the six-digit code '
                        'for Liz.',
              style: LizText.body.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 28),
            if (_settingUp && setup == null && _busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (setup != null) ...[
              const _StepHeading(number: 1, text: 'Scan this code'),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.surface,
                  shape: LizRadius.shape(
                    LizRadius.md,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: DecoratedBox(
                          // White behind the code in both themes: scanners
                          // read dark modules on a light ground.
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: LizRadius.shape(LizRadius.md),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Semantics(
                              label: 'QR code for your authenticator app',
                              child: QrImageView(data: setup.uri, size: 184),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: p.hairline),
                      const SizedBox(height: 12),
                      Text(
                        'Can’t scan it? Enter this key instead:',
                        style: LizText.footnote.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              setup.secret,
                              style: LizText.callout.copyWith(
                                color: p.textPrimary,
                                fontFeatures: LizText.tabular,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy key',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: setup.secret),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _StepHeading(number: 2, text: 'Enter the code it shows'),
              const SizedBox(height: 12),
            ],
            if (showCode) ...[
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 7,
                decoration: const InputDecoration(
                  labelText: 'Six-digit code',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                LizNotice(
                  text: _error!,
                  color: p.danger,
                  icon: Icons.error_outline,
                ),
              ],
              const SizedBox(height: 16),
              AuthSubmitButton(
                label: 'Verify',
                busy: _busy,
                onPressed: _verify,
              ),
            ] else if (_error != null) ...[
              LizNotice(
                text: _error!,
                color: p.danger,
                icon: Icons.error_outline,
              ),
              const SizedBox(height: 16),
              if (_signInAgain)
                AuthSubmitButton(
                  label: 'Sign in again',
                  onPressed: _freshSignIn,
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _startSetup,
                  child: const Text('Try again'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "1  Scan this code": a step's number in a ring, and what to do.
class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      container: true,
      header: true,
      label: 'Step $number: $text',
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.hairlineStrong),
            ),
            child: Text(
              '$number',
              style: LizText.footnote.copyWith(
                color: p.textPrimary,
                fontFeatures: LizText.tabular,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: LizText.headline.copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }
}
