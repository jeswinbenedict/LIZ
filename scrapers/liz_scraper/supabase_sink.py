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
        # One connection, reused. A rejected batch is retried row by row, so a
        # bad run would otherwise open a TLS handshake per row.
        self._session = requests.Session()

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
                resp = self._session.get(
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

    def _post(self, rows: list[dict]) -> tuple[bool, str]:
        try:
            resp = self._session.post(
                f"{self.settings.rest_url}/tools",
                params={"on_conflict": "content_hash"},
                headers=self._headers,
                json=rows,
                timeout=REQUEST_TIMEOUT,
            )
            resp.raise_for_status()
        except requests.RequestException as err:
            return False, str(err)
        return True, ""

    @staticmethod
    def _disambiguate(row: dict) -> dict:
        """Give a row a slug nobody else holds.

        `slug` is unique, but two unrelated products can share a name — a new
        "Scriptly" is not the stored one. Suffixing with the identity hash is
        deterministic, so re-running produces the same slug rather than a new
        row each time.
        """
        retry = dict(row)
        base = (retry.get("slug") or "tool")[:52].rstrip("-")
        retry["slug"] = f"{base}-{retry.get('content_hash', '')[:6]}"
        return retry

    def upsert_tools(self, rows: list[dict]) -> int:
        if not rows:
            return 0

        written = 0
        for start in range(0, len(rows), BATCH_SIZE):
            chunk = rows[start : start + BATCH_SIZE]
            ok, err = self._post(chunk)
            if ok:
                written += len(chunk)
                continue

            # PostgREST rejects the whole batch when any single row violates a
            # constraint, so one name collision would otherwise discard an
            # entire run. Fall back to writing them individually.
            log.warning("batch of %d rejected (%s) — retrying rows singly",
                        len(chunk), err)
            for row in chunk:
                if self._post([row])[0]:
                    written += 1
                    continue
                retry_ok, retry_err = self._post([self._disambiguate(row)])
                if retry_ok:
                    written += 1
                else:
                    log.error("could not write %r: %s", row.get("name"), retry_err)

        return written
