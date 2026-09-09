import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MIN_SIMILARITY, type Match, reasonFor, STRONG_MATCH } from '../ask-liz/logic.ts';

function match(overrides: Partial<Match> = {}): Match {
  return {
    id: '1',
    name: 'Descript',
    tagline: 'Edit video and podcasts by editing text.',
    pricing_type: 'freemium',
    similarity: 0.9,
    ...overrides,
  };
}

// The thresholds are calibrated against measured scores, not guessed: junk
// answers to an unanswerable question scored 0.823-0.828, while the weakest
// genuine answer (Otter.ai for "transcribe audio privately") scored 0.843.

Deno.test('the floor sits above measured noise and below real answers', () => {
  assert(MIN_SIMILARITY > 0.828, 'must exclude the statusline and link-list results');
  assert(MIN_SIMILARITY <= 0.843, 'must still admit the weakest genuine answer');
});

Deno.test('"close match" is reserved for near-exact fits', () => {
  assert(STRONG_MATCH > MIN_SIMILARITY);
  // Descript scored 0.918 for its own headline feature; 0.877 was only related.
  assert(STRONG_MATCH <= 0.918);
  assert(STRONG_MATCH > 0.877);
});

Deno.test('a strong score is described as a close match', () => {
  const reason = reasonFor(match({ similarity: 0.918 }), 'edit video by transcript');
  assert(reason.startsWith('Close match'), reason);
  assert(reason.includes('Edit video and podcasts'));
});

Deno.test('a middling score is only ever called related', () => {
  const reason = reasonFor(match({ similarity: 0.86 }), 'edit video by transcript');
  assert(reason.startsWith('Related'), reason);
  // Never claim a general fit the score does not support.
  assert(!reason.includes('matches what you described'));
});

Deno.test('free is mentioned only when the question asked for it', () => {
  const asked = reasonFor(match({ pricing_type: 'free' }), 'free video editor');
  assert(asked.startsWith('Free. '), asked);

  const notAsked = reasonFor(match({ pricing_type: 'free' }), 'video editor');
  assert(!notAsked.startsWith('Free. '), notAsked);
});

Deno.test('a paid tool is never labelled free, however the question is phrased', () => {
  const reason = reasonFor(match({ pricing_type: 'paid' }), 'free video editor');
  assert(!reason.startsWith('Free. '), reason);
});

Deno.test('a missing tagline degrades to the strength alone', () => {
  assertEquals(reasonFor(match({ tagline: '', similarity: 0.86 }), 'video'), 'Related');
  assertEquals(reasonFor(match({ tagline: '', similarity: 0.92 }), 'video'), 'Close match');
});
