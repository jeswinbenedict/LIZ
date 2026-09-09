// Guards for the image proxy.
//
// The proxy exists so Flutter web can read image bytes from hosts that send no
// CORS header. It fetches a caller-supplied URL server-side and returns the
// bytes with Access-Control-Allow-Origin: *, which — unguarded — is an open
// relay: anyone on the internet could launder arbitrary requests through this
// project, and reach addresses only the server can see.

/// Hosts that only exist from inside the network. Fetching one on a caller's
/// behalf turns the proxy into a window onto infrastructure.
const BLOCKED_HOSTNAMES = new Set([
  'localhost',
  'metadata.google.internal',
  'metadata',
]);

function isPrivateIPv4(host: string): boolean {
  const parts = host.split('.');
  if (parts.length !== 4) return false;
  const octets = parts.map((p) => Number(p));
  if (octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  const [a, b] = octets;
  return (
    a === 10 ||                          // 10.0.0.0/8
    a === 127 ||                         // loopback
    (a === 172 && b >= 16 && b <= 31) || // 172.16.0.0/12
    (a === 192 && b === 168) ||          // 192.168.0.0/16
    (a === 169 && b === 254) ||          // link-local, incl. cloud metadata
    a === 0
  );
}

export type UrlCheck = { ok: true; url: URL } | { ok: false; reason: string };

/// Decides whether the proxy may fetch a caller-supplied URL.
export function checkTargetUrl(raw: string): UrlCheck {
  let url: URL;
  try {
    url = new URL(raw);
  } catch (_) {
    return { ok: false, reason: 'not a valid URL' };
  }

  // file:, data: and gopher: are not things an image proxy should reach.
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return { ok: false, reason: `scheme ${url.protocol} is not allowed` };
  }

  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (BLOCKED_HOSTNAMES.has(host)) {
    return { ok: false, reason: 'internal host' };
  }
  // .local and .internal are resolvable only inside a network.
  if (host.endsWith('.local') || host.endsWith('.internal')) {
    return { ok: false, reason: 'internal host' };
  }
  if (isPrivateIPv4(host)) {
    return { ok: false, reason: 'private address' };
  }
  // IPv6 loopback and unique-local.
  if (host === '::1' || host.startsWith('fc') || host.startsWith('fd')) {
    return { ok: false, reason: 'private address' };
  }

  return { ok: true, url };
}

/// The proxy returns images. Anything else — HTML, JSON, a download — means the
/// caller is using it to reach something other than a logo.
export function isAllowedImageType(contentType: string | null): boolean {
  if (!contentType) return false;
  const type = contentType.split(';')[0].trim().toLowerCase();
  return type.startsWith('image/');
}

/// A logo is small. A cap stops the proxy being used to move large files, and
/// bounds what a single request can cost.
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
