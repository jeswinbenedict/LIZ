"""tool/symbolicate.py turns minified frames back into Dart locations.

A crash report from the release build is only useful if this is right, so
pin the decoder on a map small enough to check by hand.
"""

from __future__ import annotations

import importlib.util
import pathlib

_PATH = pathlib.Path(__file__).resolve().parents[2] / "tool" / "symbolicate.py"
_spec = importlib.util.spec_from_file_location("symbolicate", _PATH)
sym = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sym)


# Generated line 1: column 0 -> a.dart 1:1, column 10 -> a.dart 3:5 (name "boom").
# Generated line 2: column 4 -> b.dart 10:2.
MAP = {
    "version": 3,
    "sources": ["package:liz/a.dart", "package:liz/b.dart"],
    "names": ["boom"],
    # "AAAA" = [0,0,0,0]; "UAEIA" = [10,0,2,4,0]; "IACKC"... computed below
    "mappings": "AAAA,UAEIA;IC" + "OD",  # placeholder, replaced in test
}


def _encode(values):
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = ""
    for v in values:
        v = (-v << 1) | 1 if v < 0 else v << 1
        while True:
            digit = v & 31
            v >>= 5
            if v:
                digit |= 32
            out += chars[digit]
            if not v:
                break
    return out


def _map():
    line1 = ",".join([_encode([0, 0, 0, 0]), _encode([10, 0, 2, 4, 0])])
    # Relative to the previous segment: source +1, line +7 (2 -> 9), col -3 (4 -> 1).
    line2 = _encode([4, 1, 7, -3])
    return sym.SourceMap({**MAP, "mappings": f"{line1};{line2}"})


def test_vlq_round_trip():
    for values in ([0], [1, -1], [16, -16, 1000, -1000]):
        assert sym.decode_vlq(_encode(values)) == values


def test_lookup_takes_the_segment_at_or_before_the_column():
    m = _map()
    assert m.lookup(1, 1) == ("package:liz/a.dart", 1, 1, None)
    assert m.lookup(1, 11) == ("package:liz/a.dart", 3, 5, "boom")
    assert m.lookup(1, 50) == ("package:liz/a.dart", 3, 5, "boom")
    assert m.lookup(2, 5) == ("package:liz/b.dart", 10, 2, None)
    assert m.lookup(2, 1) is None
    assert m.lookup(9, 1) is None


def test_frames_in_a_stack_are_rewritten_in_place():
    out = sym.symbolicate(
        "TypeError: x\n    at a.b (https://liz.app/main.dart.js:1:11)\n    at c (main.dart.js:2:5)",
        _map(),
    )
    assert "package:liz/a.dart:3:5 (boom)" in out
    assert "package:liz/b.dart:10:2" in out
    assert "TypeError: x" in out
