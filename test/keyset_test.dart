import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/repository/keyset.dart';

/// News and the newest-first Community feed page by "rows after this one",
/// so an article ingested between two pages cannot push a repeat onto the
/// second. Checked against the live news table on 27 September: four keyset
/// pages matched offset paging row for row.

void main() {
  const at = '2026-09-27T09:45:12.345+00:00';

  test('a cursor survives the round trip, colons, plus sign and all', () {
    final cursor = const Keyset(at, 'b7c1-uuid').encode();
    final back = Keyset.decode(cursor)!;
    expect(back.at, at);
    expect(back.id, 'b7c1-uuid');
  });

  test('an old offset cursor starts again from the top', () {
    // A tab open across the upgrade holds a "20"; it must not break paging.
    expect(Keyset.decode('20'), isNull);
    expect(Keyset.decode(null), isNull);
    expect(Keyset.decode('k1:no-separator'), isNull);
    expect(Keyset.decode('k1:$at|'), isNull);
  });

  test('the filter asks for older rows, and same-instant rows by id', () {
    expect(
      const Keyset(at, 'b7c1').filter('published_at'),
      'published_at.lt."$at",and(published_at.eq."$at",id.lt.b7c1)',
    );
  });

  test('a short page is the last page', () {
    final rows = [
      {'id': 'a', 'published_at': at},
      {'id': 'b', 'published_at': at},
    ];
    expect(Keyset.after(rows, 'published_at', 3), isNull);
    expect(Keyset.after(const [], 'published_at', 3), isNull);
    expect(
      Keyset.decode(Keyset.after(rows, 'published_at', 2))!.id,
      'b',
      reason: 'the next page starts after the last row',
    );
  });

  // The catalog grid (momentum, then age). Checked against the live tools
  // table on 1 October: 27 keyset pages of 24 matched one full ordered read
  // row for row, for both Rising and Newest.
  group('over several columns', () {
    const cols = ['momentum', 'created_at'];

    test('a cursor survives the round trip', () {
      final c = const SortKeyset([3.25, at], 'id-9').encode();
      final back = SortKeyset.decode(c, 2)!;
      expect(back.values, [3.25, at]);
      expect(back.id, 'id-9');
    });

    test('anything else starts from the top', () {
      expect(SortKeyset.decode('24', 2), isNull);
      expect(SortKeyset.decode('k2:not-base64!', 2), isNull);
      final one = const SortKeyset([at], 'x').encode();
      expect(SortKeyset.decode(one, 2), isNull, reason: 'wrong column count');
    });

    test('the filter walks the columns down to the id', () {
      expect(
        const SortKeyset([0, at], 'b7').filter(cols),
        'momentum.lt.0,'
        'and(momentum.eq.0,created_at.lt."$at"),'
        'and(momentum.eq.0,created_at.eq."$at",id.lt.b7)',
      );
    });

    test('a missing sort value ends paging rather than guessing', () {
      final rows = [
        {'id': 'a', 'momentum': null, 'created_at': at},
      ];
      expect(SortKeyset.after(rows, cols, 1), isNull);
    });
  });
}
