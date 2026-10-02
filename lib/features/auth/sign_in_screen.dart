import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../app/theme.dart';
import '../../shared/widgets/page_header.dart';
import 'sign_in_view.dart';

/// The sign-in page (`/signin`), in the Signal look (docs/DESIGN.md).
///
/// Wide windows — most visitors, on a desktop browser — get two halves: a
/// brand panel that says what Liz is, lit by seams of red light and a trend
/// line that draws itself in, and a quiet column with the form. Narrow
/// windows get the wordmark and the form alone: on a phone the panel would
/// only push the form below the fold.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  /// From this width the brand panel has room beside a full-width form.
  static const splitWidth = 960.0;

  void _done(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
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

/// The form side: a close button, the form centred in a 420 column, and the
/// legal links at the foot.
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
              IconButton(
                tooltip: context.canPop() ? 'Close' : 'Go to Discover',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ],
          ),
        ),
        if (!wide) const GlowLine(strength: 0.6),
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

/// What Liz is, beside the form on a wide window.
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
      child: Stack(
        children: [
          // The seams of light: decoration only.
          const Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _SeamsPainter()),
            ),
          ),
          // Scrolls on a short window instead of overflowing; fills the
          // height on a normal one, so the spacers place the parts.
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(child: _content(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 48),
      child: _Entrance(
        offset: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LizWordmark(size: 28),
            const Spacer(flex: 3),
            const Eyebrow('// MOMENTUM, NOT HYPE'),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'Find the AI tools taking off — before everyone else.',
                style: LizText.display.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'Liz ranks new AI tools by how fast they are growing, '
                'and tells you why.',
                style: LizText.body.copyWith(
                  color: p.textSecondary,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const _Point(
              label: 'DAILY SIGNALS',
              text:
                  'GitHub stars, Hacker News points and real visits, '
                  'recorded every day.',
            ),
            const _Point(
              label: 'REASONS, IN WORDS',
              text: 'Every rank says why: “+3.4k GitHub stars this week”.',
            ),
            const _Point(
              label: 'WATCHED FOR YOU',
              text:
                  'Save a tool and hear when its price changes or it '
                  'starts to rise.',
            ),
            const Spacer(flex: 2),
            const SizedBox(height: 72, child: _TrendLine()),
            const SizedBox(height: 12),
            Text(
              'RANKED DAILY · GITHUB · HACKER NEWS · LIZ',
              style: LizText.label.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2,
            height: 38,
            margin: const EdgeInsets.only(right: 14, top: 2),
            decoration: BoxDecoration(
              color: p.accent,
              boxShadow: [BoxShadow(color: p.glow, blurRadius: 6)],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: LizText.label.copyWith(color: p.accent)),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: LizText.callout.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
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

/// A rising line of light that draws itself left to right when the page
/// opens — the shape Liz looks for, as decoration.
class _TrendLine extends StatelessWidget {
  const _TrendLine();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final duration = LizMotion.of(context, const Duration(milliseconds: 1600));
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeInOutCubic,
        builder: (context, t, _) => CustomPaint(
          size: Size.infinite,
          painter: _TrendPainter(progress: t, line: p.accent, glow: p.glow),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.progress,
    required this.line,
    required this.glow,
  });
  final double progress;
  final Color line;
  final Color glow;

  // A fixed, rising shape (not data): slow, then taking off.
  static const _shape = [
    0.12,
    0.14,
    0.13,
    0.17,
    0.16,
    0.21,
    0.24,
    0.23,
    0.31,
    0.38,
    0.47,
    0.6,
    0.74,
    0.9,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path();
    for (var i = 0; i < _shape.length; i++) {
      final o = Offset(
        size.width * i / (_shape.length - 1),
        size.height * (1 - _shape[i]),
      );
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    final tip = metric.getTangentForOffset(metric.length * progress)?.position;

    canvas.drawPath(
      drawn,
      Paint()
        ..color = glow.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (tip != null) {
      canvas.drawCircle(
        tip,
        7,
        Paint()
          ..color = glow.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(tip, 3.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.progress != progress || old.line != line || old.glow != glow;
}

/// Thin seams of red light across the brand panel — after the lines on the
/// TRON: Ares suit the look was drawn from. Fixed geometry, scaled to the
/// panel; drawn faint so text over them stays easy to read.
class _SeamsPainter extends CustomPainter {
  const _SeamsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const red = LizColors.brand;

    void seam(List<Offset> points, {double alpha = 0.55}) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final o in points.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = red.withValues(alpha: alpha * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = red.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Two seams down the right edge, angling in like a suit's panels.
    seam([
      Offset(w * 0.86, 0),
      Offset(w * 0.86, h * 0.34),
      Offset(w * 0.78, h * 0.44),
      Offset(w * 0.78, h),
    ], alpha: 0.35);
    seam([
      Offset(w * 0.93, 0),
      Offset(w * 0.93, h * 0.40),
      Offset(w * 0.85, h * 0.50),
      Offset(w * 0.85, h),
    ], alpha: 0.5);
    // A short horizontal seam near the top, under the wordmark.
    seam([Offset(0, h * 0.13), Offset(w * 0.32, h * 0.13)], alpha: 0.3);
  }

  @override
  bool shouldRepaint(_SeamsPainter old) => false;
}
