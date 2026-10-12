#!/usr/bin/env python3
"""Offline local-only boundary check for src/player_loader.lua.

The full-play loader necessarily touches MORE engine surface than the
parse-only harness, so it gets its own allowlist-checked boundary:

Must hold (static):
- Zero executable references to outbound/server/persistence/score calls:
  sendServerEvent, fireStageRemote*, SongEvent, FireServer, InvokeServer,
  HttpGet/request/loadstring, getconnections/hookfunction/hookmetamethod,
  setSongData/getSongData/SaveData, SubmitStats/score submission.
- No direct startSong()/endSong() invocation (only type checks via
  string literals, which the stripper removes).
- Exactly one loadSong call site (direct, under xpcall) and exactly one
  remoteListen["Start"] call site.
- abruptGameEnd + leaveLoadingState reached only via getfenv(loadSong)
  (rawget(env, ...)), never as bare globals that could resolve elsewhere.

Static evidence only; the live run must still confirm behavior.
Run: python tests/test_player_local_only.py
"""
import re
import sys
from pathlib import Path

LOADER = Path(__file__).resolve().parent.parent / "src" / "player_loader.lua"

FORBIDDEN = [
    # outbound server calls (any spelling)
    "sendServerEvent", "fireStageRemote", "fireStageRemoteBatched",
    "SongEvent", "FireServer", "InvokeServer",
    # playback entry points we must NOT invoke directly
    "startSong", "endSong", "cancelSongStart", "createResults",
    # persistence / scores
    "setSongData", "getSongData", "SaveData", "SubmitStats",
    # network / code loading / tampering primitives
    "HttpGet", "HttpPost", "request", "loadstring",
    "getconnections", "hookfunction", "hookmetamethod", "newcclosure",
    "setreadonly", "getrawmetatable", "getrenv",
]


def strip_code(src):
    src = re.sub(r"--\[=*\[.*?--\]=*\]", "", src, flags=re.S)
    src = re.sub(r"\[(=*)\[.*?\]\1\]", '""', src, flags=re.S)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', src)
    src = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", src)
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
    loads = [i + 1 for i, l in enumerate(code.splitlines())
             if re.search(r"\bloadSong\s*\(", l)]
    ok = check("single loadSong call site", len(loads) == 1, str(loads)) and ok
    starts = [i + 1 for i, l in enumerate(code.splitlines())
              if re.search(r'startFn\s*\(', l)]
    ok = check("single Start-listener call site", len(starts) == 1, str(starts)) and ok
    ok = check("abruptGameEnd via getfenv only",
               'rawget(env, "abruptGameEnd")' in src) and ok
    ok = check("no bare abruptGameEnd() call",
               not re.search(r"(?<!\")\babruptGameEnd\s*\(", code)) and ok
    ok = check("single-attempt lockout", "_G.AFNPlayerRan" in src) and ok
    ok = check("stageRemote forced nil", 'rawset(nf, "stageRemote", nil)' in src) and ok
    ok = check("no Audio in registry entry", "Instrumental" not in code) and ok
    ok = check("identity restored after game calls",
               "setthreadidentity(idBefore)" in code) and ok
    ok = check("require wrap restored in teardown",
               re.search(r"function teardown\(\).*?restoreRequire\(\)", code, re.S) is not None) and ok
    print("player local-only boundary: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
