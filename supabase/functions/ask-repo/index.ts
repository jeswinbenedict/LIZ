// POST /ask-repo — questions about an analysed repository.
//
// Body: { "analysis_id": "…", "question": "How does authentication work?",
//         "focus": "path/or/module"? }
// Returns: { data: { answer, citations: [{ path, line }] }, error }
//
// Only the owner of the analysis may ask (checked here with the service role,
// as the row's RLS would). Answers come from the analysis's own facts and the
// files it kept, cited by path and line (see _shared/repo/ask.ts for how
// retrieval works and how repository text is kept from steering the model).
//
// Deploy: supabase functions deploy ask-repo

import { json, corsHeaders } from '../_shared/cors.ts';
import { tooManyRequests, withinRateLimit } from '../_shared/rate_limit.ts';
import { AiCredentialsError, completeText } from '../_shared/ai.ts';
import { citations, prompt, retrieve, SYSTEM } from '../_shared/repo/ask.ts';
import { factsForAi } from '../_shared/repo/pipeline.ts';
import { admin, lizUid } from '../_shared/repo/caller.ts';

const QUESTIONS_PER_HOUR = 40;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ data: null, error: 'Use POST' }, 405);

  const db = admin();
  const uid = await lizUid(req, db);
  if (!uid) return json({ data: null, error: 'Sign in to ask about a repository' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ data: null, error: 'Send JSON' }, 400);
  }
  const id = String(body.analysis_id ?? '');
  const question = String(body.question ?? '').trim().slice(0, 600);
  const focus = typeof body.focus === 'string' && body.focus.length <= 300 ? body.focus : null;
  if (!/^[0-9a-f-]{36}$/.test(id) || question.length < 3) return json({ data: null, error: 'Ask a question about one of your analyses.' }, 400);

  if (!(await withinRateLimit(`ask-repo:${uid}`, QUESTIONS_PER_HOUR))) return tooManyRequests(600);

  const { data: analysis } = await db.from('repo_analyses').select('id, report, sections, status').eq('id', id).eq('user_id', uid).maybeSingle();
  if (!analysis) return json({ data: null, error: 'No such analysis.' }, 404);
  if (analysis.status !== 'done') return json({ data: null, error: 'This analysis has not finished.' }, 409);

  const { data: files } = await db.from('repo_analysis_files').select('path, content').eq('analysis_id', id);
  const chunks = retrieve((files ?? []) as { path: string; content: string }[], question, focus);
  const facts = factsForAi(analysis.report ?? {}, analysis.sections ?? []);

  try {
    const answer = await completeText({ system: SYSTEM, user: prompt(facts, chunks, question), maxTokens: 1100 });
    if (!answer.trim()) return json({ data: null, error: 'No answer came back. Try asking another way.' }, 502);
    return json({ data: { answer: answer.trim(), citations: citations(answer, chunks) }, error: null });
  } catch (e) {
    if (e instanceof AiCredentialsError) {
      console.error('ask-repo: AI key refused');
      return json({ data: null, error: 'Answers are unavailable right now: the AI provider’s key needs renewing.', code: 'ai_credentials' }, 503);
    }
    return json({ data: null, error: 'The AI provider did not answer. Try again in a minute.' }, 502);
  }
});
