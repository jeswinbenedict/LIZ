import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/auth_gate.dart' show safeReturnPath;
import '../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../app/theme.dart';
import '../../shared/widgets/signal_sparkline.dart';
import 'sign_in_view.dart';

/// The sign-in page (`/signin`), in the Signal look (docs/DESIGN.md).
///
/// Wide windows — most visitors, on a desktop browser — get two halves: a
/// brand panel that says what Liz is and shows a preview of it, and a quiet
/// column with the form. Narrow windows get the wordmark and the form alone:
/// on a phone the panel would only push the form below the fold.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, this.returnTo});

  /// The page the visitor asked for before the sign-in wall sent them here.
  final String? returnTo;

  /// From this width the brand panel has room beside a full-width form.
  static const splitWidth = 960.0;

  /// Back to where they were going. The router would get there too once it
  /// sees the session; going now saves a frame of the form after success.
  void _done(BuildContext context) {
    context.go(safeReturnPath(returnTo)?.toString() ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final wide = MediaQuery.sizeOf(context).width >= splitWidth;
    final form = _FormColumn(onSignedIn: () => _done(context));

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(flex: 11, child: _BrandPanel()),
                  Expanded(flex: 9, child: form),
                ],
              )
            : form,
      ),
    );
  }
}

/// The form side: the form centred in a 420 column, and the legal links at the
/// foot. No close button: every page is behind sign-in, so there is nowhere
/// to close to.
class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.onSignedIn});
  final VoidCallback onSignedIn;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final wide = MediaQuery.sizeOf(context).width >= SignInScreen.splitWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Row(
            children: [
              // On a wide window the wordmark is in the brand panel.
              if (!wide) const LizWordmark(size: 24),
              const Spacer(),
            ],
          ),
        ),
        if (!wide) Divider(height: 1, color: p.hairline),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _Entrance(
                child: SignInView(
                  onSignedIn: onSignedIn,
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 40 : 20,
                    vertical: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.push('/terms'),
                style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                child: const Text('Terms'),
              ),
              ExcludeSemantics(
                child: Text(
                  '·',
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/privacy'),
                style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                child: const Text('Privacy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What Liz is, beside the form on a wide window: the name, one claim in
/// large type, one plain sentence, and a preview of the product itself — the
/// week's risers as Liz shows them — rather than decoration.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.hairline)),
      ),
      // Scrolls on a short window instead of overflowing; fills the height
      // on a normal one, so the spacers place the parts.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(child: _content(context)),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 40),
      child: _Entrance(
        offset: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LizWordmark(size: 28),
            const Spacer(flex: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                'Find AI tools while they are still rising.',
                style: LizText.display.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'Liz ranks new AI tools by how fast they are growing — GitHub '
                'stars, Hacker News points and saves — and says why in plain '
                'words.',
                style: LizText.body.copyWith(
                  color: p.textSecondary,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const _RisingPreview(),
            ),
            const Spacer(flex: 3),
            Text(
              'Ranked daily from GitHub, Hacker News and Liz.',
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The week's risers, drawn as Liz draws them on Discover: a sample of the
/// product rather than a picture of it. The tools are illustrative; signed
/// out, the catalogue itself is not readable.
class _RisingPreview extends StatelessWidget {
  const _RisingPreview();

  static const _rows = [
    (
      'Lensflow',
      'Video',
      '2.2k',
      'GitHub stars',
      [2.0, 2.1, 2.3, 2.4, 2.8, 3.3, 4.1, 5.0, 6.4, 8.0],
    ),
    (
      'Reviewer',
      'Dev tools',
      '1.6k',
      'GitHub stars',
      [3.0, 3.1, 3.0, 3.3, 3.6, 3.7, 4.4, 5.2, 5.9, 6.6],
    ),
    (
      'Taskloop',
      'Agents',
      '276',
      'saves on Liz',
      [1.0, 1.2, 1.3, 1.3, 1.6, 2.0, 2.2, 2.9, 3.4, 4.1],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.canvas,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Rising this week',
                    style: LizText.headline.copyWith(color: p.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    'Last 7 days',
                    style: LizText.footnote.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.hairline),
                _PreviewRow(rank: i + 1, row: _rows[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.rank, required this.row});
  final int rank;
  final (String, String, String, String, List<double>) row;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final (name, category, figure, unit, trend) = row;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: LizText.mono.copyWith(color: p.textSecondary),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: p.surfaceHover,
              shape: LizRadius.shape(
                LizRadius.sm,
                side: BorderSide(color: p.hairlineStrong),
              ),
            ),
            child: Text(
              name[0],
              style: LizText.headline.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: LizText.headline.copyWith(color: p.textPrimary),
                ),
                Text(
                  category,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '+$figure ',
                  style: LizText.mono.copyWith(color: p.accent),
                ),
                TextSpan(
                  text: unit,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SignalSparkline(values: trend, semanticLabel: '', width: 72),
        ],
      ),
    );
  }
}

/// Fades and lifts its child in once, when the page opens. Nothing moves for
/// someone who has asked for reduced motion.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.offset = 12});
  final Widget child;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final duration = LizMotion.of(context, const Duration(milliseconds: 520));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: LizMotion.ease,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
