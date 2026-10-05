"""Write normalized rows into Supabase via PostgREST.

Upserts on `content_hash` so a re-run refreshes an existing row instead of
duplicating it. The service-role key bypasses RLS and must stay server-side;
a machine with LIZ_INGEST_KEY goes through the scraper-ingest function instead
(config.py).
"""

from __future__ import annotations

import logging

import requests

from .config import REQUEST_TIMEOUT, Settings
from .ingest_client import IngestClient

log = logging.getLogger(__name__)

BATCH_SIZE = 50


class SupabaseSink:
    def __init__(self, settings: Settings) -> None:
        if not settings.can_scrape:
            raise ValueError(
                "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or LIZ_INGEST_KEY) "
                "must be set to write rows."
            )
        self.settings = settings
        # One connection, reused. A rejected batch is retried row by row, so a
        # bad run would otherwise open a TLS handshake per row.
        self._session = requests.Session()
        self._ingest = (IngestClient(settings, self._session)
                        if settings.uses_ingest else None)

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
        """Which hashes are already settled, so a run can skip re-fetching them.

        Only *published* rows count as settled. A pending row is one the
        quality gate held back — usually because enrichment could not reach the
        product page and website_url is still the listing — and the reason is
        often transient: a 403 from one IP, a site that was down, a redirect
        that resolved later. Treating those as done would freeze the first bad
        result forever, because the hash is taken from the listing URL and the
        row would be skipped on every future run.

        Retrying costs little: candidates come from a feed capped per run, so a
        run only ever re-attempts what is currently on the front page.
        """
        if not hashes:
            return set()

        found: set[str] = set()
        for start in range(0, len(hashes), BATCH_SIZE):
            chunk = hashes[start : start + BATCH_SIZE]
            quoted = ",".join(f'"{h}"' for h in chunk)
            try:
                if self._ingest:
                    found.update(self._ingest.published(chunk))
                    continue
                resp = self._session.get(
                    f"{self.settings.rest_url}/tools",
                    params={
                        "select": "content_hash",
                        "content_hash": f"in.({quoted})",
                        "status": "eq.published",
                    },
                    headers=self._headers,
                    timeout=REQUEST_TIMEOUT,
                )
                resp.raise_for_status()
            except requests.RequestException as err:
                log.warning("dedupe lookup failed: %s", err)
                continue
            found.update(row["content_hash"] for row in resp.json())

        return found

    def existing_sites(self, keys: list[str]) -> dict[str, str]:
        """site_key -> content_hash for published rows on these sites, so a
        product reached through a different listing URL is not written again."""
        found: dict[str, str] = {}
        keys = [k for k in keys if k]
        for start in range(0, len(keys), BATCH_SIZE):
            chunk = keys[start : start + BATCH_SIZE]
            quoted = ",".join(f'"{k}"' for k in chunk)
            try:
                if self._ingest:
                    found.update(self._ingest.sites(chunk))
                    continue
                resp = self._session.get(
                    f"{self.settings.rest_url}/tools",
                    params={"select": "site_key,content_hash",
                            "site_key": f"in.({quoted})", "status": "eq.published"},
                    headers=self._headers, timeout=REQUEST_TIMEOUT,
                )
                resp.raise_for_status()
            except requests.RequestException as err:
                log.warning("site lookup failed: %s", err)
                continue
            found.update({r["site_key"]: r["content_hash"] for r in resp.json()})
        return found

    def _post(self, rows: list[dict]) -> tuple[bool, str]:
        try:
            if self._ingest:
                self._ingest.upsert(rows)
                return True, ""
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
