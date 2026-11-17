import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The light behind every page (docs/DESIGN.md §2, Ambient): near-black,
/// and a ring of the brand's red that reads as light — a white-hot hairline
/// inside a red tube and a soft bloom, brightest along two arcs where it
/// catches the light, faint between, with a whisper of light falling inward
/// and the corners falling into the dark.
///
/// Computed per pixel by a fragment shader (shaders/ambient.frag), so it is
/// sharp at any size and density and its glow adds like light instead of
/// tinting like paint. Where shaders are unavailable a painted version of
/// the same ring stands in. Drawn once per size behind a repaint boundary;
/// nothing animates.
class LizAmbient extends StatefulWidget {
  const LizAmbient({super.key, this.child});
  final Widget? child;

  /// The ring's centre and radius in a box of [size].
  static (Offset, double) geometry(Size size) {
    final phone = size.width < 600;
    return (
      Offset(
        size.width * (phone ? 0.5 : 0.58),
        size.height * (phone ? 0.3 : 0.46),
      ),
      phone ? size.width * 0.72 : math.max(size.width, size.height) * 0.4,
    );
  }

  /// How bright the light is: [quiet] behind dense content, [full] on open
  /// pages that ask for it with [AmbientLevel].
  static const quiet = 0.42;
  static const full = 1.0;
  static final level = ValueNotifier<double>(quiet);
  static final _requests = <Object>[];

  static Future<ui.FragmentProgram?>? _program;

  static Future<ui.FragmentProgram?> _load() =>
      _program ??= ui.FragmentProgram.fromAsset(
        'shaders/ambient.frag',
      ).then<ui.FragmentProgram?>((p) => p).catchError((Object _) => null);

  @override
  State<LizAmbient> createState() => _LizAmbientState();
}

class _LizAmbientState extends State<LizAmbient>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;

  /// The level shown, easing toward [LizAmbient.level] when it changes.
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: LizAmbient.level.value,
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    LizAmbient._load().then((p) {
      if (mounted && p != null) setState(() => _program = p);
    });
    LizAmbient.level.addListener(_follow);
  }

  void _follow() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _shown.value = LizAmbient.level.value;
    } else {
      _shown.animateTo(LizAmbient.level.value, curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    LizAmbient.level.removeListener(_follow);
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final program = _program;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: program == null
                  ? AmbientPainter(
                      canvas: p.canvas,
                      red: p.accent,
                      level: _shown,
                    )
                  : _ShaderPainter(
                      program,
                      canvas: p.canvas,
                      red: p.accent,
                      level: _shown,
                    ),
            ),
          ),
        ),
        ?widget.child,
      ],
    );
  }
}

const _hot = Color(0xFFFFD6CC);

class _ShaderPainter extends CustomPainter {
  _ShaderPainter(
    this.program, {
    required this.canvas,
    required this.red,
    required this.level,
  }) : super(repaint: level);
  final ui.FragmentProgram program;
  final Animation<double> level;
  final Color canvas;
  final Color red;

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    final (centre, radius) = LizAmbient.geometry(size);
    final s = program.fragmentShader();
    var i = 0;
    void f(double v) => s.setFloat(i++, v);
    void rgb(Color col) {
      f(col.r);
      f(col.g);
      f(col.b);
    }

    f(size.width);
    f(size.height);
    f(centre.dx);
    f(centre.dy);
    f(radius);
    f(1); // uDpr: coordinates here are logical pixels
    rgb(canvas);
    rgb(red);
    rgb(_hot);
    f(level.value);
    c.drawRect(Offset.zero & size, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) =>
      old.program != program || old.canvas != canvas || old.red != red;
}

/// The same ring painted with blurred strokes, added like light (plus), for
/// where a shader cannot run.
class AmbientPainter extends CustomPainter {
  AmbientPainter({required this.canvas, required this.red, this.level})
    : super(repaint: level);
  final Color canvas;
  final Color red;
  final Animation<double>? level;

  @override
  void paint(Canvas c, Size size) {
    final rect = Offset.zero & size;
    c.drawRect(rect, Paint()..color = canvas);
    if (size.isEmpty) return;
    final (centre, radius) = LizAmbient.geometry(size);
    c.saveLayer(
      rect,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, (level?.value ?? 1).clamp(0.0, 1.0)),
    );
    final dim = red.withValues(alpha: 0.22);
    final sweep = ui.Gradient.sweep(
      centre,
      [
        dim,
        red.withValues(alpha: 0.5),
        Color.lerp(red, _hot, 0.6)!,
        red.withValues(alpha: 0.45),
        dim,
        Color.lerp(red, _hot, 0.45)!,
        dim,
      ],
      const [0.0, 0.22, 0.39, 0.55, 0.72, 0.9, 1.0],
      TileMode.clamp,
      0,
      math.pi * 2,
    );
    void ring(double width, double sigma) => c.drawCircle(
      centre,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = sweep
        ..maskFilter = sigma > 0
            ? MaskFilter.blur(BlurStyle.normal, sigma)
            : null,
    );
    ring(radius * 0.18, radius * 0.08);
    ring(radius * 0.05, radius * 0.02);
    ring(radius * 0.012, radius * 0.004);
    ring(1.6, 0.4);
    c.restore();
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.45),
          math.max(size.width, size.height) * 0.8,
          [
            canvas.withValues(alpha: 0),
            canvas.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.55),
          ],
          const [0, 0.6, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(AmbientPainter old) =>
      old.canvas != canvas || old.red != red;
}

/// The page transition the app already used, with [LizAmbient] behind each
/// page inside it: every page is opaque with its own light, so two pages
/// never show through each other while one fades in over the other.
class AmbientPageTransitionsBuilder extends PageTransitionsBuilder {
  const AmbientPageTransitionsBuilder();
  static const _inner = FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    LizAmbient(child: child),
  );
}

/// Asks for the full ambient light while this page is on screen (open pages:
/// Ask Liz before a question, Welcome). Pages full
/// of content leave it quiet, so the ring never runs bright behind text.
/// Tabs kept alive offstage stop asking, through [TickerMode].
class AmbientLevel extends StatefulWidget {
  const AmbientLevel({super.key, required this.child, this.full = true});
  final Widget child;
  final bool full;

  @override
  State<AmbientLevel> createState() => _AmbientLevelState();
}

class _AmbientLevelState extends State<AmbientLevel> {
  bool _asking = false;

  void _update() {
    final want = widget.full && TickerMode.valuesOf(context).enabled;
    if (want == _asking) return;
    _asking = want;
    if (want) {
      LizAmbient._requests.add(this);
    } else {
      LizAmbient._requests.remove(this);
    }
    // After the frame: changing a notifier during build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LizAmbient.level.value = LizAmbient._requests.isEmpty
          ? LizAmbient.quiet
          : LizAmbient.full;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(AmbientLevel old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    if (_asking) {
      LizAmbient._requests.remove(this);
      final empty = LizAmbient._requests.isEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LizAmbient.level.value = empty ? LizAmbient.quiet : LizAmbient.full;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
