-- 0057 cleared hnrss's footer from stored Hacker News snippets, but missed
-- six: their article URLs were long enough that the snippet's 300-character
-- cut fell inside the footer, and the pattern expected it whole. From
-- "Article URL: … Comments URL:" to the end is footer however it was cut.
-- fetch-news now removes the footer before cutting (newsSnippet).
update public.news
set snippet = btrim(regexp_replace(
  snippet, '\s*Article URL:\s*\S+\s*Comments URL:.*$', '', 'i'
))
where source = 'hackernews'
  and snippet ~* 'Article URL:\s*\S+\s*Comments URL:';
