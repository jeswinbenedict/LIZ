"""Environment-driven configuration.

Secrets never live in this repo: keys are read from the environment (GitHub
Actions secret, n8n credential, or a local shell export).

Two ways to write, one key each:

* SUPABASE_SERVICE_ROLE_KEY — GitHub Actions, which also runs jobs that need
  the whole database.
* LIZ_INGEST_KEY — the laptop n8n runs on. It opens the scraper-ingest
  function and nothing else: look up published tools, write new listings,
  re-try held ones. A lost laptop cannot read profiles or rewrite the catalog.
  When it is set it is used, even if a service key is also present.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

USER_AGENT = (
    "LizBot/1.0 (+https://liz.app/bot; AI tool discovery; contact: hello@liz.app)"
)

# Seconds to wait between requests to the same host, unless robots.txt asks for more.
DEFAULT_CRAWL_DELAY = 1.5

REQUEST_TIMEOUT = 20


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    service_role_key: str
    ingest_key: str = ""

    @property
    def rest_url(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/rest/v1"

    @property
    def ingest_url(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/functions/v1/scraper-ingest"

    @property
    def uses_ingest(self) -> bool:
        return bool(self.ingest_key)

    @property
    def configured(self) -> bool:
        """The service key: what the maintenance jobs (backfills, review,
        threats) need. They run in GitHub Actions, never on the laptop."""
        return bool(self.supabase_url and self.service_role_key)

    @property
    def can_scrape(self) -> bool:
        """Either key: enough for the scrape and retry_held."""
        return bool(self.supabase_url and (self.service_role_key or self.ingest_key))


def load_settings() -> Settings:
    return Settings(
        supabase_url=os.environ.get("SUPABASE_URL", "").strip(),
        service_role_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip(),
        ingest_key=os.environ.get("LIZ_INGEST_KEY", "").strip(),
    )
