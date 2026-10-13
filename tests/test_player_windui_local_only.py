#!/usr/bin/env python3
"""Static local-only boundary for src/player_windui.lua.

UI may loadstring ONLY the local vendor (afn_windui.lua) and player_core
(afn_player_core.lua). No HTTP, no remotes, no direct loadSong/startSong.
Play/Stop must go through core.play / core.stop.
Run: python tests/test_player_windui_local_only.py
"""
import re
import sys
from pathlib import Path

UI = Path(__file__).resolve().parent.parent / "src" / "player_windui.lua"

FORBIDDEN = [
    "sendServerEvent", "fireStageRemote", "SongEvent",
    "FireServer", "InvokeServer",
    "startSong", "endSong", "createResults",
    "setSongData", "getSongData", "SaveData", "SubmitStats",
    "HttpGet", "HttpPost", "request",
    "getconnections", "hookfunction", "hookmetamethod",
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
        src = UI.read_text(encoding="utf-8")
    except OSError as e:
        print("FAIL unreadable:", e)
        return 1
    code = strip_code(src)
    ok = True
    for name in FORBIDDEN:
        hits = [i + 1 for i, l in enumerate(code.splitlines())
                if re.search(r"\b" + re.escape(name) + r"\b", l)]
        ok = check("forbidden:" + name, not hits, str(hits)) and ok

    # loadstring only for local vendor + core filenames
    loads = [l.strip() for l in code.splitlines() if re.search(r"\bloadstring\s*\(", l)]
    ok = check("loadstring sites <= 2", len(loads) <= 2, str(loads)) and ok
    ok = check("reads afn_windui.lua", 'readfile("afn_windui.lua")' in src
               or "readfile(WINDUI_FILE)" in src) and ok
    ok = check("reads afn_player_core.lua", 'readfile(CORE_FILE)' in src
               or 'readfile("afn_player_core.lua")' in src) and ok
    ok = check("play via core.play", "core.play" in src or "state.core.play" in src) and ok
    ok = check("stop via core.stop", "core.stop" in src or "state.core.stop" in src) and ok
    ok = check("no direct loadSong call",
               not re.search(r"\bloadSong\s*\(", code)) and ok
    ok = check("charts dir AfternightCustomSongs/Charts",
               "AfternightCustomSongs/Charts" in src) and ok
    ok = check("re-exec cleanup registered",
               "_G.AFNPlayerUICleanup" in src) and ok
    ok = check("Play runs preflight internally", "state.core.preflight()" in src) and ok
    ok = check("no standalone Preflight button", 'Title = "Preflight"' not in src) and ok
    ok = check("Tap Test tab removed", 'Title = "Tap Test"' not in src) and ok
    ok = check("simple UI has Chart/Refresh/Play/Stop",
               all(f'Title = "{name}"' in src for name in ("Chart", "Refresh", "Play", "Stop"))) and ok
    ok = check("successful Stop offers another chart", "Ready for another chart" in src) and ok
    ok = check("successful Stop has no mandatory rejoin copy", "Rejoin before another Play" not in src) and ok
    ok = check("audio dir AfternightCustomSongs/Audio",
               "AfternightCustomSongs/Audio" in src) and ok
    ok = check("audio passed to core.play", "audioFile" in src) and ok
    ok = check("audio dropdown present", 'Title = "Audio"' in src) and ok
    ok = check("audio auto-match by chart stem", "automatchAudio" in src) and ok
    ok = check("no asset-ID literals", "rbxassetid" not in code) and ok
    ok = check("boot splash present", 'AFN-Loading' in src) and ok
    ok = check("splash created before vendor load",
               src.find('AFN-Loading') < src.find('readfile(WINDUI_FILE)')) and ok
    ok = check("splash hidden on every abort path",
               src.count('hideSplash()') >= 4) and ok
    ok = check("splash hidden once ready",
               'hideSplash()' in src.split('refreshDropdown()\nsetStatus("Loading player core...")')[1]
               if 'refreshDropdown()\nsetStatus("Loading player core...")' in src else False) and ok
    ok = check("splash parented to PlayerGui (no gethui)",
               'FindFirstChildOfClass("PlayerGui")' in src and "gethui" not in code) and ok
    print("player windui local-only: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
