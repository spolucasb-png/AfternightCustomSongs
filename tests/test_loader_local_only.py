#!/usr/bin/env python3
"""Offline local-only boundary check for src/test_loader.lua.

Proves, at code level, that the staged harness cannot touch the server,
persistent storage, scores/results, or playback transport:

- No executable references to server/persistence/score/playback functions.
- No hooking/tampering primitives.
- Exactly one state-changing call site: parser(wrapper, {}, nil, nil),
  reached only through an explicit UI button.
- parseChart itself is never invoked directly (only resolved via safeGet).

This is STATIC evidence (the file contains no such calls). It does not
prove runtime behavior; the live run must still confirm transport/scores
unchanged via snapshot comparison. Run: python tests/test_loader_local_only.py
"""
import re
import sys
from pathlib import Path

LOADER = Path(__file__).resolve().parent.parent / "src" / "test_loader.lua"

# Anything that could reach the server, storage, scores, or transport.
FORBIDDEN = [
    # server boundary (reversal: sendServerEvent = NetworkFunctions+SongEvent)
    "sendServerEvent", "fireStageRemote", "SongEvent", "NetworkFunctions",
    "FireServer", "InvokeServer", "Fire", "Invoke",
    # playback / results / scores
    "startSong", "endSong", "cancelSongStart", "createResults",
    "ratingModule", "TriggerClip", "clearUp",
    # persistence (reversal: setSongData = SetData over SaveData/)
    "setSongData", "getSongData", "SetData", "GetData", "SaveData",
    # multi-stage chart calls excluded from the parse-only harness
    "addNotesFromChart", "addSectionsFromChart",
    # network / code loading / tampering primitives
    "HttpGet", "HttpPost", "request", "loadstring", "load",
    "getconnections", "hookfunction", "hookmetamethod", "newcclosure",
    "setreadonly", "getrawmetatable",
]


def strip_code(src):
    # long comments --[[ ... ]]
    src = re.sub(r"--\[=*\[.*?--\]=*\]", "", src, flags=re.S)
    # long strings [[ ... ]]
    src = re.sub(r"\[(=*)\[.*?\]\1\]", '""', src, flags=re.S)
    # short strings (single + double quoted, naive escape handling)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', src)
    src = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", src)
    # line comments (after strings are gone, -- starts a comment)
    src = re.sub(r"--[^\n]*", "", src)
    return src


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ((" - " + detail) if detail and not cond else ""))
    return cond


def main():
    try:
        src = LOADER.read_text(encoding="utf-8")
    except OSError as e:
        print("FAIL unreadable loader:", e)
        return 1
    code = strip_code(src)
    ok = True
    for name in FORBIDDEN:
        hits = [i + 1 for i, l in enumerate(code.splitlines())
                if re.search(r"\b" + re.escape(name) + r"\b", l)]
        ok = check("forbidden:" + name, not hits, "code lines " + str(hits)) and ok
    calls = [i + 1 for i, l in enumerate(code.splitlines())
             if re.search(r"\bparser\s*\(", l)]
    ok = check("single parser call site", len(calls) == 1, str(calls)) and ok
    direct = [i + 1 for i, l in enumerate(code.splitlines())
              if re.search(r"\bparseChart\s*\(", l)]
    ok = check("no direct parseChart() invocation", not direct, str(direct)) and ok
    ok = check("resolves parseChart via safeGet",
               'safeGet(state.module, "parseChart")' in src) and ok
    print("local-only boundary: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
