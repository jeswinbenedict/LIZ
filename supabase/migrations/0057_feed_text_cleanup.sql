-- hnrss.org's per-story footer ("Article URL: … Comments URL: … Points: N
-- # Comments: N") was stored as the snippet of every Hacker News story and
-- shown as its summary. fetch-news now drops it; this clears the rows already
-- collected, keeping any Ask HN text written above the footer.
update public.news
set snippet = btrim(regexp_replace(
  snippet,
  '\s*Article URL:\s*\S+\s*Comments URL:\s*\S+\s*Points:\s*\d+\s*#\s*Comments:\s*\d+\s*$',
  '',
  'i'
))
where source = 'hackernews'
  and snippet ~* 'Article URL:\s*\S+\s*Comments URL:';

-- GitHub taglines were the repository description sliced at 140 characters,
-- so many ended mid-word ("one CLI, zero AP") or on a dangling "&".
-- fetch-tools now cuts at a word (clipTagline); this repairs the rows it cut
-- before, and only those still holding the raw slice, so a tagline a person
-- or the enricher rewrote is left alone.
update public.tools
set tagline = regexp_replace(
  regexp_replace(
    regexp_replace(left(regexp_replace(btrim(description), '\s+', ' ', 'g'), 139), '\s+\S*$', ''),
    '(\s+(&|and|or|with|the|a|an|of|to|for))+$', '', 'i'
  ),
  '[\s,;:&—–-]+$', ''
) || '…'
where source = 'github'
  and length(description) > 140
  and tagline = left(description, 140)
  and position(' ' in left(description, 139)) > 0;
