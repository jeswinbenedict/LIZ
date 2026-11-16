// An overview in prose, written by a model from the extracted facts.
//
// Optional: the report stands without it. The model sees only the facts this
// code extracted (factsForAi), never raw repository text, so nothing a stranger
// wrote in the repository reaches it here.

import { completeText, extractJson } from '../ai.ts';

export interface Narrative {
  overview: string;
  howItWorks: string;
  learnToBuild: string[];
}

const SYSTEM = `You write a short, accurate technical overview of a software repository for a developer who has never seen it.
Use only the JSON facts given. Do not invent technologies, files or features that are not in the facts.
Answer with JSON only: {"overview": "2-3 sentences: what it is and what it is built with", "howItWorks": "3-5 sentences: how the parts work together", "learnToBuild": ["5-8 technologies or concepts to learn to build something similar, each a few words"]}`;

export async function narrate(facts: string): Promise<Narrative | null> {
  const text = await completeText({ system: SYSTEM, user: facts, maxTokens: 700 });
  const j = extractJson<Partial<Narrative>>(text, {});
  if (typeof j.overview !== 'string' || typeof j.howItWorks !== 'string') return null;
  return {
    overview: j.overview.slice(0, 800),
    howItWorks: j.howItWorks.slice(0, 1400),
    learnToBuild: Array.isArray(j.learnToBuild) ? j.learnToBuild.filter((x) => typeof x === 'string').slice(0, 8).map((x) => x.slice(0, 80)) : [],
  };
}
