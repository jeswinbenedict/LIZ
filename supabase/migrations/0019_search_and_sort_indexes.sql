-- Indexes for the two query shapes the catalog has outgrown plans for.
--
-- Neither is measurable at today's 185 published tools — a sequential scan
-- over 185 rows finishes before the network round trip does. Both matter at
-- the size the ingestion pipeline is heading for, and adding them now costs
-- nothing while the table is small.

-- Search ORs across name, tagline and description. The first two have
-- trigram indexes; the third does not, and Postgres cannot combine a bitmap
-- OR when one branch has no index to scan — so the whole OR falls back to a
-- sequential scan, defeating the two indexes that are there.
create index if not exists idx_tools_description_trgm
  on tools using gin (description gin_trgm_ops);

-- The "Top rated" sort orders by rating with no index to read it from, so it
-- sorts every published row on each request. Rows with no ratings never
-- appear at the top, so they are left out of the index entirely.
create index if not exists idx_tools_status_rating
  on tools (status, avg_rating desc, rating_count desc)
  where rating_count > 0;
