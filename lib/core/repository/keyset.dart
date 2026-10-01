import 'dart:convert';

/// Paging for feeds that grow at the top: News, and the newest-first Community
/// feed.
///
/// Offset paging asks for "rows 20 to 39 of the list as it is now". Articles
/// are ingested every hour, so when one lands between the first page and the
/// second, everything shifts down a place and "Load more" opens with the last
/// item already on screen. Asking for "rows after this one" instead cannot be
/// moved by what arrives above it.
///
/// Rows are ordered by a timestamp, newest first, with the id breaking ties so
/// two rows written in the same instant are neither skipped nor repeated.
class Keyset {
  const Keyset(this.at, this.id);

  /// The timestamp of the last row on the previous page, as the server sent it.
  final String at;

  /// Its id.
  final String id;

  static const _prefix = 'k1:';

  /// The cursor for the page after [rows], or null when [rows] was the last.
  static String? after(List<dynamic> rows, String column, int limit) {
    if (rows.length < limit || rows.isEmpty) return null;
    final last = rows.last as Map<String, dynamic>;
    return Keyset(last[column] as String, last['id'] as String).encode();
  }

  /// A cursor this class wrote, or null for none — including an old offset
  /// cursor from before keyset paging, which then starts again from the top.
  static Keyset? decode(String? cursor) {
    if (cursor == null || !cursor.startsWith(_prefix)) return null;
    final body = cursor.substring(_prefix.length);
    final split = body.lastIndexOf('|');
    if (split <= 0 || split == body.length - 1) return null;
    return Keyset(body.substring(0, split), body.substring(split + 1));
  }

  String encode() => '$_prefix$at|$id';

  /// A PostgREST `or` filter for rows that come after this one in
  /// `[column] desc, id desc` order. The timestamp is quoted because its `:`
  /// and `+` would otherwise be read as filter syntax.
  String filter(String column) =>
      '$column.lt."$at",and($column.eq."$at",id.lt.$id)';
}

/// Keyset paging over several sort columns, all descending, with the id last
/// — for the catalog grid, ordered by momentum and then age.
///
/// The ranking is recomputed nightly and the scraper adds tools daily, so an
/// offset page read after either repeated or skipped tools. Only for columns
/// whose values survive a JSON round trip exactly: timestamps, and momentum,
/// which is stored rounded to four places. Not for `avg_rating`, an
/// unrounded average whose double form may not equal the stored numeric.
class SortKeyset {
  const SortKeyset(this.values, this.id);

  /// The last row's value for each sort column, in order.
  final List<Object> values;
  final String id;

  static const _prefix = 'k2:';

  /// The cursor for the page after [rows], or null when [rows] was the last
  /// or a sort value is missing (paging then simply ends).
  static String? after(List<dynamic> rows, List<String> columns, int limit) {
    if (rows.length < limit || rows.isEmpty) return null;
    final last = rows.last as Map<String, dynamic>;
    final values = [for (final c in columns) last[c]];
    if (values.any((v) => v is! num && v is! String)) return null;
    return SortKeyset(values.cast<Object>(), last['id'] as String).encode();
  }

  /// A cursor this class wrote, or null for anything else (an offset cursor
  /// from before, or one for a different number of columns).
  static SortKeyset? decode(String? cursor, int columns) {
    if (cursor == null || !cursor.startsWith(_prefix)) return null;
    try {
      final list =
          jsonDecode(utf8.decode(base64Url.decode(cursor.substring(3))))
              as List;
      if (list.length != columns + 1 || list.last is! String) return null;
      final values = list.sublist(0, columns);
      if (values.any((v) => v is! num && v is! String)) return null;
      return SortKeyset(values.cast<Object>(), list.last as String);
    } on FormatException {
      return null;
    }
  }

  String encode() =>
      _prefix + base64Url.encode(utf8.encode(jsonEncode([...values, id])));

  /// A PostgREST `or` filter for rows after this one in
  /// `columns[0] desc, …, id desc` order: a smaller first value, or an equal
  /// first and a smaller second, and so on down to the id.
  String filter(List<String> columns) {
    assert(columns.length == values.length);
    String lit(Object v) => v is num ? '$v' : '"$v"';
    final terms = <String>[];
    for (var i = 0; i <= columns.length; i++) {
      final eqs = [
        for (var j = 0; j < i; j++) '${columns[j]}.eq.${lit(values[j])}',
      ];
      final lt = i < columns.length
          ? '${columns[i]}.lt.${lit(values[i])}'
          : 'id.lt.$id';
      terms.add(eqs.isEmpty ? lt : 'and(${[...eqs, lt].join(',')})');
    }
    return terms.join(',');
  }
}
