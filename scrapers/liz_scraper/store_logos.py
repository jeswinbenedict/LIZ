"""Store every tool's logo once, small, in Supabase Storage.

    python -m liz_scraper.store_logos              # report, change nothing
    python -m liz_scraper.store_logos --apply      # store and repoint logo_url

Each logo used to be fetched through the `logo` Edge Function on every first
view, twenty-odd function calls per visit to Discover (migration 0048). This
fetches it once — through that same proxy, so its rules still hold: no private
addresses, no SVG, nothing over 5 MB — shrinks it to fit 128 x 128, encodes it
as WebP (a few kilobytes), uploads it to the public `logos` bucket and points
tools.logo_url at it. The Storage CDN then serves it with a one-year cache.

New tools get theirs on the daily scrape run; this also back-fills.

A tool with no usable logo anywhere — no icon, or only an SVG — gets an empty
logo_url: "looked, found nothing". The app then draws its letter tile without
asking the proxy, which every visitor's browser otherwise did, logging a 404
each time. The row stays in this job's queue, so a logo that appears later is
still picked up.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import io
import json
import logging
import sys
from urllib.parse import quote, urlsplit

import requests

from .config import REQUEST_TIMEOUT, load_settings

log = logging.getLogger(__name__)

SIZE = 128
BUCKET = "logos"

# Hosts whose favicon belongs to the host, not to the tool listed there — the
# same list the app keeps (Env._sharedHosts).
_SHARED_HOSTS = ("github.com", "githubusercontent.com", "producthunt.com",
                 "ycombinator.com", "run.app", "google.com")


def to_webp(data: bytes, size: int = SIZE) -> bytes | None:
    """The image fitted into size x size, as WebP. None when it is not an
    image Pillow can read, or too small to be a usable logo."""
    from PIL import Image, UnidentifiedImageError

    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, ValueError):
        return None
    if min(img.size) < 16:
        return None
    if getattr(img, "n_frames", 1) > 1:
        img.seek(0)
    img = img.convert("RGBA")
    img.thumbnail((size, size), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, format="WEBP", quality=85, method=6)
    return out.getvalue()


def object_name(tool_id: str, webp: bytes) -> str:
    return f"{tool_id}-{hashlib.sha1(webp).hexdigest()[:8]}.webp"


def domain_of(url: str | None) -> str | None:
    host = urlsplit(url or "").netloc.lower().removeprefix("www.")
    if not host or any(host == h or host.endswith("." + h) for h in _SHARED_HOSTS):
        return None
    return host


NO_LOGO = ""


def same_logo_filter(logo_url: str | None) -> str:
    """PostgREST filter matching the logo_url that was read, so a write never
    overwrites one that something else set in the meantime."""
    return "is.null" if logo_url is None else f"eq.{logo_url}"


def should_mark_none(tool: dict) -> bool:
    """Whether a miss is news: rows already marked need no write."""
    return tool.get("logo_url") != NO_LOGO


def proxy_url(functions_url: str, tool: dict) -> str | None:
    domain = domain_of(tool.get("website_url"))
    logo = tool.get("logo_url")
    if logo and "/logo?" in logo:
        return logo
    if logo:
        suffix = f"&domain={quote(domain)}" if domain else ""
        return f"{functions_url}/logo?url={quote(logo, safe='')}{suffix}"
    if domain:
        return f"{functions_url}/logo?domain={quote(domain)}"
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.store_logos")
    parser.add_argument("--apply", action="store_true", help="Store and repoint.")
    parser.add_argument("--limit", type=int, default=2000)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    base = settings.supabase_url.rstrip("/")
    public_prefix = f"{base}/storage/v1/object/public/{BUCKET}/"
    key = settings.service_role_key
    rest = {"apikey": key, "Authorization": f"Bearer {key}"}

    rows = requests.get(
        f"{settings.rest_url}/tools",
        params={"select": "id,name,website_url,logo_url", "status": "eq.published",
                "or": f"(logo_url.is.null,logo_url.not.like.{public_prefix}*)",
                "order": "momentum.desc", "limit": args.limit},
        headers=rest, timeout=REQUEST_TIMEOUT,
    ).json()

    outcome: collections.Counter[str] = collections.Counter()
    http = requests.Session()

    def mark_none(tool: dict) -> None:
        if not args.apply or not should_mark_none(tool):
            return
        http.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"eq.{tool['id']}",
                    "logo_url": same_logo_filter(tool.get("logo_url"))},
            headers={**rest, "Content-Type": "application/json", "Prefer": "return=minimal"},
            json={"logo_url": NO_LOGO},
            timeout=REQUEST_TIMEOUT,
        )
        outcome["marked none"] += 1

    for tool in rows:
        src = proxy_url(f"{base}/functions/v1", tool)
        if not src:
            outcome["no source"] += 1
            mark_none(tool)
            continue
        try:
            resp = http.get(src, timeout=REQUEST_TIMEOUT)
        except requests.RequestException:
            # A network failure says nothing about the logo: leave the row.
            outcome["unreachable"] += 1
            continue
        if resp.status_code != 200 or not resp.headers.get("content-type", "").startswith("image/"):
            outcome["no logo"] += 1
            if resp.status_code == 404:
                mark_none(tool)
            continue
        webp = to_webp(resp.content)
        if webp is None:
            outcome["unusable"] += 1
            mark_none(tool)
            continue
        outcome["stored"] += 1
        if not args.apply:
            continue
        name = object_name(tool["id"], webp)
        up = http.post(
            f"{base}/storage/v1/object/{BUCKET}/{name}",
            data=webp,
            headers={**rest, "Content-Type": "image/webp",
                     "cache-control": "31536000", "x-upsert": "true"},
            timeout=REQUEST_TIMEOUT,
        )
        if up.status_code >= 400:
            log.warning("upload failed for %s: %s", tool["name"], up.text[:200])
            outcome["upload failed"] += 1
            continue
        http.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"eq.{tool['id']}"},
            headers={**rest, "Content-Type": "application/json", "Prefer": "return=minimal"},
            json={"logo_url": public_prefix + name},
            timeout=REQUEST_TIMEOUT,
        )

    print(json.dumps({"tried": len(rows), **outcome, "applied": args.apply}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
