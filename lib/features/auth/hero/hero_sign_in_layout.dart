import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../../app/theme.dart';
import 'character_stage.dart';
import '../sign_in_view.dart';

/// The sign-in page's layout (`/signin`): the seven characters beside the
/// form on a wide window, above it on a narrow one (docs/DESIGN.md §8).
///
/// The form is [SignInView], unchanged. The characters read it from outside,
/// through focus: which box has focus, and whether the password box hides
/// what is typed. Nothing here touches authentication.
class HeroSignInLayout extends StatefulWidget {
  const HeroSignInLayout({super.key, required this.onSignedIn});

  /// Where to go once signed in; [SignInScreen] decides.
  final VoidCallback onSignedIn;

  static const splitWidth = 960.0;

  @override
  State<HeroSignInLayout> createState() => _HeroSignInLayoutState();
}

class _HeroSignInLayoutState extends State<HeroSignInLayout> {
  final _pointer = ValueNotifier<Offset?>(null);
  final _cue = ValueNotifier(const HeroCue(HeroMood.idle));

  @override
  void initState() {
    super.initState();
    // Read on what can change it, never by polling: focus moving, and a tap
    // or a key, which is how the password's eye button changes visibility
    // without moving focus.
    FocusManager.instance.addListener(_readSoon);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent _) {
    _readSoon();
    return false;
  }

  /// After the frame that applies the change, so the form has rebuilt.
  void _readSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _readForm();
    });
  }

  /// The cue from the form: the focused box, read from the widget that owns
  /// the focus.
  void _readForm() {
    final node = FocusManager.instance.primaryFocus;
    final field = node?.context?.findAncestorWidgetOfExactType<TextField>();
    final label = field?.decoration?.labelText;
    HeroCue cue;
    if (field == null || label == null) {
      cue = const HeroCue(HeroMood.idle);
    } else if (label == 'Password') {
      cue = HeroCue(field.obscureText ? HeroMood.privacy : HeroMood.peek);
    } else {
      cue = HeroCue(HeroMood.attentive, node!.rect);
    }
    _cue.value = cue;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_readSoon);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _pointer.dispose();
    _cue.dispose();
    super.dispose();
  }

  Widget _stage({Alignment alignment = Alignment.bottomCenter}) =>
      CharacterStage(pointer: _pointer, cue: _cue, alignment: alignment);

  Widget _form(BuildContext context, EdgeInsets padding) => Listener(
    onPointerUp: (_) => _readSoon(),
    child: Theme(
      data: _formTheme(context),
      child: SignInView(onSignedIn: widget.onSignedIn, padding: padding),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= HeroSignInLayout.splitWidth;
    return Scaffold(
      backgroundColor: const Color(0xFF07070A),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (e) => _pointer.value = e.position,
        onPointerMove: (e) => _pointer.value = e.position,
        onPointerDown: (e) => _pointer.value = e.position,
        child: MouseRegion(
          onExit: (_) => _pointer.value = null,
          child: Stack(
            children: [
              const Positioned.fill(child: _Backdrop()),
              if (wide) _wide(context) else _narrow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final p = context.liz;
    final width = MediaQuery.sizeOf(context).width;
    final formWidth = width >= 1280 ? 520.0 : 460.0;
    return Row(
      children: [
        Expanded(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 36, 32, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LizWordmark(size: 28),
                  const SizedBox(height: 28),
                  _Copy(palette: p),
                  const SizedBox(height: 16),
                  // The characters: the page's picture, as large as the
                  // panel allows.
                  Expanded(child: _stage()),
                  const SizedBox(height: 12),
                  Text(
                    'Ranked daily from GitHub, Hacker News and Liz.',
                    style: LizText.footnote.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: formWidth,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 32, 16),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _Glass(
                        radius: 24,
                        child: _form(
                          context,
                          const EdgeInsets.fromLTRB(32, 32, 32, 28),
                        ),
                      ),
                    ),
                  ),
                  _LegalLinks(palette: p),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    final p = context.liz;
    final size = MediaQuery.sizeOf(context);
    // The form comes first on a phone; the characters are a band above it,
    // sized by the height too, so a short window still shows the form.
    final band = (size.width * 0.5)
        .clamp(110.0, 220.0)
        .clamp(0.0, size.height * 0.28);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LizWordmark(size: 24),
              ),
            ),
            SizedBox(height: band, child: _stage()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Centred: the column stretches its children, which would
              // override the panel's maximum width.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _Glass(
                    radius: 20,
                    child: _form(
                      context,
                      const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    ),
                  ),
                ),
              ),
            ),
            _LegalLinks(palette: p),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  /// The form's boxes and buttons, lifted for the glass panel: a darker
  /// fill, a red focus edge, and the label in white once focused.
  ThemeData _formTheme(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.liz;
    OutlineInputBorder edge(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: const Color(0xFF0E0E12),
        hoverColor: const Color(0xFF15151B),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: edge(p.hairlineStrong),
        enabledBorder: edge(p.hairlineStrong),
        focusedBorder: edge(p.accent, 1.6),
        floatingLabelStyle: LizText.footnote.copyWith(color: p.textPrimary),
        focusColor: p.accent,
      ),
    );
  }
}

/// The two lines beside the characters, as the sign-in page has them.
class _Copy extends StatelessWidget {
  const _Copy({required this.palette});
  final LizPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Find AI tools while they are still rising.',
            style: LizText.display.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
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
      ],
    );
  }
}

/// A dark glass panel: the backdrop's light shows through, blurred.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 18});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            color: const Color(0xC70E0E12),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Near-black, with the brand's red rising from behind the characters and a
/// faint electric blue opposite it, as in the concept.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.25, 0.85),
          radius: 0.9,
          colors: [Color(0x33FF3B3B), Color(0x00FF3B3B)],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1.0, -0.9),
            radius: 0.8,
            colors: [Color(0x1F3B82F6), Color(0x003B82F6)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.9, -1.0),
              radius: 0.7,
              colors: [Color(0x1AFF3B3B), Color(0x00FF3B3B)],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({required this.palette});
  final LizPalette palette;

  @override
  Widget build(BuildContext context) {
    final style = LizText.footnote.copyWith(color: palette.textSecondary);
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => context.push('/terms'),
            child: Text('Terms', style: style),
          ),
          Text('·', style: style),
          TextButton(
            onPressed: () => context.push('/privacy'),
            child: Text('Privacy', style: style),
          ),
        ],
      ),
    );
  }
}
