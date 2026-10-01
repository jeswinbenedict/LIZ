import 'json.dart';

/// What a person has told Liz about themselves (user_preferences, migration
/// 0050): the kinds of tools they care about, and which alerts they want.
/// Private to them.
class UserPrefs {
  const UserPrefs({
    this.interests = const [],
    this.pricingAlerts = true,
    this.risingAlerts = true,
  });

  /// Category slugs.
  final List<String> interests;
  final bool pricingAlerts;
  final bool risingAlerts;

  bool get hasInterests => interests.isNotEmpty;

  UserPrefs copyWith({
    List<String>? interests,
    bool? pricingAlerts,
    bool? risingAlerts,
  }) => UserPrefs(
    interests: interests ?? this.interests,
    pricingAlerts: pricingAlerts ?? this.pricingAlerts,
    risingAlerts: risingAlerts ?? this.risingAlerts,
  );

  factory UserPrefs.fromJson(Map<String, dynamic> j) {
    final alerts = j['alert_prefs'] is Map
        ? (j['alert_prefs'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return UserPrefs(
      interests: asStringList(j['interests']),
      pricingAlerts: alerts['pricing'] != false,
      risingAlerts: alerts['trending'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'interests': interests,
    'alert_prefs': {'pricing': pricingAlerts, 'trending': risingAlerts},
  };
}
