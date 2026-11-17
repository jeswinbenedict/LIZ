import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme.dart';
import 'ambient_gpu/gpu_stub.dart'
    if (dart.library.js_interop) 'ambient_gpu/gpu_web.dart';

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
  const LizAmbient({super.key, this.child, this.animate = true});
  final Widget? child;

  /// Whether the light may move. Off for the app-wide light, which every
  /// page covers with its own: two moving lights would cost twice.
  final bool animate;

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

  /// The shader, or null where it would run on the CPU (no WebGL) or
  /// fails to load; the painted light stands in.
  static Future<ui.FragmentProgram?> _load() => _program ??= !hasGpuCanvas()
      ? Future<ui.FragmentProgram?>.value()
      : ui.FragmentProgram.fromAsset(
          'shaders/ambient.frag',
        ).then<ui.FragmentProgram?>((p) => p).catchError((Object _) => null);

  @override
  State<LizAmbient> createState() => _LizAmbientState();
}

class _LizAmbientState extends State<LizAmbient> with TickerProviderStateMixin {
  ui.FragmentProgram? _program;

  /// Live light (web, with WebGL, motion allowed): seconds since start and
  /// the pointer, eased, as the shader's uTime / uPointer.
  final _clock = _Live();
  Ticker? _ticker;
  Offset? _target;

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

  void _tick(Duration elapsed) {
    _clock.time = 1 + elapsed.inMicroseconds / 1e6;
    final target = _target;
    final on = target == null ? 0.0 : 1.0;
    _clock.on += (on - _clock.on) * 0.06;
    if (target != null) {
      _clock.pointer = Offset.lerp(_clock.pointer, target, 0.08)!;
    }
    _clock.notify();
  }

  void _syncTicker(bool animate) {
    if (animate && _ticker == null) {
      _ticker = createTicker(_tick)..start();
    } else if (!animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
      _clock.time = 0;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    LizAmbient.level.removeListener(_follow);
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final program = _program;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final live = program != null && kIsWeb && !reduce && widget.animate;
    _syncTicker(live);
    final stack = Stack(
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
                  : live
                  ? _LivePainter(
                      program,
                      canvas: p.canvas,
                      red: p.accent,
                      level: _shown,
                      clock: _clock,
                    )
                  : _ShaderPainter(
                      program,
                      canvas: p.canvas,
                      red: p.accent,
                      level: _shown,
                      dpr: MediaQuery.devicePixelRatioOf(context),
                    ),
            ),
          ),
        ),
        ?widget.child,
      ],
    );
    if (!live) return stack;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _target = e.localPosition,
      onPointerMove: (e) => _target = e.localPosition,
      child: MouseRegion(
        opaque: false,
        onExit: (_) => _target = null,
        child: stack,
      ),
    );
  }
}

class _Live extends ChangeNotifier {
  double time = 0;
  Offset pointer = Offset.zero;
  double on = 0;
  void notify() => notifyListeners();
}

/// The shader drawn every frame, moving: used only on the web with WebGL,
/// where it runs on the GPU. Elsewhere the baked, still light is drawn.
class _LivePainter extends CustomPainter {
  _LivePainter(
    this.program, {
    required this.canvas,
    required this.red,
    required this.level,
    required this.clock,
  }) : super(repaint: Listenable.merge([level, clock]));
  final ui.FragmentProgram program;
  final Color canvas;
  final Color red;
  final Animation<double> level;
  final _Live clock;
  late final ui.FragmentShader _s = program.fragmentShader();

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    final (centre, radius) = LizAmbient.geometry(size);
    var i = 0;
    void f(double v) => _s.setFloat(i++, v);
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
    f(1);
    rgb(canvas);
    rgb(red);
    rgb(_hot);
    f(level.value);
    f(clock.time);
    f(clock.pointer.dx);
    f(clock.pointer.dy);
    f(clock.on);
    c.drawRect(Offset.zero & size, Paint()..shader = _s);
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.program != program || old.canvas != canvas || old.red != red;
}

const _hot = Color(0xFFFFD6CC);

/// The light computed once per size and level, kept as an image.
///
/// The web renderer redraws a page's background on every frame, so drawing
/// the shader directly recomputed every pixel of the screen whenever
/// anything animated — invisible on a GPU, crippling without one (software
/// rendering, low-end phones). Baked, a frame costs one image copy.
class _Baked {
  static final _cache = <String, ui.Image>{};

  static ui.Image of(
    ui.FragmentProgram program,
    Size size,
    double dpr,
    Color canvas,
    Color red,
    double level,
  ) {
    final w = (size.width * dpr).ceil(), h = (size.height * dpr).ceil();
    final key = '$w×$h ${canvas.toARGB32()} ${red.toARGB32()} $level';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // most recent last
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
    f(level);
    f(0); // uTime: still
    f(0);
    f(0);
    f(0); // no pointer
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(dpr)
      ..drawRect(Offset.zero & size, Paint()..shader = s);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    s.dispose();
    _cache[key] = image;
    // A window being resized makes a new size each frame; keep the latest.
    while (_cache.length > 6) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)!.dispose();
    }
    return image;
  }
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter(
    this.program, {
    required this.canvas,
    required this.red,
    required this.level,
    required this.dpr,
  }) : super(repaint: level);
  final ui.FragmentProgram program;
  final Animation<double> level;
  final Color canvas;
  final Color red;
  final double dpr;

  static final _image = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    final dst = Offset.zero & size;
    // Quiet and full are baked; between them is a cross-fade of the two.
    final t =
        ((level.value - LizAmbient.quiet) /
                (LizAmbient.full - LizAmbient.quiet))
            .clamp(0.0, 1.0);
    void draw(double at, double opacity) {
      final img = _Baked.of(program, size, dpr, canvas, red, at);
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      c.drawImageRect(
        img,
        src,
        dst,
        opacity >= 1
            ? _image
            : (Paint()
                ..filterQuality = FilterQuality.low
                ..color = Color.fromRGBO(255, 255, 255, opacity)),
      );
    }

    if (t < 1) draw(LizAmbient.quiet, 1);
    if (t > 0) draw(LizAmbient.full, t);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) =>
      old.program != program ||
      old.canvas != canvas ||
      old.red != red ||
      old.dpr != dpr;
}

/// The same ring for where a shader cannot run, without blur filters (which
/// cost every frame): the glow and bloom are radial gradients banded at the
/// ring's radius, the core a hairline, all scaled by the level.
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
    final k = (level?.value ?? 1).clamp(0.0, 1.0);
    final outer = radius * 1.4;
    Color a(double alpha) => red.withValues(alpha: alpha * k);
    // A band of light around the ring: transparent, lit at the radius,
    // transparent again, wider outside than in (as the shader's bloom).
    void band(double inside, double outside, double alpha) => c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          outer,
          [a(0), a(alpha), a(0)],
          [
            ((radius - inside) / outer).clamp(0.0, 1.0),
            radius / outer,
            ((radius + outside) / outer).clamp(0.0, 1.0),
          ],
        ),
    );
    band(radius * 0.07, radius * 0.11, 0.22);
    band(radius * 0.025, radius * 0.03, 0.4);
    c.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Color.lerp(red, _hot, 0.35 * k)!.withValues(alpha: k),
    );
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
