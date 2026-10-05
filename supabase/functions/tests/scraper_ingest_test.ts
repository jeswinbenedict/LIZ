import { assertEquals } from 'jsr:@std/assert@1';
import {
  cleanRow,
  HELD_UPDATE_COLUMNS,
  MAX_ROWS,
  rowsToUpsert,
  stringList,
} from '../scraper-ingest/logic.ts';

// The laptop's key opens scraper-ingest and nothing else. These are the
// limits that make it narrower than the service key it replaced.

Deno.test('only scraper columns get through', () => {
  const row = cleanRow(
    { name: 'T', content_hash: 'h', id: 'x', avg_rating: 5, like_count: 9 },
    HELD_UPDATE_COLUMNS,
  );
  assertEquals(row, { name: 'T' });
});

Deno.test('the scraper publishes or holds; it cannot hide', () => {
  assertEquals(cleanRow({ status: 'pending' }, HELD_UPDATE_COLUMNS), { status: 'pending' });
  assertEquals(
    cleanRow({ status: 'hidden' }, HELD_UPDATE_COLUMNS),
    'status hidden is not allowed',
  );
  assertEquals(cleanRow([1], HELD_UPDATE_COLUMNS), 'not an object');
});

Deno.test('a published listing is not the scraper\'s to rewrite', () => {
  const { rows, refused } = rowsToUpsert(
    [
      { name: 'New', content_hash: 'new' },
      { name: 'Live', content_hash: 'live', status: 'published' },
      { name: 'No hash' },
    ],
    new Set(['live']),
  );
  assertEquals(rows, [{ name: 'New', content_hash: 'new' }]);
  assertEquals(refused, ['live is published', 'missing content_hash']);
});

Deno.test('one call writes at most MAX_ROWS', () => {
  const many = Array.from({ length: MAX_ROWS + 5 }, (_, i) => ({ content_hash: `h${i}` }));
  const { rows, refused } = rowsToUpsert(many, new Set());
  assertEquals(rows.length, MAX_ROWS);
  assertEquals(refused, [`only ${MAX_ROWS} rows per call`]);
  assertEquals(rowsToUpsert('nope', new Set()).refused, ['rows must be a list']);
});

Deno.test('lookup lists keep strings only, capped', () => {
  assertEquals(stringList(['a', 1, '', null, 'b']), ['a', 'b']);
  assertEquals(stringList('a'), []);
  assertEquals(stringList(['a', 'b', 'c'], 2), ['a', 'b']);
});
