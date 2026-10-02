"""Serves a Flutter web build the way the host does: files as they are, and
index.html for every other path, so /tools/x and /category/y load the app.

    python tool/qa/serve.py build/web 8100
"""

from __future__ import annotations

import functools
import http.server
import os
import sys


class SpaHandler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        if not os.path.isfile(self.translate_path(self.path)):
            self.path = "/index.html"
        return super().send_head()

    def log_message(self, format, *args):  # noqa: A002 — the base class's name
        pass  # quiet: CI logs should show the checks, not every request


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8100
    handler = functools.partial(SpaHandler, directory=root)
    with http.server.ThreadingHTTPServer(("localhost", port), handler) as server:
        print(f"serving {root} on http://localhost:{port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
