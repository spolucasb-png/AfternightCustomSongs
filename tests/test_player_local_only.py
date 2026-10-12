#!/usr/bin/env python3
"""Offline local-only boundary check for src/player_core.lua (+ thin loader).

The full-play path lives in player_core.lua. player_loader.lua is a one-shot
smoke bootstrap that loadstrings the core from the executor workspace.

Must hold on player_core (static):
- Zero executable references to outbound/server/persistence/score calls.
- No direct startSong()/endSong() invocation.
- Exactly one loadSong call site and exactly one Start-listener call site.
- abruptGameEnd via getfenv / rawget(env, ...) only.
- stageRemote forced nil; no Audio/Instrumental in registry entry.
- identity restored after game calls; require wrap restored in teardown.

player_loader must keep the session lockout and only loadstring the core file.
Run: python tests/test_player_local_only.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "src" / "player_core.lua"
LOADER = ROOT / "src" / "player_loader.lua"

FORBIDDEN = [
    "sendServerEvent", "fireStageRemote", "fireStageRemoteBatched",
    "SongEvent", "FireServer", "InvokeServer",
    "startSong", "endSong", "cancelSongStart", "createResults",
    "setSongData", "getSongData", "SaveData", "SubmitStats",
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
    ok = True
    try:
        core_src = CORE.read_text(encoding="utf-8")
        loader_src = LOADER.read_text(encoding="utf-8")
    except OSError as e:
        print("FAIL unreadable:", e)
        return 1

    code = strip_code(core_src)
    for name in FORBIDDEN:
        hits = [i + 1 for i, l in enumerate(code.splitlines())
                if re.search(r"\b" + re.escape(name) + r"\b", l)]
        ok = check("core forbidden:" + name, not hits, "code lines " + str(hits)) and ok

    loads = [i + 1 for i, l in enumerate(code.splitlines())
             if re.search(r"\bloadSong\s*\(", l)]
    ok = check("core single loadSong call site", len(loads) == 1, str(loads)) and ok
    starts = [i + 1 for i, l in enumerate(code.splitlines())
              if re.search(r'startFn\s*\(', l)]
    ok = check("core single Start-listener call site", len(starts) == 1, str(starts)) and ok
    ok = check("core abruptGameEnd via env",
               'rawget(c.env, "abruptGameEnd")' in core_src
               or 'rawget(env, "abruptGameEnd")' in core_src) and ok
    ok = check("core no bare abruptGameEnd() call",
               not re.search(r"(?<!\")\babruptGameEnd\s*\(", code)) and ok
    ok = check("core stageRemote forced nil", 'rawset(nf, "stageRemote", nil)' in core_src) and ok
    ok = check("core no Audio/Instrumental in registry",
               "Instrumental" not in code and not re.search(r"\bAudio\s*=", code)) and ok
    ok = check("core identity restored", "setthreadidentity(idBefore)" in code) and ok
    ok = check("core require wrap restored in teardown",
               "restoreRequire" in core_src and "doTeardown" in core_src) and ok
    ok = check("core exports play/stop",
               "function M.play" in core_src and "function M.stop" in core_src) and ok

    # Thin smoke loader: lockout + core bootstrap only.
    ok = check("loader lockout", "_G.AFNPlayerRan" in loader_src) and ok
    ok = check("loader reads afn_player_core.lua",
               'readfile("afn_player_core.lua")' in loader_src) and ok
    ok = check("loader calls core.play", "core.play" in loader_src) and ok
    ok = check("loader no direct loadSong",
               "loadSong" not in strip_code(loader_src)) and ok

    print("player local-only boundary: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
