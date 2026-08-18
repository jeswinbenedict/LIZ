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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: IMG_CORS });

  const u = new URL(req.url);
  const domain = u.searchParams.get('domain');
  const passthrough = u.searchParams.get('url');

  // Candidate raster sources, in order of preference.
  const candidates: string[] = [];
  if (passthrough) candidates.push(passthrough);
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
      const buf = await res.arrayBuffer();
      if (buf.byteLength > 0) {
        return new Response(buf, { headers: imgHeaders(res.headers.get('content-type')) });
      }
    }
  }
  return new Response('logo not found', { status: 404, headers: IMG_CORS });
});
