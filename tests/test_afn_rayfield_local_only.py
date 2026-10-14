#!/usr/bin/env python3
"""Offline local-only boundary check for src/afn_rayfield.lua (Rayfield edition).

Allowlist: one Rayfield HttpGet (UI library, rule-lifted 2026-10-14),
loadSong direct call, Start listen fn, one endSong(true) (user-approved),
SetAutoplay on/off pair. Everything game-server/persistence/score/hook
shaped is forbidden in executable code.
Run: python tests/test_afn_rayfield_local_only.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "afn_rayfield.lua"

FORBIDDEN = [
    "sendServerEvent", "fireStageRemote", "fireStageRemoteBatched",
    "SongEvent", "FireServer", "InvokeServer",
    "startSong", "cancelSongStart", "createResults",
    "setSongData", "getSongData", "SaveData", "SubmitStats",
    "HttpPost", "request",
    "getconnections", "hookfunction", "hookmetamethod", "newcclosure",
    "setreadonly", "getrawmetatable", "getrenv",
]


def strip_code(text):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("--"):
            continue
        out.append(line)
    return "\n".join(out)


def main():
    src = SRC.read_text(encoding="utf-8")
    code = strip_code(src)
    ok = True

    def check(name, cond):
        global ok
        nonlocal_ok = cond
        print(("PASS " if cond else "FAIL ") + name)
        if not cond:
            ok = False
        return cond

    for ident in FORBIDDEN:
        check(f"no {ident}", ident not in code)
    check("exactly one HttpGet (Rayfield)",
          len(re.findall(r"HttpGet\s*\(", code)) == 1)
    check("rayfield source url", "sirius.menu/rayfield" in code)
    check("single endSong(true) site", code.count("endFn(true)") == 1)
    check("autoplay on site", code.count("apFn(true)") == 1)
    check("autoplay reset site", code.count("apFn(false)") == 1)
    check("loadSong source line", "8058" in code)
    check("safe %q chart embedding", "%q" in code)
    check("abruptGameEnd teardown", "abruptGameEnd" in code)
    check("audio via getcustomasset only",
          "getcustomasset" in code or "getlocalasset" in code)
    check("no rbxassetid literals", "rbxassetid" not in code.lower())
    check("sv map anchored at t0 (glitch fix)",
          "SV-map anchor" in src
          and "table.insert(sv, 1, { startTime = 0, multiplier = 1 })" in src)
    check("sv anchor reported", 'sv-anchor' in src and "_svAnchored" in src)

    print("rayfield local-only boundary: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
