/// Small JSON parsing helpers shared by all models. Supabase returns loosely
/// typed maps; these coerce safely so a single unexpected null never crashes a
/// whole feed.
library;

String asString(Object? v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

String? asStringOrNull(Object? v) => v?.toString();

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double asDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return fallback;
}

DateTime asDate(Object? v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime(1970);
  return DateTime(1970);
}

DateTime? asDateOrNull(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

List<String> asStringList(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}
