import { assert, assertEquals } from 'jsr:@std/assert@1';
import { EMBEDDING_DIMS, EMBEDDING_MODEL, toolText } from '../_shared/embed.ts';
import { extractJson } from '../_shared/ai.ts';

Deno.test('the embedding contract matches the vector(384) column', () => {
  // A mismatch here makes every stored vector unusable, silently.
  assertEquals(EMBEDDING_DIMS, 384);
  assertEquals(EMBEDDING_MODEL, 'gte-small');
});

Deno.test('toolText leads with what the tool does, not its name', () => {
  const text = toolText({
    name: 'Descript',
    tagline: 'Edit video by editing text.',
    description: 'Transcript-based video editor.',
    tags: ['video', 'audio'],
    category: 'ai-video',
  });

  // Someone searches for a job to be done, so the functional wording has to
  // dominate the vector rather than the brand.
  assert(text.startsWith('Edit video by editing text.'), text);
  assert(text.indexOf('Descript') > text.indexOf('Edit video'));
  assert(text.includes('video, audio'));
  // The "ai-" prefix is noise repeated across every category.
  assert(!text.includes('ai-video'));
});

Deno.test('toolText tolerates missing fields', () => {
  assertEquals(toolText({ name: 'Solo' }), 'Solo');
  assertEquals(toolText({}), '');
  assertEquals(toolText({ name: null, tagline: null, tags: null }), '');
});

Deno.test('extractJson reads a fenced block', () => {
  const out = extractJson<{ a: number }>('prose\n```json\n{"a":1}\n```\nmore', { a: 0 });
  assertEquals(out.a, 1);
});

Deno.test('extractJson falls back rather than throwing on junk', () => {
  assertEquals(extractJson('not json at all', { fallback: true }), { fallback: true });
  assertEquals(extractJson('{"broken": ', { fallback: true }), { fallback: true });
});
