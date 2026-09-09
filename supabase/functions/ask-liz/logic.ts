// gte-small similarities sit in a narrow, high band: across sample queries any
// two pieces of English product copy score ~0.83, an on-topic tool ~0.86, and a
// tool whose headline feature *is* the request ~0.92 (Descript for "edit video
// by transcript"). A textbook 0.5 floor therefore admits the entire catalog.
//
// The floor sits where measured noise stops and real answers start: asking to
// "review my pull requests" — something no tool in the catalog actually does —
// scored 0.823-0.828 against a statusline and a link list, while genuine
// answers begin at Otter.ai's 0.843 for "transcribe audio privately". Returning
// nothing is the correct response to a question the catalog cannot answer.
//
// Calibrated on a handful of queries against a ~160-tool catalog — revisit as
// both grow, and prefer measuring over guessing if results drift.
export const MIN_SIMILARITY = 0.84;
export const STRONG_MATCH = 0.89;

export type Match = {
  id: string;
  name: string;
  tagline: string;
  pricing_type: string;
  similarity: number;
};

/// States what the match is based on, and how confident it is, without
/// claiming more than the score supports.
export function reasonFor(match: Match, query: string): string {
  const wantsFree = /\bfree\b/i.test(query);
  const isFree = match.pricing_type === 'free' || match.pricing_type === 'freemium';
  const prefix = wantsFree && isFree ? 'Free. ' : '';
  // "Related" is the honest word for the middle of that band — it is on topic,
  // but it is not necessarily the tool for the job.
  const strength = match.similarity >= STRONG_MATCH ? 'Close match' : 'Related';
  const tagline = match.tagline?.trim();
  return tagline ? `${prefix}${strength} — ${tagline}` : `${prefix}${strength}`;
}
