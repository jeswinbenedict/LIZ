import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/states.dart';

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
            appBar: AppBar(title: const Text('Admin')),
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
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: MaxWidth(
        maxWidth: 520 + gutter * 2,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 40),
          children: [
            Icon(Icons.shield_outlined, size: 40, color: p.accent),
            const SizedBox(height: 16),
            Text(
              _settingUp
                  ? 'Set up two-step verification'
                  : 'Enter your verification code',
              style: LizText.title2.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              _settingUp
                  ? 'The admin console can publish and remove anything, so it '
                        'needs a code from an authenticator app as well as your '
                        'password. Scan this with Google Authenticator, 1Password, '
                        'Authy or any other, then enter the code it shows.'
                  : 'Open your authenticator app and enter the six-digit code '
                        'for Liz.',
              style: LizText.body.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 24),
            if (_settingUp && setup == null && _busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (setup != null) ...[
              Center(
                child: DecoratedBox(
                  // White behind the code in both themes: scanners read dark
                  // modules on a light ground.
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: LizRadius.shape(LizRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      label: 'QR code for your authenticator app',
                      child: QrImageView(data: setup.uri, size: 200),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Can\'t scan it? Enter this key instead:',
                style: LizText.footnote.copyWith(color: p.textSecondary),
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
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: setup.secret)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            if (!_settingUp || setup != null) ...[
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 7,
                decoration: InputDecoration(
                  labelText: 'Six-digit code',
                  counterText: '',
                  errorText: _error,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: LizButtons.capsule,
                onPressed: _busy ? null : _verify,
                child: Text(_busy ? 'Checking…' : 'Verify'),
              ),
            ] else if (_error != null) ...[
              Text(_error!, style: LizText.callout.copyWith(color: p.danger)),
              const SizedBox(height: 12),
              OutlinedButton(
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
