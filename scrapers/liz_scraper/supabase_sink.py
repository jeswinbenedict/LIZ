"""Write normalized rows into Supabase via PostgREST.

Upserts on `content_hash` so a re-run refreshes an existing row instead of
duplicating it. The service-role key bypasses RLS and must stay server-side.
"""

from __future__ import annotations

import logging

import requests

from .config import REQUEST_TIMEOUT, Settings

log = logging.getLogger(__name__)

BATCH_SIZE = 50


class SupabaseSink:
    def __init__(self, settings: Settings) -> None:
        if not settings.configured:
            raise ValueError(
                "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set to write rows."
            )
        self.settings = settings

    @property
    def _headers(self) -> dict[str, str]:
        key = self.settings.service_role_key
        return {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        }

    def existing_hashes(self, hashes: list[str]) -> set[str]:
        """Ask which content hashes are already stored, so we can skip re-fetching."""
        if not hashes:
            return set()

        found: set[str] = set()
        for start in range(0, len(hashes), BATCH_SIZE):
            chunk = hashes[start : start + BATCH_SIZE]
            quoted = ",".join(f'"{h}"' for h in chunk)
            try:
                resp = requests.get(
                    f"{self.settings.rest_url}/tools",
                    params={"select": "content_hash", "content_hash": f"in.({quoted})"},
                    headers=self._headers,
                    timeout=REQUEST_TIMEOUT,
                )
                resp.raise_for_status()
            except requests.RequestException as err:
                log.warning("dedupe lookup failed: %s", err)
                continue
            found.update(row["content_hash"] for row in resp.json())

        return found

    def upsert_tools(self, rows: list[dict]) -> int:
        if not rows:
            return 0

        written = 0
        for start in range(0, len(rows), BATCH_SIZE):
            chunk = rows[start : start + BATCH_SIZE]
            try:
                resp = requests.post(
                    f"{self.settings.rest_url}/tools",
                    params={"on_conflict": "content_hash"},
                    headers=self._headers,
                    json=chunk,
                    timeout=REQUEST_TIMEOUT,
                )
                resp.raise_for_status()
            except requests.RequestException as err:
                log.error("upsert failed for %d rows: %s", len(chunk), err)
                continue
            written += len(chunk)

        return written
