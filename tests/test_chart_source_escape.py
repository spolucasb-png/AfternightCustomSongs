#!/usr/bin/env python3
"""Regression vectors for the Luau %q chart-source contract.

This is an offline model plus a source-contract check, not a Luau interpreter
test. It verifies the production code uses %q and that representative escaped
payloads round-trip as a single quoted string literal.
"""
import ast
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent / "src" / "player_core.lua"


def model_lua_q(value):
    """Small %q-compatible encoder for adversarial ASCII regression vectors."""
    out = ['"']
    short = {"\\": "\\\\", '"': '\\"', "\n": "\\n",
             "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f"}
    for ch in value:
        if ch in short:
            out.append(short[ch])
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def test_source_uses_percent_q_and_not_long_brackets():
    src = CORE.read_text(encoding="utf-8")
    assert 'chartMod.Source = "return " .. string.format("%q", chartJson)' in src
    assert '[=[" .. chartJson .. "]=]' not in src


def test_adversarial_strings_round_trip_as_one_literal():
    payloads = [
        '{"song":{"song":"x]=]","notes":[]}}',
        '{"song":{"song":"double \\" quote","notes":[]}}',
        '{"song":{"song":"backslash \\\\ test","notes":[]}}',
        '{"song":{\n"song":"line one\\nline two\\r\\t","notes":[]}}',
        '{"song":{"song":"quote + terminator \\" ]=]","notes":[]}}',
    ]
    for payload in payloads:
        literal = model_lua_q(payload)
        source = "return " + literal
        assert source.startswith('return "') and source.endswith('"')
        assert ast.literal_eval(source[len("return "):]) == payload
        # The long-bracket terminator may appear only within the quoted literal.
        if "]=]" in source:
            start, end = source.index('"'), source.rindex('"')
            assert start < source.index("]=]") < end


if __name__ == "__main__":
    tests = [test_source_uses_percent_q_and_not_long_brackets,
             test_adversarial_strings_round_trip_as_one_literal]
    for test in tests:
        test()
        print("PASS", test.__name__)
    print(f"{len(tests)}/{len(tests)} passed (offline model; not Luau runtime proof)")
