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
