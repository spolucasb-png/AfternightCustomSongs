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
    check("skin loader allowlisted once",
          code.count('rawget(t21, "loadNoteskin")') == 1)
    check("skin applied once", code.count('skinFn("R"') == 1)
    check("skin require wrapped in sprite env",
          'rawset(spriteEnv, "require"' in code)
    check("skin set-cache cleared in teardown",
          'rawget(t143, "noteSets")' in code)
    check("menu tab builder", "openMenuTab" in code and "closeMenuTab" in code)
    check("menu tab toggles", "toggleMenuTab" in code)
    check("menu in-menu toggle button (stats row clone)",
          "AFNToggle" in code and "ensureMenuToggle" in code
          and "destroyMenuToggle" in code and "startMenuWatcher" in code)
    check("menu rows are clones of the game's own SongTemplate",
          "found.tmpl:Clone()" in code and "found.search:Clone()" in code)
    check("menu clones stripped of scripts", "stripScripts" in code)
    check("menu row click hooks the row, not the hidden Cover",
          'FindFirstChild("Cover"' not in code and "r.MouseButton1Click" in code)
    check("menu leftovers swept by name on boot/cleanup",
          "MENU_PIECES" in code and "sweepMenuPieces" in code
          and "pcall(sweepMenuPieces, false)" in code)
    check("menu tab solo guard", "menuPlayerCount" in code)
    check("menu tab overlay", "AFNCustomTab" in code and "AFNPlay" in code)
    check("menu play late-bound (no forward-local nil)",
          "doPlayFn = doPlay" in code and "xpcall(doPlayFn" in code)
    check("menu play leaves the song-select (close tab, hide root)",
          "if menuTab ~= nil then" in code and "pcall(closeMenuTab)" in code
          and "r.Visible = false" in code)
    check("menu polish pieces present (mod row, header, favourites, preview)",
          "AFNModRow" in code and "AFNHeader" in code
          and "saveFavorite" in code and "startMenuPreview" in code
          and "stopMenuPreview" in code and "findMenuMusic" in code)
    # Session 22: rows are one per SONG. Chart files group by their source
    # (title, artist) metadata; each difficulty gets its own native-styled
    # button (renderDiffButtons) and its own preview; the Rayfield UI gets a
    # matching Difficulty dropdown.
    check("songs group charts by source metadata",
          "groupEntries" in code and "e.title = type(src.title)" in code
          and "e.diffLabel = type(src.difficulty)" in code
          and "e.group = g" in code)
    check("in-menu difficulty buttons render one per chart entry",
          "renderDiffButtons" in code and "ui.diffButtons" in code
          and "AFNDiff" in code)
    check("rayfield difficulty dropdown present",
          "diffDropdown" in code and "refreshDiffList" in code
          and "selectDiff(" in code and "suppressDiffPick" in code)
    # Session 23: multi-key charts (5-10K). Row validity is keyCount-driven;
    # wide charts skip the 4K custom skin (its packs lack wide-lane dirs)
    # and the summary surfaces synth chunking.
    check("wide charts accepted (keyCount-driven lane bounds)",
          "local kc = tonumber(song.keyCount) or 4" in code
          and "local laneLo, laneHi = kc, kc + pkc - 1" in code
          and "song.playerKeyCount" in code)
    check("wide charts follow the pack skin + borrow the stock centre Square",
          "stockSquareModule" in code and 'mine.Name = "Square"' in code
          and 'note = "square=stock"' in code and "square=fallback(Up)" in code
          and "default(wide:%dK)" not in code)
    # Play leaves the song-select through the object's own hide(), never via
    # the SetSongSelector listener (its Hide branch persists Favorites and
    # Recents). The listener is only read for its upvalues.
    check("leave-select helper present (hide, inSongSelect, blur fade)",
          "leaveSongSelect" in code and "ss:hide()" in code
          and '"inSongSelect", false' in code and "SettingsBlur" in code)
    check("SetSongSelector listener only read, never invoked",
          code.count("SetSongSelector") == 1
          and not re.search(r"\blst\s*\(", code)
          and not re.search(r"remoteListen\s*\)?\s*\[\s*\"SetSongSelector\"\s*\]\s*\(", code))
    check("no saved-data writes (Favorites / Recents / SetData)",
          '"Favorites"' not in code and '"Recents"' not in code
          and "SetData" not in code)
    check("leave-select called after a successful start",
          "pcall(leaveSongSelect, ctx, fromMenu)" in code)
    check("results screen cleared on Stop via the game's own clearUp",
          'step("results"' in code and "c.resultsRaised" in code
          and 'rawget(res, "clearUp")' in code
          and code.count("c.resultsRaised = true") == 1
          and code.count("clearUp(frame)") == 1)
    check("helpers sit above doTeardown (forward-only locals)",
          code.index("local leaveSongSelect, clearResultsScreen")
          < code.index("local function doTeardown"))
    check("sv flatten option", '"sv-flat"' in code
          and "ignoreSV" in code)
    check("teleport tamer present and multiplier-scoped",
          '"sv-tame"' in code and "TAME_THRESHOLD" in code
          and "TAME_CAP" in code
          and "e.multiplier = m > 0 and TAME_CAP or -TAME_CAP" in code)
    # Spawn hook (explicit user approval 2026-10-16): exactly one game-global
    # write (plus its svFunctions mirror), always restored on teardown, with
    # a copy-clamp fallback so a failed install never aborts the play.
    check("tame hook writes only the spawn-SV global",
          code.count("getSVFromTime = hook") == 2
          and "env.getSVFromTime = hook" in code)
    check("tame hook restores on teardown",
          'step("sv-hook"' in code
          and "env.getSVFromTime = h.orig" in code)
    check("tame hook falls back, never aborts",
          ")-fallback(hook:" in code)
    check("tame hook locates the Client chunk, not any line match",
          'findFnByLine(SVFN_LINE, 1, "Client")' in code)
    check("judge swap loop", '"judgeswap"' in code)
    check("judge swap event-driven", "DescendantAdded" in code)
    check("judge swap names", "FNF_Rating" in code and "FNF_Combo" in code)
    # Popup labels are destroyed per spawn (releaseChildrenToPool + t_1
    # destroy), so first sight carries birth truth; re-deriving the digit
    # from our own zeroed offset self-clobbers every nonzero digit to 0
    # within a tick (all-zeros session-15 bug). The marker must be a
    # boolean latch, never a revision stamp.
    check("judge swap latches once-only (no offset re-derive)",
          "rev ~= digit" not in code and "rev ~= imgS" not in code
          and '_AFNSwapped", true)' in code
          and 'SetAttribute("_AFNSwapped", imgS)' not in code
          and 'SetAttribute("_AFNSwapped", digit)' not in code)
    check("sustain clipping once", code.count('rawget(t21, "setSustainClipping")') == 1
          and code.count('clipFn("R", true)') == 1)
    check("sv map anchored at t0 (glitch fix)",
          "SV-map anchor" in src
          and "table.insert(sv, 1, { startTime = 0, multiplier = 1 })" in src)
    check("sv anchor reported", 'sv-anchor' in src and "_svAnchored" in src)

    print("rayfield local-only boundary: " + ("HELD (static)" if ok else "BROKEN"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
