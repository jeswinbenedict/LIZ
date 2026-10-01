-- ============================================================================
-- Liz — seed content (categories, tools, news)
-- Mirrors the app's bundled mock data so a fresh project launches with a full,
-- browsable catalog — the "no empty room" rule (§16, Phase 1).
-- Community seed (profiles/posts/reviews) requires real auth users; see
-- seed_community.sql.
--
-- Local development only (supabase db reset); production data comes from
-- the scrapers. Every counter starts at zero: views, saves and ratings were
-- once invented here, and a local catalog should look like a real one on its
-- first day, not claim ratings nobody gave.
-- Safe to re-run: uses ON CONFLICT upserts on slug/url.
-- ============================================================================

insert into categories (name, slug, icon) values
  ('AI Writing',   'ai-writing',      'edit'),
  ('Video',        'ai-video',        'movie'),
  ('Image',        'ai-image',        'image'),
  ('Audio',        'ai-audio',        'graphic_eq'),
  ('Design',       'ai-design',       'brush'),
  ('Dev Tools',    'ai-dev',          'code'),
  ('Agents',       'ai-agents',       'smart_toy'),
  ('Productivity', 'ai-productivity', 'bolt'),
  ('Research',     'ai-research',     'science'),
  ('New Apps',     'new-apps',        'apps')
on conflict (slug) do update set name = excluded.name, icon = excluded.icon;

-- Tools -----------------------------------------------------------------------
insert into tools
  (name, slug, tagline, description, ai_summary, website_url, category, tags,
   platforms, pricing_type, price_note, source, trend_score, view_count,
   save_count, avg_rating, rating_count, status, launched_at, created_at)
values
  ('Scriptly','scriptly','Turn a rough outline into a finished script in seconds.',
   'Scriptly drafts video scripts, ad copy, and long-form articles from a short brief, keeping tone consistent and citing sources inline.',
   '["Generates full scripts from a one-line brief.","Keeps a consistent voice across an entire project.","Inline source citations you can verify."]',
   'https://example.com/scriptly','ai-writing',
   '{writing,copywriting,video,scripts}','{web}','freemium','Free tier: 10k words/mo',
   'producthunt',0,0,0,0,0,'published',now()-interval '6 days',now()-interval '6 days'),

  ('Framecut','framecut','Edit video by editing the transcript.',
   'Framecut transcribes footage, then lets you cut, rearrange, and caption by editing text. Filler-word and silence removal is one click.',
   '["Edit video by editing its transcript.","One-click filler-word and silence removal.","Auto-captions in 30+ languages."]',
   'https://example.com/framecut','ai-video',
   '{video,editing,transcription,captions}','{web,mac}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '9 days',now()-interval '9 days'),

  ('Backdrop','backdrop','Remove and replace image backgrounds, free.',
   'A fast, free background remover with AI relight so the subject matches the new scene. Batch mode handles hundreds of product photos.',
   '["Free, high-quality background removal.","AI relights the subject to match new scenes.","Batch mode for product photography."]',
   'https://example.com/backdrop','ai-image',
   '{image,background,ecommerce,design}','{web,ios,android}','free',null,
   'github',0,0,0,0,0,'published',now()-interval '21 days',now()-interval '21 days'),

  ('Vocalize','vocalize','Studio-quality voiceover from text.',
   'Vocalize produces natural narration with controllable emotion and pacing. Clone your voice with a two-minute sample.',
   '["Natural narration with emotion controls.","Voice cloning from a 2-minute sample.","Export broadcast-ready audio."]',
   'https://example.com/vocalize','ai-audio',
   '{audio,voice,tts,podcast}','{web}','paid','From $12/mo',
   'producthunt',0,0,0,0,0,'published',now()-interval '18 days',now()-interval '18 days'),

  ('Layoutly','layoutly','Describe a UI, get a Figma-ready design.',
   'Layoutly turns a text prompt into editable, on-brand UI layouts. Export to Figma or copy production React.',
   '["Text-to-UI in seconds, fully editable.","Exports Figma files and React code.","Learns your brand tokens."]',
   'https://example.com/layoutly','ai-design',
   '{design,ui,figma,frontend}','{web}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '5 days',now()-interval '5 days'),

  ('Reviewer','reviewer','An AI pair that reviews your PRs.',
   'Reviewer comments on pull requests with context from your whole repo, flags risky changes, and suggests tests. Self-hostable.',
   '["Repo-aware pull-request reviews.","Flags risky diffs and missing tests.","Self-hostable for private code."]',
   'https://example.com/reviewer','ai-dev',
   '{dev,code-review,github,productivity}','{web}','freemium',null,
   'github',0,0,0,0,0,'published',now()-interval '4 days',now()-interval '4 days'),

  ('Taskloop','taskloop','An agent that runs your recurring workflows.',
   'Describe a repeatable task once; Taskloop schedules it, calls your tools, and reports back. Connects to 200+ apps.',
   '["Natural-language automation for recurring work.","Connects to 200+ apps and APIs.","Reports results on a schedule."]',
   'https://example.com/taskloop','ai-agents',
   '{agents,automation,workflow,productivity}','{web}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '7 days',now()-interval '7 days'),

  ('Inboxzero AI','inboxzero-ai','Triage, draft, and schedule your email.',
   'Sorts your inbox by intent, drafts replies in your voice, and surfaces the three emails that actually matter today.',
   '["Sorts email by intent automatically.","Drafts replies that sound like you.","Highlights what truly needs attention."]',
   'https://example.com/inboxzeroai','ai-productivity',
   '{productivity,email,assistant}','{web,ios,android}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '24 days',now()-interval '24 days'),

  ('Sourcely','sourcely','Ask a question, get a cited research brief.',
   'Sourcely searches academic and web sources, then writes a structured brief with citations and a confidence note on each claim.',
   '["Cited research briefs from a question.","Confidence score on each claim.","Export to Notion, Docs, or Markdown."]',
   'https://example.com/sourcely','ai-research',
   '{research,citations,writing,academic}','{web}','freemium',null,
   'hackernews',0,0,0,0,0,'published',now()-interval '12 days',now()-interval '12 days'),

  ('Moodboard','moodboard','Generate on-brand image sets instantly.',
   'Feed Moodboard a few references and it produces cohesive image sets for campaigns — consistent style, characters, and lighting.',
   '["Cohesive image sets from a few references.","Consistent characters and lighting.","Campaign-ready exports."]',
   'https://example.com/moodboard','ai-image',
   '{image,branding,marketing,design}','{web}','paid','From $19/mo',
   'producthunt',0,0,0,0,0,'published',now()-interval '15 days',now()-interval '15 days'),

  ('Clipper','clipper','Turn long videos into short clips that pop.',
   'Clipper finds the best moments in a long video, reframes them vertically, adds captions, and schedules them to your socials.',
   '["Finds viral-worthy moments automatically.","Auto reframes and captions for shorts.","Schedules directly to socials."]',
   'https://example.com/clipper','ai-video',
   '{video,social,shorts,marketing}','{web}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '11 days',now()-interval '11 days'),

  ('Querybird','querybird','Chat with your database in plain English.',
   'Ask questions about your data and Querybird writes the SQL, runs it safely on a read replica, and charts the result.',
   '["Plain-English questions become safe SQL.","Runs read-only on a replica.","Auto-charts every result."]',
   'https://example.com/querybird','ai-dev',
   '{dev,data,sql,analytics}','{web}','freemium',null,
   'github',0,0,0,0,0,'published',now()-interval '8 days',now()-interval '8 days'),

  ('Notewise','notewise','Your meetings, summarized and searchable.',
   'Joins your calls, writes structured notes with action items, and makes every past meeting searchable by topic or person.',
   '["Structured notes with action items.","Searchable archive of every meeting.","Syncs tasks to your tracker."]',
   'https://example.com/notewise','ai-productivity',
   '{productivity,meetings,notes,assistant}','{web,mac,windows}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '30 days',now()-interval '30 days'),

  ('Personae','personae','Build a support agent from your docs.',
   'Point Personae at your help center and it deploys a support agent that answers accurately, escalates when unsure, and learns from tickets.',
   '["Support agent trained on your docs.","Escalates gracefully when unsure.","Improves from resolved tickets."]',
   'https://example.com/personae','ai-agents',
   '{agents,support,chatbot,saas}','{web}','paid','From $49/mo',
   'producthunt',0,0,0,0,0,'published',now()-interval '17 days',now()-interval '17 days'),

  ('Palette','palette','AI color systems for real products.',
   'Generate accessible, on-brand color systems with light/dark variants and exportable design tokens — WCAG-checked automatically.',
   '["Accessible color systems in one click.","Light/dark variants + design tokens.","Automatic WCAG contrast checks."]',
   'https://example.com/palette','ai-design',
   '{design,color,accessibility,tokens}','{web}','free',null,
   'github',0,0,0,0,0,'published',now()-interval '26 days',now()-interval '26 days'),

  ('Transcribe Go','transcribe-go','Offline transcription that respects privacy.',
   'A free, on-device transcription app. Nothing leaves your machine. Speaker labels, timestamps, and export to SRT.',
   '["On-device, private transcription.","Speaker labels and timestamps.","Export to SRT, VTT, and text."]',
   'https://example.com/transcribego','ai-audio',
   '{audio,transcription,privacy,free}','{mac,windows,linux}','free',null,
   'github',0,0,0,0,0,'published',now()-interval '13 days',now()-interval '13 days'),

  ('Pitchdeck AI','pitchdeck-ai','From idea to investor deck in minutes.',
   'Describe your startup and Pitchdeck AI builds a structured, designed deck with market sizing and a narrative arc you can edit.',
   '["Full investor deck from a description.","Includes market sizing and narrative.","Fully editable, on-brand slides."]',
   'https://example.com/pitchdeckai','new-apps',
   '{startup,slides,productivity,design}','{web}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '19 days',now()-interval '19 days'),

  ('Refactory','refactory','Modernize legacy code, safely.',
   'Refactory proposes incremental refactors with tests, explains each change, and never touches more than you approve.',
   '["Incremental, test-backed refactors.","Explains the why behind each change.","You approve every diff."]',
   'https://example.com/refactory','ai-dev',
   '{dev,refactoring,legacy,testing}','{web,vscode}','freemium',null,
   'github',0,0,0,0,0,'published',now()-interval '6 days',now()-interval '6 days'),

  ('Storysmith','storysmith','Interactive fiction, generated and playable.',
   'Write a premise and Storysmith generates a branching, playable story with consistent characters and memory of your choices.',
   '["Branching interactive fiction from a premise.","Characters that remember your choices.","Share playable stories with a link."]',
   'https://example.com/storysmith','new-apps',
   '{writing,games,fiction,creative}','{web,ios,android}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '28 days',now()-interval '28 days'),

  ('Datasketch','datasketch','Clean messy spreadsheets with a prompt.',
   'Upload a chaotic CSV and Datasketch normalizes columns, fixes types, dedupes rows, and explains every transformation.',
   '["Prompt-driven spreadsheet cleaning.","Fixes types, dedupes, normalizes.","Full audit trail of every change."]',
   'https://example.com/datasketch','ai-productivity',
   '{data,spreadsheet,productivity,cleaning}','{web}','freemium',null,
   'hackernews',0,0,0,0,0,'published',now()-interval '20 days',now()-interval '20 days'),

  ('Lensflow','lensflow','Text-to-video that keeps characters consistent.',
   'Generate short cinematic clips from prompts with the same character across shots — a long-standing pain point, solved.',
   '["Consistent characters across generated shots.","Cinematic camera controls.","Up to 30-second clips."]',
   'https://example.com/lensflow','ai-video',
   '{video,generation,film,creative}','{web}','paid','From $29/mo',
   'producthunt',0,0,0,0,0,'published',now()-interval '3 days',now()-interval '3 days'),

  ('Brief.ai','brief-ai','Your personalized morning tech digest.',
   'Brief.ai learns what you care about and delivers a 3-minute morning read across launches, papers, and releases.',
   '["Personalized 3-minute tech digest.","Covers launches, papers, releases.","Learns from what you open."]',
   'https://example.com/briefai','new-apps',
   '{productivity,news,digest,assistant}','{web,ios,android}','free',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '14 days',now()-interval '14 days'),

  ('Formcraft','formcraft','AI forms that adapt to each answer.',
   'Build conversational forms that branch intelligently, validate inputs, and summarize responses for you automatically.',
   '["Conversational forms that branch by answer.","Smart validation out of the box.","Auto-summarized responses."]',
   'https://example.com/formcraft','ai-productivity',
   '{productivity,forms,nocode,saas}','{web}','freemium',null,
   'producthunt',0,0,0,0,0,'published',now()-interval '25 days',now()-interval '25 days'),

  ('Coversmith','coversmith','Tailored cover letters from a job link.',
   'Paste a job posting and your resume; Coversmith writes a specific, honest cover letter and flags gaps to address.',
   '["Job-specific cover letters in seconds.","Flags gaps between you and the role.","Keeps your authentic voice."]',
   'https://example.com/coversmith','ai-writing',
   '{writing,career,jobs,productivity}','{web}','free',null,
   'hackernews',0,0,0,0,0,'published',now()-interval '22 days',now()-interval '22 days')
on conflict (slug) do nothing;

-- News ------------------------------------------------------------------------
insert into news (title, url, snippet, ai_summary, source, category, published_at, status)
values
  ('A wave of "transcript-first" video editors is reshaping creator workflows',
   'https://example.com/news/transcript-first-editors',
   'Editing footage by editing text is moving from novelty to default, with several tools crossing the usability threshold this month.',
   '["Transcript-based editing is going mainstream.","Turnaround times are dropping sharply.","Captions and clipping are now table stakes."]',
   'techcrunch','ai-video',now()-interval '1 day','published'),
  ('Repo-aware code review agents show real defect-catch gains in early trials',
   'https://example.com/news/repo-aware-review',
   'Teams report agents catching bugs that slipped past human reviewers when given full-repository context.',
   '["Full-repo context beats single-diff review.","Early teams report real defect catches.","Self-hosting eases private-code concerns."]',
   'hackernews','ai-dev',now()-interval '2 days','published'),
  ('On-device transcription hits quality parity with cloud services',
   'https://example.com/news/on-device-transcription',
   'New open models make private, offline transcription genuinely competitive for the first time.',
   '["Offline transcription now rivals the cloud.","Privacy-sensitive fields are early adopters.","Open models drive the shift."]',
   'arstechnica','ai-audio',now()-interval '3 days','published')
on conflict (url) do nothing;

-- Ranks from daily signal snapshots (0037); with none yet, nothing rises.
select refresh_trend_scores();
