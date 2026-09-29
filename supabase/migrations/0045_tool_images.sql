-- ============================================================================
-- Liz — a picture of the product. Migration 0045. Safe to re-run.
--
-- People judge software by looking at it, and a tool page had only a logo.
-- Most product sites declare a preview image for link sharing (og:image);
-- the scraper has always read it and thrown it away. It is now kept, shown on
-- the tool page through Liz's image proxy, and filled for existing tools by
-- `python -m liz_scraper.backfill_images`.
-- ============================================================================

alter table public.tools add column if not exists image_url text;

comment on column public.tools.image_url is
  'The product''s own preview image (og:image / twitter:image), absolute URL, '
  'raster only. Null when the site declares none.';
