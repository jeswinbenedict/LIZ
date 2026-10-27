import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../app/theme.dart';
import '../../shared/widgets/signal_sparkline.dart';

/// The page every account screen sits in — signing in, a forgotten password,
/// a new password — so the three read as one place (docs/DESIGN.md §8).
///
/// Wide windows get two halves: a brand panel that says what Liz is and shows
/// a preview of it, and a quiet column with the form. Narrow windows get the
/// wordmark and the form alone: on a phone the panel would only push the form
/// below the fold. Both halves end on the same footer line.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.child, this.scrolls = false});

  /// The form: an [AuthHeading] and what follows it.
  final Widget child;

  /// Whether [child] scrolls and pads itself (the sign-in form, which is
  /// also shown in a sheet). Otherwise the frame does both.
  final bool scrolls;

  /// The padding round a form, by window: [SignInView] takes it too.
  static EdgeInsets formPadding(BuildContext context) => EdgeInsets.symmetric(
    horizontal: MediaQuery.sizeOf(context).width >= splitWidth ? 40 : 20,
    vertical: 24,
  );

  /// From this width the brand panel has room beside a full-width form.
  static const splitWidth = 960.0;

  /// The height of the line both halves end on.
  static const _footer = 56.0;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final wide = MediaQuery.sizeOf(context).width >= splitWidth;
    final form = _FormColumn(wide: wide, scrolls: scrolls, child: child);

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

/// A form's title and the line under it. The title is the page's heading.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          headingLevel: 1,
          child: Text(
            title,
            style: LizText.title1.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: LizText.callout.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

/// "← Back to sign in", above a form that is a step away from signing in.
class AuthBackLink extends StatelessWidget {
  const AuthBackLink({super.key, this.label = 'Back to sign in'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Align(
      alignment: Alignment.centerLeft,
      // The arrow lines up with the form's edge, not the button's padding.
      child: Transform.translate(
        offset: const Offset(-12, 0),
        child: TextButton.icon(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/signin'),
          style: TextButton.styleFrom(foregroundColor: p.textSecondary),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

/// A form message — an error, a confirmation, a warning — as a quiet panel:
/// the colour is in the icon, the words stay in ink. Announced to screen
/// readers when it appears, and optionally titled.
class AuthMessage extends StatelessWidget {
  const AuthMessage({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
    this.title,
  });
  final String text;
  final Color color;
  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final fill = Color.alphaBlend(color.withValues(alpha: 0.06), p.surface);
    // Its own node, so the message is announced on its own rather than read
    // as the tail of the field hint above it.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: ShapeDecoration(
          color: fill,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: color.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 18,
                color: LizColors.legibleOn(color, fill),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: LizText.headline.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    text,
                    style: LizText.callout.copyWith(
                      color: title == null ? p.textPrimary : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary button of an account form: full width, 50 tall, a spinner
/// while [busy].
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.fromHeight(50)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? Semantics(
              label: 'Working',
              child: const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Text(label),
    );
  }
}

/// The form side: the wordmark on a narrow window, the form centred in a
/// 460 column, and the legal links at the foot. No close button: every page
/// is behind sign-in, so there is nowhere to close to.
class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.wide,
    required this.scrolls,
    required this.child,
  });
  final bool wide;
  final bool scrolls;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final link = TextButton.styleFrom(foregroundColor: p.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On a wide window the wordmark is in the brand panel.
        if (!wide) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LizWordmark(size: 24),
            ),
          ),
          Divider(height: 1, color: p.hairline),
        ],
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _Entrance(
                child: scrolls
                    ? child
                    : SingleChildScrollView(
                        padding: AuthFrame.formPadding(context),
                        child: child,
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: AuthFrame._footer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.push('/terms'),
                style: link,
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
                style: link,
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
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 0),
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
            SizedBox(
              height: AuthFrame._footer,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ranked daily from GitHub, Hacker News and Liz.',
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ),
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
            LizRadius.lg,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
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
            ),
            for (var i = 0; i < _rows.length; i++) ...[
              Divider(height: 1, color: p.hairline),
              _PreviewRow(rank: i + 1, row: _rows[i]),
            ],
          ],
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: LizText.subhead.copyWith(
                color: p.textSecondary,
                fontFeatures: LizText.tabular,
              ),
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
                  style: LizText.subhead.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: LizText.tabular,
                  ),
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
