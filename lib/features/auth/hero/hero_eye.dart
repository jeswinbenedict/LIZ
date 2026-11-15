import 'dart:ui';

/// One eye of the sign-in hero, in the picture's own pixels
/// (tool/brand/make_hero.py measures them and paints the irises out).
class HeroEye {
  const HeroEye({
    required this.opening,
    required this.iris,
    required this.irisRadius,
    required this.lidArea,
    required this.irisSprite,
  });

  /// The box around the eye's opening: the white and the iris between lids.
  final Rect opening;

  /// Where the artist drew the iris: the eye at rest looks this way.
  final Offset iris;
  final double irisRadius;

  /// The eye with its lashes: what a closing lid covers.
  final Rect lidArea;

  /// This eye's iris in assets/hero/irises.png, drawn at four times size.
  final Rect irisSprite;

  /// How far the iris may travel from the opening's centre, per axis. It may
  /// tuck a little under the lids, as real irises do, but never leave.
  Offset get travel => Offset(
    (opening.width / 2 - irisRadius * 0.55).clamp(0.5, double.infinity),
    (opening.height / 2 - irisRadius * 0.75).clamp(0.5, double.infinity),
  );

  /// The resting look, as a fraction of [travel].
  Offset get rest {
    final t = travel;
    final d = iris - opening.center;
    return Offset(
      (d.dx / t.dx).clamp(-1.0, 1.0),
      (d.dy / t.dy).clamp(-1.0, 1.0),
    );
  }
}
