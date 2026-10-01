"""Turn a minified crash report back into Dart files and lines.

    python tool/symbolicate.py main.dart.js.map < stack.txt
    python tool/symbolicate.py main.dart.js.map "at a.b (https://liz.app/main.dart.js:2:51234)"

The release build is minified, so a crash report in the admin console (or in
error_events) reads "main.dart.js:2:51234". Each deploy keeps that build's
source maps as a GitHub Actions artifact named `sourcemaps-<version>`, where
<version> is the `app_version` the report carries. Download it, then pipe the
stack through this script. Standard library only; reads source map v3.
"""

from __future__ import annotations

import bisect
import json
import re
import sys

_B64 = {c: i for i, c in enumerate(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")}

# "main.dart.js:2:51234", with or without a URL or parentheses around it.
_FRAME = re.compile(r"(?P<file>[\w./:-]*?main\.dart\.js):(?P<line>\d+):(?P<col>\d+)")


def decode_vlq(segment: str) -> list[int]:
    values, shift, value = [], 0, 0
    for ch in segment:
        digit = _B64[ch]
        value += (digit & 31) << shift
        if digit & 32:
            shift += 5
            continue
        values.append(-(value >> 1) if value & 1 else value >> 1)
        shift = value = 0
    return values


class SourceMap:
    def __init__(self, data: dict) -> None:
        self.sources = data.get("sources", [])
        self.names = data.get("names", [])
        # Per generated line: sorted generated columns, and what each maps to.
        self.lines: list[tuple[list[int], list[tuple]]] = []
        src = src_line = src_col = name = 0
        for line in data.get("mappings", "").split(";"):
            cols, targets, gen_col = [], [], 0
            for seg in filter(None, line.split(",")):
                v = decode_vlq(seg)
                gen_col += v[0]
                if len(v) >= 4:
                    src += v[1]
                    src_line += v[2]
                    src_col += v[3]
                    if len(v) >= 5:
                        name += v[4]
                        targets.append((src, src_line, src_col, name))
                    else:
                        targets.append((src, src_line, src_col, None))
                    cols.append(gen_col)
            self.lines.append((cols, targets))

    def lookup(self, line: int, column: int) -> tuple[str, int, int, str | None] | None:
        """1-based line, 1-based column (as browsers print them)."""
        if not 1 <= line <= len(self.lines):
            return None
        cols, targets = self.lines[line - 1]
        i = bisect.bisect_right(cols, column - 1) - 1
        if i < 0:
            return None
        src, s_line, s_col, name = targets[i]
        return (self.sources[src] if src < len(self.sources) else "?",
                s_line + 1, s_col + 1,
                self.names[name] if name is not None and name < len(self.names) else None)


def symbolicate(text: str, smap: SourceMap) -> str:
    def replace(m: re.Match) -> str:
        hit = smap.lookup(int(m.group("line")), int(m.group("col")))
        if hit is None:
            return m.group(0)
        source, line, col, name = hit
        source = source.replace("org-dartlang-sdk:///", "sdk:")
        return f"{source}:{line}:{col}" + (f" ({name})" if name else "")
    return _FRAME.sub(replace, text)


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    with open(argv[0], encoding="utf-8") as fh:
        smap = SourceMap(json.load(fh))
    text = " ".join(argv[1:]) if len(argv) > 1 else sys.stdin.read()
    print(symbolicate(text, smap))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
