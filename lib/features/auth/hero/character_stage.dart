import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'hero_eye.dart';
import 'hero_eyes.dart';

/// What the characters are doing, from the form beside them.
enum HeroMood {
  /// Nothing to react to: they rest, breathe and blink, and follow the
  /// pointer when there is one.
  idle,

  /// A name or email box has focus: they look at it, leaning in a little.
  attentive,

  /// The password box has focus and the password is hidden: eyes closed.
  privacy,

  /// The password is being shown: they look away, politely.
  peek,
}

/// The mood and, for [HeroMood.attentive], the global rect to look at.
@immutable
class HeroCue {
  const HeroCue(this.mood, [this.target]);
  final HeroMood mood;
  final Rect? target;

  @override
  bool operator ==(Object other) =>
      other is HeroCue && other.mood == mood && other.target == target;

  @override
  int get hashCode => Object.hash(mood, target);
}

/// The seven characters of the sign-in page, alive.
///
/// The picture is flat, so nothing in it can move on its own. What moves is
/// drawn over it: each iris (painted out of the picture by
/// tool/brand/make_hero.py) and each eyelid, clipped to the eye's opening by
/// a mask, so the drawing never leaves the eye. Whole-picture motion —
/// breathing and a lean — moves all seven together.
///
/// Every frame is painted, not rebuilt: a ticker updates the state and the
/// painter repaints. With reduced motion there is no breathing, blinking,
/// or lean, and the eyes go where they are going without easing.
class CharacterStage extends StatefulWidget {
  const CharacterStage({
    super.key,
    required this.pointer,
    required this.cue,
    this.alignment = Alignment.bottomCenter,
  });

  /// The pointer, in global coordinates; null when it has left the page.
  final ValueListenable<Offset?> pointer;
  final ValueListenable<HeroCue> cue;

  final Alignment alignment;

  @override
  State<CharacterStage> createState() => _CharacterStageState();
}

class _CharacterStageState extends State<CharacterStage>
    with SingleTickerProviderStateMixin {
  static const _base = AssetImage('assets/hero/characters.webp');
  static const _mask = AssetImage('assets/hero/eye_openings.png');
  static const _closed = AssetImage('assets/hero/eyes_closed.webp');
  static const _irises = AssetImage('assets/hero/irises.png');

  final _sim = _HeroSim();

  /// Bumped every tick; the painter repaints on it.
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  ui.Image? _baseImage;
  ui.Image? _maskImage;
  ui.Image? _closedImage;
  ui.Image? _irisImage;
  final _streams = <ImageStream, ImageStreamListener>{};
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load(_base, (i) => _baseImage = i);
    _load(_mask, (i) => _maskImage = i);
    _load(_closed, (i) => _closedImage = i);
    _load(_irises, (i) => _irisImage = i);
  }

  void _load(ImageProvider provider, void Function(ui.Image) done) {
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => done(info.image));
      if (_baseImage != null &&
          _maskImage != null &&
          _closedImage != null &&
          _irisImage != null &&
          !_ticker.isActive) {
        _ticker.start();
      }
    });
    stream.addListener(listener);
    _streams[stream] = listener;
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final global = widget.pointer.value;
    final cue = widget.cue.value;
    _sim.step(
      dt: dt,
      time: now.inMicroseconds / 1e6,
      size: box.size,
      alignment: widget.alignment,
      pointer: global == null ? null : box.globalToLocal(global),
      cue: cue.mood,
      target: cue.target == null ? null : box.globalToLocal(cue.target!.center),
      calm: MediaQuery.disableAnimationsOf(context),
    );
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _streams.forEach((s, l) => s.removeListener(l));
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _baseImage;
    final mask = _maskImage;
    final closed = _closedImage;
    final irises = _irisImage;
    return Semantics(
      image: true,
      label:
          'Seven friends gathered round a laptop, looking at what is rising '
          'on Liz.',
      child: AnimatedOpacity(
        opacity:
            base == null || mask == null || closed == null || irises == null
            ? 0
            : 1,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: base == null || mask == null || closed == null || irises == null
            ? const SizedBox.expand()
            : RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _StagePainter(
                    base: base,
                    mask: mask,
                    closed: closed,
                    irises: irises,
                    sim: _sim,
                    alignment: widget.alignment,
                    repaint: _frame,
                  ),
                ),
              ),
      ),
    );
  }
}

/// One character: two eyes that look together and blink together.
class _Character {
  _Character(this.left, this.right, this.speed, this.reach, this.seed)
    : look = left.rest,
      lookLeft = left.rest,
      lookRight = left.rest,
      _goal = left.rest,
      _rng = math.Random(seed) {
    _nextBlink = 1.5 + _rng.nextDouble() * 3;
    _phases = [for (var i = 0; i < 4; i++) _rng.nextDouble() * math.pi * 2];
  }

  final HeroEye left;
  final HeroEye right;

  /// How quickly this one's eyes catch up, and how far they swing: each
  /// character a little different, so they do not move as one.
  final double speed;
  final double reach;
  final int seed;
  final math.Random _rng;

  /// Where the pair is looking, as a fraction of the iris's travel, and how
  /// fast that is changing: the eyes are a damped spring, so they speed up
  /// out of one place and ease into the next instead of sliding at one rate.
  Offset look;
  Offset velocity = Offset.zero;

  /// Each eye's own look: the pair's, plus a drift of a percent or two that
  /// is each eye's own, as living eyes never hold perfectly still.
  Offset lookLeft;
  Offset lookRight;
  Offset _goal;
  late final List<double> _phases;
  double lid = 0;
  double _nextBlink = 0;
  double? _blinkAt;

  Offset get centre => (left.opening.center + right.opening.center) / 2;

  /// Moves the pair towards [goal]. Stiffness from [speed]; damped just short
  /// of critical, so a long look settles without overshoot you could see.
  void follow(Offset goal, double dt, bool calm) {
    // A big change of gaze often comes with a blink, as it does in people.
    if ((goal - _goal).distance > 0.9 &&
        _blinkAt == null &&
        _rng.nextDouble() < 0.35) {
      _nextBlink = 0;
    }
    _goal = goal;
    if (calm) {
      look = goal;
      velocity = Offset.zero;
    } else {
      final k = speed * speed;
      final c = 2 * 0.92 * speed;
      // Small steps: a long frame must not make the spring overshoot.
      var left = dt;
      while (left > 0) {
        final h = math.min(left, 1 / 240);
        final a = (goal - look) * k - velocity * c;
        velocity += a * h;
        look += velocity * h;
        left -= h;
      }
    }
  }

  /// Each eye's look: the pair's plus its own slow drift.
  void settleEyes(double time, bool calm) {
    Offset own(int i) => calm
        ? Offset.zero
        : Offset(
            math.sin(time * 0.83 + _phases[i]) * 0.018 +
                math.sin(time * 2.1 + _phases[i + 1]) * 0.008,
            math.sin(time * 0.71 + _phases[i + 1]) * 0.014,
          );
    Offset inside(Offset o) => o.distance > 1 ? o / o.distance : o;
    lookLeft = inside(look + own(0));
    lookRight = inside(look + own(2));
  }

  /// 0 → 1 → 0 over a blink of 0.16 s.
  double blink(double time, bool allowed) {
    if (_blinkAt == null && allowed && time >= _nextBlink) _blinkAt = time;
    final at = _blinkAt;
    if (at == null) return 0;
    final t = (time - at) / 0.16;
    if (t >= 1) {
      _blinkAt = null;
      // Now and then a double blink, as people do.
      _nextBlink =
          time +
          (_rng.nextDouble() < 0.15 ? 0.25 : 2.5 + _rng.nextDouble() * 4);
      return 0;
    }
    return math.sin(t * math.pi);
  }
}

class _HeroSim {
  _HeroSim()
    : characters = [
        for (var i = 0; i < heroEyes.length ~/ 2; i++)
          _Character(
            heroEyes[i * 2],
            heroEyes[i * 2 + 1],
            // Stiffness of each one's gaze (per second): some quick, some
            // unhurried.
            const [9.0, 12.0, 8.0, 11.0, 10.0, 7.5, 13.0][i % 7],
            const [1.0, 0.92, 1.05, 0.9, 1.0, 1.08, 0.95][i % 7],
            i * 7919 + 13,
          ),
      ];

  final List<_Character> characters;

  /// The picture's placement in the stage, and its offset and scale on top.
  Rect picture = Rect.zero;
  Offset drift = Offset.zero;
  double swell = 1;

  Offset _parallax = Offset.zero;
  Offset _lean = Offset.zero;

  static double _ease(double k, double dt, bool calm) =>
      calm ? 1 : 1 - math.exp(-k * dt);

  void step({
    required double dt,
    required double time,
    required Size size,
    required Alignment alignment,
    required Offset? pointer,
    required HeroMood cue,
    required Offset? target,
    required bool calm,
  }) {
    final fit = applyBoxFit(BoxFit.contain, heroSize, size);
    picture = alignment.inscribe(fit.destination, Offset.zero & size);
    final scale = picture.width / heroSize.width;

    Offset? toPicture(Offset? local) =>
        local == null ? null : (local - picture.topLeft) / scale;
    final aim = toPicture(cue == HeroMood.attentive ? target : pointer);

    for (final c in characters) {
      Offset goal;
      var lidGoal = 0.0;
      switch (cue) {
        case HeroMood.privacy:
          goal = const Offset(0, 0.6);
          lidGoal = 1;
        case HeroMood.peek:
          // Looking away, up and to the side, eyes half shut.
          goal = Offset(c.seed.isEven ? -0.9 : -0.7, -0.75);
          lidGoal = 0.45;
        case HeroMood.attentive:
        case HeroMood.idle:
          if (aim == null) {
            goal = c.left.rest;
          } else {
            final v = aim - c.centre;
            final d = v.distance;
            // Full swing beyond ~400 px of the picture; gentler up close.
            final m = math.sqrt((d / 400).clamp(0.0, 1.0)) * c.reach;
            goal = d < 1
                ? Offset.zero
                : Offset(v.dx / d * m, v.dy / d * m * 0.85);
          }
      }
      // Within the opening's ellipse.
      final len = goal.distance;
      if (len > 1) goal = goal / len;

      c.follow(goal, dt, calm);
      c.settleEyes(time, calm);
      final lidSpeed = cue == HeroMood.privacy ? 10.0 : 7.0;
      c.lid = c.lid + (lidGoal - c.lid) * _ease(lidSpeed, dt, calm);
      final b = c.blink(time, !calm && cue != HeroMood.privacy);
      c.lid = math.max(c.lid, b * 0.97);
    }

    // Whole picture: breathing, parallax away from the pointer, a lean
    // towards a box being filled, and the reaction.
    if (calm) {
      drift = Offset.zero;
      swell = 1;
      return;
    }
    final breathe = math.sin(time * 2 * math.pi / 4.8);
    final p = pointer == null || size.isEmpty
        ? Offset.zero
        : Offset(
            (pointer.dx / size.width - 0.5).clamp(-1.0, 1.0),
            (pointer.dy / size.height - 0.5).clamp(-1.0, 1.0),
          );
    _parallax = Offset.lerp(_parallax, p * -6, _ease(4, dt, calm))!;
    final leanGoal = cue == HeroMood.attentive
        ? const Offset(6, -2)
        : Offset.zero;
    _lean = Offset.lerp(_lean, leanGoal, _ease(5, dt, calm))!;
    drift = _parallax + _lean + Offset(0, breathe * 2.2);
    swell = 1 + breathe * 0.003 + (cue == HeroMood.attentive ? 0.006 : 0);
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.base,
    required this.mask,
    required this.closed,
    required this.irises,
    required this.sim,
    required this.alignment,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.Image base;
  final ui.Image mask;
  final ui.Image closed;
  final ui.Image irises;
  final _HeroSim sim;
  final Alignment alignment;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.medium;
  static final _irisPaint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (sim.picture.isEmpty) {
      final fit = applyBoxFit(BoxFit.contain, heroSize, size);
      sim.picture = alignment.inscribe(fit.destination, Offset.zero & size);
    }
    final rect = sim.picture;
    final scale = rect.width / heroSize.width * sim.swell;
    final origin =
        Offset(
          rect.center.dx - heroSize.width * scale / 2,
          rect.bottom - heroSize.height * scale,
        ) +
        sim.drift;
    final dst = origin & (heroSize * scale);
    final src = Offset.zero & heroSize;

    canvas.drawImageRect(base, src, dst, _imagePaint);

    // Everything drawn in the eyes goes on a layer the openings mask.
    canvas.saveLayer(dst, Paint());
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    for (final c in sim.characters) {
      _eye(canvas, c.left, c.lookLeft);
      _eye(canvas, c.right, c.lookRight);
    }
    canvas.restore();
    canvas.drawImageRect(
      mask,
      src,
      dst,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // Lids go over the layer, not in it: a closed eye covers the lash line
    // too, which the openings' mask would cut off.
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    for (final c in sim.characters) {
      if (c.lid <= 0.01) continue;
      _lid(canvas, c.left, c.lid);
      _lid(canvas, c.right, c.lid);
    }
    canvas.restore();
  }

  /// The upper lid coming down: the closed eye as the artist painted it
  /// (assets/hero/eyes_closed.webp, lined up on each face by
  /// tool/brand/make_hero.py) swept down over the open one behind an edge
  /// bowed like a lid's, until it covers the eye.
  void _lid(Canvas canvas, HeroEye e, double lid) {
    final area = e.lidArea;
    // A soft edge, a few pixels deep, so the lid comes down as shading rather
    // than a cut across the eye; it travels until the soft part has passed
    // the bottom too.
    const soft = 5.0;
    final edge = area.top - soft + (area.height + soft * 2) * lid;
    canvas.saveLayer(area, Paint());
    canvas.drawImageRect(closed, area, area, _imagePaint);
    canvas.drawRect(
      area,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset(0, edge - soft),
          Offset(0, edge),
          const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ),
    );
    canvas.restore();
  }

  void _eye(Canvas canvas, HeroEye e, Offset look) {
    final o = e.opening;
    final t = e.travel;
    final c = o.center + Offset(look.dx * t.dx, look.dy * t.dy);
    final r = e.irisRadius;

    // The artist's iris (tool/brand/make_hero.py renders each from its own
    // painted colours, rim to pupil, four times over for sharpness).
    final sprite = e.irisSprite;
    canvas.drawImageRect(
      irises,
      sprite,
      Rect.fromCenter(
        center: c,
        width: sprite.width / 4,
        height: sprite.height / 4,
      ),
      _irisPaint,
    );
    canvas.drawCircle(
      c + Offset(r * 0.32, -r * 0.36),
      r * 0.2,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      c + Offset(-r * 0.3, r * 0.3),
      r * 0.08,
      Paint()..color = const Color(0xB3FFFFFF),
    );

    // The upper lid's shadow on the eyeball, as the painting has it.
    final shadeTop = o.top;
    canvas.drawRect(
      Rect.fromLTRB(
        o.left - 2,
        shadeTop,
        o.right + 2,
        shadeTop + o.height * 0.45,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shadeTop),
          Offset(0, shadeTop + o.height * 0.45),
          [const Color(0x2E000000), const Color(0x00000000)],
        ),
    );
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      old.base != base ||
      old.mask != mask ||
      old.closed != closed ||
      old.irises != irises ||
      old.alignment != alignment;
}
