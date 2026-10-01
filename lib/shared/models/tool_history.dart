import 'json.dart';

/// One day of a tool's signals (tool_signal_snapshots, migration 0037):
/// outside figures as they stood that day, and running totals on Liz.
class SignalPoint {
  const SignalPoint({
    required this.day,
    this.ghStars,
    this.hnPoints,
    this.views = 0,
    this.clicks = 0,
    this.saves = 0,
  });

  final DateTime day;
  final int? ghStars;
  final int? hnPoints;
  final int views;
  final int clicks;
  final int saves;

  /// Interest shown on Liz, weighted the way momentum weights it: a save
  /// means more than a visit, a visit more than a view.
  double get lizActivity => 3.0 * saves + clicks + 0.3 * views;

  factory SignalPoint.fromJson(Map<String, dynamic> j) => SignalPoint(
    day: asDate(j['day']),
    ghStars: j['gh_stars'] == null ? null : asInt(j['gh_stars']),
    hnPoints: j['hn_points'] == null ? null : asInt(j['hn_points']),
    views: asInt(j['views']),
    clicks: asInt(j['clicks']),
    saves: asInt(j['saves']),
  );
}

/// A change to a tool's price, recorded as it happened (migration 0044).
class ToolChange {
  const ToolChange({
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.changedAt,
  });

  /// `pricing_type` or `price_note`.
  final String field;
  final String? oldValue;
  final String? newValue;
  final DateTime changedAt;

  factory ToolChange.fromJson(Map<String, dynamic> j) => ToolChange(
    field: asString(j['field']),
    oldValue: asStringOrNull(j['old_value']),
    newValue: asStringOrNull(j['new_value']),
    changedAt: asDate(j['changed_at']),
  );
}

/// Which line to draw for a tool, and what to call it.
///
/// The signal that actually moves: stars for a repository, activity on Liz
/// for anything people are using here, Hacker News points otherwise. A flat
/// line is left out rather than drawn — it says nothing.
class SignalSeries {
  const SignalSeries(this.label, this.values);

  final String label;
  final List<double> values;

  double get first => values.first;
  double get last => values.last;

  static SignalSeries? pick(List<SignalPoint> unordered) {
    if (unordered.length < 3) return null;
    // Oldest first, whatever order they came in: a query that returned them
    // newest first drew every rising tool as falling (1 October).
    final points = [...unordered]..sort((a, b) => a.day.compareTo(b.day));
    List<double>? series(double? Function(SignalPoint) f) {
      final v = points.map(f).toList();
      if (v.any((x) => x == null)) return null;
      final values = v.cast<double>();
      final moved = values.any((x) => x != values.first);
      return moved ? values : null;
    }

    final stars = series((p) => p.ghStars?.toDouble());
    if (stars != null) return SignalSeries('GitHub stars', stars);
    final liz = series((p) => p.lizActivity);
    if (liz != null) return SignalSeries('Interest on Liz', liz);
    final hn = series((p) => p.hnPoints?.toDouble());
    if (hn != null) return SignalSeries('Hacker News points', hn);
    return null;
  }
}
