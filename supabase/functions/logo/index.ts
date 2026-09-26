// GET /logo?domain=chatgpt.com — CORS-friendly raster logo proxy.
//
// Flutter web (CanvasKit) fetches image BYTES, so it needs the image host to
// send Access-Control-Allow-Origin. Google's favicon service returns great PNGs
// but no CORS header; unavatar sends CORS but sometimes returns SVG (which the
// image widget can't decode → black box). This proxy fetches a raster PNG
// server-side (no CORS limit there) and re-serves it with CORS + long caching,
// so every tool logo loads correctly on web and mobile alike.
//
// Deploy public (no JWT): supabase functions deploy logo --no-verify-jwt

import { checkTargetUrl, isAllowedImageType, MAX_IMAGE_BYTES } from './logic.ts';
import { callerKey, InMemoryLimiter, tooManyRequests } from '../_shared/rate_limit.ts';

const IMG_CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
};

function imgHeaders(contentType: string | null): HeadersInit {
  const ct = contentType && contentType.startsWith('image/') ? contentType : 'image/png';
  return {
    ...IMG_CORS,
    'Content-Type': ct,
    'Cache-Control': 'public, max-age=2592000, immutable',
  };
}

async function tryFetch(url: string): Promise<Response | null> {
  try {
    const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Liz logo proxy)' } });
    return res.ok ? res : null;
  } catch (_) {
    return null;
  }
}

// Counted in memory rather than in the database: one page of the catalog asks
// for dozens of logos, and a round trip per image to save a favicon fetch
// would be a poor trade. Per instance, so it blunts a flood from one source
// rather than enforcing a global ceiling.
const limiter = new InMemoryLimiter(300, 60_000);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: IMG_CORS });

  if (!limiter.take(callerKey(req, 'logo'))) {
    return tooManyRequests(60);
  }

  const u = new URL(req.url);
  const domain = u.searchParams.get('domain');
  const passthrough = u.searchParams.get('url');

  // Candidate raster sources, in order of preference.
  const candidates: string[] = [];
  if (passthrough) {
    // The caller controls this URL, so it is checked before the server is made
    // to fetch it — otherwise the proxy is an open relay onto anything the
    // server can reach, returned with permissive CORS.
    const check = checkTargetUrl(passthrough);
    if (!check.ok) {
      return new Response(`refused: ${check.reason}`, {
        status: 400,
        headers: { ...IMG_CORS, 'Cache-Control': 'public, max-age=3600' },
      });
    }
    candidates.push(check.url.toString());
  }
  if (domain) {
    candidates.push(`https://www.google.com/s2/favicons?domain=${encodeURIComponent(domain)}&sz=256`);
    candidates.push(`https://icons.duckduckgo.com/ip3/${encodeURIComponent(domain)}.ico`);
  }
  if (candidates.length === 0) {
    return new Response('domain or url required', { status: 400, headers: IMG_CORS });
  }

  for (const c of candidates) {
    const res = await tryFetch(c);
    if (res) {
      const contentType = res.headers.get('content-type');
      // Only images leave this endpoint. Anything else means the caller is
      // reaching for something that is not a logo.
      if (!isAllowedImageType(contentType)) continue;

      const declared = Number(res.headers.get('content-length') ?? '0');
      if (declared > MAX_IMAGE_BYTES) continue;

      const buf = await res.arrayBuffer();
      if (buf.byteLength > 0 && buf.byteLength <= MAX_IMAGE_BYTES) {
        return new Response(buf, { headers: imgHeaders(contentType) });
      }
    }
  }
  // A miss costs two upstream lookups before it gives up. Without a cache
  // header every visitor pays that again on every view, forever, for a logo
  // that is not coming back — but keep the window short, since the usual cause
  // is a product moving an asset and a later scrape can fix it.
  return new Response('logo not found', {
    status: 404,
    headers: { ...IMG_CORS, 'Cache-Control': 'public, max-age=3600' },
  });
});
