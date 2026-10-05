"""The scraper-ingest function, for a machine that holds LIZ_INGEST_KEY.

Same operations the scraper does through PostgREST with the service key, and
nothing more (supabase/functions/scraper-ingest). Errors raise
requests.RequestException, as the PostgREST calls do, so callers handle both
the same way.
"""

from __future__ import annotations

import requests

from .config import REQUEST_TIMEOUT, Settings


class IngestClient:
    def __init__(self, settings: Settings, session: requests.Session | None = None) -> None:
        self.settings = settings
        self._session = session or requests.Session()

    def call(self, action: str, **payload) -> object:
        resp = self._session.post(
            self.settings.ingest_url,
            headers={"x-liz-ingest": self.settings.ingest_key,
                     "Content-Type": "application/json"},
            json={"action": action, **payload},
            timeout=REQUEST_TIMEOUT,
        )
        try:
            body = resp.json()
        except ValueError:
            body = {}
        if not isinstance(body, dict):
            body = {}
        if resp.status_code >= 400 or body.get("error"):
            raise requests.HTTPError(
                f"{resp.status_code} scraper-ingest {action}: "
                f"{body.get('error') or resp.text[:200]}",
                response=resp,
            )
        return body.get("data")

    def published(self, hashes: list[str]) -> set[str]:
        return set(self.call("existing", hashes=hashes)["published"])

    def sites(self, keys: list[str]) -> dict[str, str]:
        return dict(self.call("existing", site_keys=keys)["sites"])

    def upsert(self, rows: list[dict]) -> None:
        self.call("upsert", rows=rows)

    def held(self, marker: str, limit: int) -> list[dict]:
        return list(self.call("held", marker=marker, limit=limit))

    def update_held(self, row_id: str, update: dict) -> None:
        self.call("update_held", id=row_id, update=update)
