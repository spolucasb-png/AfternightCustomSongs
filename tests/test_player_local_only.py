#!/usr/bin/env python3
"""Offline local-only boundary check for src/player_core.lua (+ thin loader).

The full-play path lives in player_core.lua. player_loader.lua is a one-shot
smoke bootstrap that loadstrings the core from the executor workspace.

Must hold on player_core (static):
- Zero executable references to outbound/server/persistence/score calls.
- No direct startSong() invocation. endSong is allowlisted at exactly one
  site (user-approved 2026-10-13): resolved from the gameplay module,
  called once with cleared=true, gated on the audio-clock end; createResults
  is never called directly and no score submission exists.
- Exactly one loadSong call site and exactly one Start-listener call site.
- abruptGameEnd via getfenv / rawget(env, ...) only.
- stageRemote forced nil; audio only from opts.audioFile via
  getcustomasset+Content.fromUri (no asset-ID literals).
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
    "startSong", "cancelSongStart", "createResults",
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
    ok = check("chart source uses quoted literal", 'string.format("%q", chartJson)' in core_src) and ok
    ok = check("old long-bracket chart embedding removed",
               '[=[" .. chartJson .. "]=]' not in core_src) and ok
    registered_at = core_src.find("-- Register cleanup before the first state-changing operation.")
    ctx_at = core_src.find("ctx = c", registered_at)
    mutation_at = core_src.find("-- 1. Ratings clone")
    ok = check("cleanup context registered before first mutation",
               registered_at >= 0 and ctx_at >= registered_at
               and mutation_at >= 0 and ctx_at < mutation_at) and ok
    ok = check("core no asset-ID literals", "rbxassetid" not in code) and ok
    ok = check("core audio gated on opts.audioFile",
               "opts.audioFile" in core_src) and ok
    ok = check("core audio resolves only via getcustomasset+Content.fromUri",
               "getcustomasset" in core_src
               and "Content.fromUri(getcustomasset(audioPath))" in core_src) and ok
    ok = check("core single Instrumental site (audio entry only)",
               code.count("Instrumental") == 1, str(code.count("Instrumental"))) and ok
    ok = check("core reports audio-resolve failure",
               '"audio-resolve-failed"' in core_src) and ok
    ok = check("core endSong resolved once from gameplay module",
               core_src.count('rawget(c.t21, "endSong")') == 1,
               str(core_src.count('rawget(c.t21, "endSong")'))) and ok
    ok = check("core endSong invoked once with cleared=true",
               code.count("endFn(true)") == 1) and ok
    ok = check("core never calls createResults directly",
               "createResults" not in code) and ok
    ok = check("core finish gated on audio clock",
               '"finishing"' in core_src and "timeLength" in core_src
               and "getSongPlayer" in core_src) and ok
    ok = check("core autoplay resolved once from gameplay module",
               core_src.count('rawget(t21, "SetAutoplay")') == 1) and ok
    ok = check("core autoplay enabled once", code.count("apFn(true)") == 1) and ok
    ok = check("core autoplay reset in teardown",
               'step("autoplay"' in core_src and "apFn(false)" in code) and ok
    ok = check("core no toggleAutoplay reference",
               "toggleAutoplay" not in code) and ok
    ok = check("core locator retries scan",
               "for _ = 1, tries do" in core_src
               and "task.wait(0.15)" in core_src) and ok
    ok = check("core records locator attempts",
               'rep.gates["locator-attempts"]' in core_src) and ok
    ok = check("core identity restored", "setthreadidentity(idBefore)" in code) and ok
    ok = check("core require wrap restored in teardown",
               'step("require"' in core_src
               and 'rawset(c.env, "require", c.prevReq)' in core_src) and ok
    ok = check("core resets idle flags during teardown",
               'step("idle-flags"' in core_src
               and 'rawset(c.t7, "loadedSong", false)' in core_src
               and 'rawset(c.t7, "inSong", false)' in core_src
               and 'rawset(c.t21, "inSong", false)' in core_src) and ok
    ok = check("core clears note pools and best-effort strum pools",
               'step("pools-notes"' in core_src
               and 'step("pools-strums"' in core_src
               and 'gcMod = gcMod' in core_src) and ok
    ok = check("core bumps audio-capable version", 'VERSION = "1.3.0"' in core_src) and ok
    ok = check("preflight avoids unconditional rejoin instruction", "rejoin first" not in core_src.lower()) and ok
    ok = check("core exports play/stop",
               "function M.play" in core_src and "function M.stop" in core_src) and ok
    ok = check("core anchors SV map at t0 (glitch fix)",
               "SV-map anchor" in core_src
               and 'table.insert(sv, 1, { startTime = 0, multiplier = 1 })' in core_src) and ok

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
