"""Environment-driven configuration.

Secrets never live in this repo: the service-role key is read from the
environment (GitHub Actions secret, n8n credential, or a local shell export).
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

    @property
    def rest_url(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/rest/v1"

    @property
    def configured(self) -> bool:
        return bool(self.supabase_url and self.service_role_key)


def load_settings() -> Settings:
    return Settings(
        supabase_url=os.environ.get("SUPABASE_URL", "").strip(),
        service_role_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip(),
    )
