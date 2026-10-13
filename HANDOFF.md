# Handoff (AfternightCustomSongs)

## Current state (2026-10-12 — session 6; replay reset code, live verification pending)

The full-play core and WindUI chart picker are implemented; UI boot and
three-chart discovery are recorded live, and a full-play smoke path succeeded in
session 4. This change adds a `forceIdle` cleanup attempt for idle flags and pool
tables plus a simplified Chart / Refresh / Play / Stop UI. Same-session replay
is NOT yet live-verified. Table clearing cannot prove orphaned Roblox Instances,
render bindings, camera, or HUD state are restored; rejoin only if Stop remains
`cleanup-incomplete` after retry until live evidence establishes a stronger
recovery contract. The player's boundary is non-invocation, not strict network
silence: see the documented indirect `UpdPreferences`/`Sync` side effect below.

## Save protocol

Sessions can end abruptly. After every meaningful step, update this file and
`ROADMAP.md`. Do not commit unless the user explicitly approves. Never claim a
runtime result without a live observation behind it. Every live claim below
cites the probe or test that produced it.

## Current state (session 1, 2026-10-12)

Independent repo at `Referencesandmods/AfternightCustomSongs` (local git, no
remote). Baseline commit `d825804`: 16 probes, synth fixture + offline test
(7/7), README, spike-status doc. Empty `src/` + `converters/` (no loader).

Target: Project Afternight, PlaceId `13042495892` (name "Ugc"). Executor:
Madium only. Server-cleanliness desired, not required. Chart schema frozen
only on the Gakuran side; Afternight format follows engine evidence.

## What the spike established (all read-only unless noted)

- Engine: FNF-style gameplay module, ~120 methods (`probe_c`). Native SV
  (`svFunctions`: `getPosFromTime`, `getPosFromTimeSV`, `getSVFromTime`,
  `getSpeed`, `mapVelocityChanges`, `sliderVelocities`) — `probe_d`.
- Notes live in `Notes` / `UnspawnedNotes` pools; `strumTime` in ms on the
  Conductor axis; lanes 0–7 (opponent 0–3 / player 4–7), `column` mirrors lane;
  sustains are segment chains (`isSustain`, `susLength`, `prevNote`,
  `totalSustains`) — `probe_n`, `probe_n2`.
- Native rows are `[timeMs, lane, sustainMs]`; sections carry
  `{id, mustHitSection, sectionNotes}` (`probe_h`).
- Conductor: `BPM`/`BaseBPM` = base tempo, `CurBPM` = live tempo, `Offset` in
  seconds, `BPMChangeMap` + tempo-change events (`probe_t`, `probe_s`).
- SV entries are `{startTime, multiplier}` — Quaver-identical shape
  (`probe_t`). Gakuran discovery shapes find nothing here.
- Caller evidence (`probe_i`): one orchestrator references `parseChart` +
  `addNotesFromChart` + `addSectionsFromChart` + `createNote`; `parseChart`
  does not reference the spawners in constants (but see correction below).
- `getinfo` line markers match Claude's decompile refs to the line
  (parseChart 5287, addNotesFromChart 5053, createNote 4761).
- Lane routing (from decompile model, matches all live data): lanes 4–7 +
  `mustHit=false` → player side R cols 0–3; lanes 4–7 + `mustHit=true` →
  opponent side L.

## Test history
- **Test A** (addNotesFromChart-only, idle): clean failure,
  `nil with 'KeyCount'`, zero state change. Verdict: missing strumline
  context, not schema rejection.
- **Test A2** (parse → sections → notes, wrapper `{song=chart}`):
  parseChart OK, built 8 Strums + 2 Strumlines; `addSectionsFromChart`
  rejected the wrapper (`nil.notes` — likely wants the song subtable);
  **4/4 notes created by parseChart itself** (timestamps/lanes unverified —
  sampler gated on stage 3, fixed next time). Pools + Conductor/SV restored
  and verified; strums/strumlines persist (userdata, unrestorable by hand).
- **Correction:** parseChart evidently spawns via an aliased internal call —
  constant cross-referencing misses localized calls. Caller evidence is
  necessary but not sufficient; trust staged observation over it.
- **Test B2-min (parse-only, direct) — PASS, 2026-10-12.** On a rejoined
  idle engine (pools 0/0/0/0): `parseChart(wrapper, {}, nil, nil)` ok, built
  8 Strums + 2 Strumlines and exactly 4 UnspawnedNotes — times
  1200/1800/2400/3000, rawLanes 4/5/6/7 → columns 0/1/2/3, dirs
  Left/Down/Up/Right, `side="R"` + `mustPress=true` on all four
  (player-side routing now LIVE-PROVEN, not model-inferred). Pools wiped to
  0/0 in place, Conductor numerics + BPM/SV maps restored and verified.
  Strums/strumlines persist (expected) → rejoin required before next test.
  The WindUI loader window from this session is stale: do NOT press its Run
  (would double-parse); rejoin instead.

## Pending right now

1. User rejoins the client (Test A2's strums persist; pristine idle needed).
2. Then **first live harness run** (`src/test_loader.lua`, staged uncommitted —
   see "Staged harness" below): Inspect/Preflight → one gated Run → Cleanup →
   rejoin. Pass = 4 notes R/0–3 @1200/1800/2400/3000; PARTIAL also acceptable
   as evidence (taps/time/columns without observable side field).
3. After taps verify: sustain test, SV test, BPM test (one mechanic each),
   then the `src/` adapter decision.

## Staged harness (session 2, 2026-10-12 — NOT executed, NOT committed)

- Source: user-supplied `afternight_test_loader.lua`, saved as
  `src/test_loader.lua` (SHA256-verified identical copy, plus one
  behavior-preserving fix: the deferred log-scroll now runs inside `pcall`
  so closing the UI before it fires cannot throw).
- Preserved core: exactly one `parser(wrapper, {}, nil, nil)` call site
  (verified by scan), wrapper byte-matching
  `fixtures/afn_synth_a_taps.chart.json` (id, bpm 200, keyCount/
  playerKeyCount 4, one `mustHitSection=false` section, rows
  1200/1800/2400/3000 lanes 4–7, events empty).
- Verified absent from executable code (comment/string mentions only): zero
  calls to `addNotesFromChart`, `addSectionsFromChart`, `startSong`,
  `endSong`, remotes, HTTP, `loadstring`, `require`. Native Roblox instances
  only; no UI library, no downloads. Preflight + test both PlaceId-gated to
  `13042495892`; single-attempt lockout (`state.ran`) per client session.
- Supersedes the old 3-stage B2: the forensic audit found B2 internally
  inconsistent (mixed `wrapper` vs `wrapper.song` args; `addNotesFromChart`
  after a spawning `parseChart` risks duplicates), so the harness runs
  parse-only (B2-min). `add_*` shapes remain separate future experiments.
- Cleanup reviewed: restores pools (identity-preserving), Conductor scalars,
  `BPMChangeMap`, `lastBPMChange`, `sliderVelocities`, with serialized
  verify; deliberately leaves Strums/Strumlines/Maps untouched and labels
  the residue EXPECTED/UNRESTORED. **Pool-clear is never a clean session —
  rejoin is mandatory and the UI says so at every stage.**
- Compat: `+=`, `getgc(true)`, `gethui` all previously evidenced live
  (`probe_n`-family, `probe_a`); `task.defer` is standard Roblox (UI-scroll
  only, now pcall-guarded); `Draggable` is deprecated-but-functional, left
  as-is. No fixes were needed beyond the defer guard.
- Standing: staged file + doc updates are uncommitted per instruction;
  Gakuran repo verified untouched (`git status` clean apart from its
  pre-existing untracked `experiments/`).
- Local-only boundary (session 2): server/persistence/score access is
  prevented by never invoking it, NOT by hooking the network (no
  getconnections/hookfunction anywhere in the harness). Codified in
  `tests/test_loader_local_only.py` — 37/37 checks pass: zero executable
  references to sendServerEvent/fireStageRemote/SongEvent/startSong/endSong/
  setSongData/SaveData/add_* /HTTP/loadstring/hook primitives; exactly one
  parser call site via safeGet. Static evidence only; the live run must
  still confirm transport/scores unchanged via snapshots.
- Loader prototype, half 1 (session 2, offline only): `converters/osu_to_afn.py`
  converts osu!mania to `{song:...}` wrappers (ms rows, lanes 4-7,
  mustHit=false, verbatim SV with last-wins, >4K fold, single-BPM with loud
  multi-red warning, no-overwrite outputs). `tests/test_osu_to_afn.py` 3/3.
  Timing math follows osu2gakuran (reference-only, reimplemented — no
  Gakuran imports). Half 2 (in-game file staging + inject) waits for the
  tap-test verdict. UI stays native: catalog libs (WindUI/Maclib/Rayfield/
  LinoriaLib) all require downloading external code, which violates the
  local-only rule, and multiply the Instance-touch surface that already
  throws on some executor threads.

## Standing rules

- Idle engine + pre/post snapshots for every state-changing call.
- One attempt per approval; stop on first error, no permutation sweeps.
- No `startSong` (server remote), no scores, no hooks, no files in game.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: never
  modify its production code, converters, charts, or outputs.
- Workspace probe files (`afn_probe_*`) cannot be deleted remotely (no
  `delfile`); they are inert and clearly named. Repo `experiments/` copies
  are canonical.


## Session 3 (2026-10-12) — full-play path recon (read-only, no state change)

- Decompile works from Madium: `decompile(Players.LocalPlayer.PlayerScripts.Client)` -> 502,401 bytes / 15,644 lines (it is a LocalScript). This supersedes "no game-code decompiler" under Known limits. Decompile line numbers differ from `debug.info` source lines: loadSong = decompile 12548 / source 8058; `LoadSong` listener = decompile 15194 / source 9840.
- `afn_recon4.lua` (executor workspace) ran live on an idle engine (t_7.loadedSong=false, inSong=false). loadSong upvalues: 3 = ENGINE `t_1`, 5 = STATE `t_7`, 6 = MODULE `t_21` (identical to the gc module; has startSong / beginCountdown / endSong). `t_1.songIds[ModName] = { Songs = { [songName] = { Audio = {...} } } }` (sample: "Super Funkin' Galaxy" -> "MAJOR BURROWS"). `t_1.ChartFixing` = { fixChart, fixEvents }. Conductor exposes setSongPos / changeBPM. SongPlayer exposes new / setPosition / Resume / etc.
- loadSong contract (read from decompile 12548-12960, NOT yet exercised live): `loadSong(arg325, side "L"|"R", rate, stageModel, t17, playerIdx, players, ?, ?)`.
  - `arg325.Chart`: ModuleScript whose `require()` returns a JSON *string*; it is JSONDecoded, then `ChartFixing.fixChart(result, Chart.Name)`. Chart.Name is the difficulty. loadSong re-parents Chart's children into a new Folder.
  - `arg325.Song`: Instance (Name, optional `DisplayName` attribute). `arg325.Mod`: Instance (Name, optional `Metadata` child module). `arg325.ModchartsEnabled` / `GimmicksEnabled` flags.
  - `t_1.songIds[Mod.Name].Songs` is indexed unguarded, and `SongInfo.Audio` is read -> the registry entry must exist first.
  - `t17` and `players` must be `{L={},R={}}`-shaped tables.
  - `stageModel` nil => v23 (singleplayer flag) false and `stageRemote` nil. Unverified whether the rest of loadSong tolerates a nil stage (cameras table `t_11`).
- Not yet read: decompile 12960+ (Events module, audio load from SoundInfo.Audio, camera/stage use, parseChart call, render-step bind), plus the `Start` listener / beginCountdown / startSong.
- Rule tension to resolve before any live run: Standing rules say "no startSong". The decompile suggests the server notification inside startSong is gated on v23, so with v23 false it may be skippable. Verify in the decompile before calling it.
- loadSong is far heavier than parseChart-only (disables PlayerControls and StageZones, builds HUD/camera, reparents instances). Treat every live attempt as rejoin-required.

## Session 4 (2026-10-12) — local-play contract closed, loader built (no live run yet)

All reads below are from decompile sources saved in
`experiments/decompiled/` (byte-exact via in-executor `decompile()` +
`writefile`, live client PID 15352, PlaceId 13042495892). Live claims cite
the recon script that produced them.

### Q-answers (read from source, then verified live where noted)
- **Q1 `add(nil)` — SAFE.** `afn_decomp_ScriptPack.lua:146-149`:
  `function t.add(t8, arg2, b1) if not arg2 then return end`.
  Every NoteGroup/ForcedModchart/Modchart lookup is a no-op.
- **Q2 asset fetch — CONFIRMED server-on-miss, mitigated.**
  `afn_decomp_AssetReplicator.lua:239-311`: container hit returns with no
  traffic; miss does `RequestEvent:FireServer` + yields up to 5 s.
  Live (`afn_recon6.lua`): `__AssetContainer/Ratings` holds ONLY
  "Afternight", no "Countdowns" category. Live settings
  (`afn_recon7.lua`): `JudgementStyle="Custom"`, `HideLobby=false`,
  `BackgroundDim=1`, `FakeOpponentInput=true`, `HideCharacters=false`.
  Mitigations in loader: `SkipCountdown=true` (skips BOTH Countdowns
  lookups: loadSong decompile 13247 + beginCountdown's) and pre-clone
  Ratings/Afternight -> Ratings/Custom (cache hit, removed on teardown).
- **Q3 map block — NO-OP for these settings.** Else-branch taken
  (`MapService.Stage=nil`), no map calls. Loader still gates
  `HideLobby==false` + `BackgroundDim>0.05` and aborts otherwise.
- **Q4 fireServer — NOT wrapped** (no explicit approval; rule ambiguity
  stands). Residual: `CharReplicator.SetSettings` fires "UpdPreferences"+
  "Sync" ONCE when `loadStageCharacters` flips true->false (live t_2 read
  in `afn_recon7.lua`; left flipped, next real loadSong repairs it).
  `PlayerDeath`/`PlayerReset` only on death/reset/hitch — accepted, no
  death expected (4 misses, GhostTapping=true).
- **Q5 stop — `abruptGameEnd` via `getfenv(loadSong)`.**
  `afn_recon6.lua`: `getfenv(loadSong)` resolves; `abruptGameEnd`,
  `clearUp`, `beginCountdown`, `onUpdate` all functions. `endSong` is NOT
  a server path (body = createResults + clearUp, no remotes) but stays
  unused. Audio-free plays never self-terminate (decompile 11269 needs
  `not v90.paused`); loader stops via abruptGameEnd after ~3 s observe.
- **Q6 audio — audio-free first.** `SoundInfo=nil` => `v90:load` skipped
  => `Resume()` early-returns (`curAudio==nil`) => Conductor free-run
  branch (`updateConductor`, decompile 9564). `_CachedAudio=30` attribute
  on the Chart keeps timebar math sane.
- **New, not in prior summary:**
  - `NetworkFunctions.fireStageRemote*` nil-guard at source top
    (`afn_decomp_NetworkFunctions.lua`); `stageRemote` written once
    (loadSong, `v20 and FindFirstChild("Hits") or nil`); live nil.
  - `LoadingScreen.start` (afn_decomp_Loading.lua:170-174) Invokes
    `GetPreviewOverheadData` per non-bot side. Mitigation: pre-flip
    `enterLoadingState({Sides={L={},R={}}})` (v85 guard shared with
    `leaveLoadingState`, decompile 791-815) so loadSong's call returns
    early. Teardown always calls `leaveLoadingState` (no-op if already).
  - `CharacterModule.new` -> `LoadAnim` -> `Replicate("LoadAnim")` fires
    `Main.Character:FireServer` (afn_decomp_Character.lua:955-966,
    1331-1344). `Main.Character` used NOWHERE else (grep: 1 site).
    Mitigation: relocate it to a temp folder during the run, restore +
    verify in teardown.
  - Emote char (`t_245`) carries NO remote => its Replicate calls no-op.
  - `DescriptionReady=true` live — no unbounded wait.
  - `getfenv`/`debug.setupvalue` available; v963==false live (clean).
  - `getBotAppearance(getRandomFriend())` for the emote char is UNREAD —
    accepted risk (platform API, not game server), noted for the run.

### Built (session 4) — first live run GREEN (see ROADMAP §7)
- `src/player_loader.lua` was the one-shot smoke (now a thin wrapper).
- Live fixes: require-wrap for executor ModuleScripts; identity 2 for HUD.
- Decompile evidence in `experiments/decompiled/` (9 modules).

## Session 5 (2026-10-12) — WindUI player panel

Continued from Muse Spark / Claude handoff: put the full-play loader into
the vendored WindUI library UI with a local chart picker.

### Built (uncommitted)
- `src/player_core.lua` — callable API: `preflight()`, `play(opts)`,
  `stop()`, `normalizeChart()`. `keepAlive=true` leaves the song running
  until Stop; default smoke path observes ~3s then tears down. Accepts
  engine wrappers `{song:{...}}` and flat `{notes:[{time_ms,lane,hold_len}]}`.
- `src/player_loader.lua` — thin one-shot: reads `afn_player_core.lua`,
  plays synth fixture, `_G.AFNPlayerRan` lockout.
- `src/player_windui.lua` — WindUI window (Gakuran-style §0 / §0.5 only):
  capability check, re-exec cleanup, Tab **Play** with Chart dropdown
  (scans `AfternightCustomSongs/Charts`), Refresh / Preflight / Play /
  Stop. Play calls `core.play({keepAlive=true})`. Vendor = local
  `afn_windui.lua` (AFN-P1/P2/P3); the current player configuration does not
  enable the vendor's dormant HTTP-fetch, key-system or remote-asset paths.
  This is configuration-specific, not a blanket vendor guarantee.
- Charts staged in Madium workspace
  `AfternightCustomSongs/Charts/`:
  `afn_synth_a_taps.chart.json`, `easy_001.chart.json`,
  `afn_camp_hard_2_35_3_14_normal.chart.json` (from Camp .osu via
  `converters/osu_to_afn.py`). 2FAR .osu has no hit objects (skipped).
- Tests: `test_player_local_only.py` HELD (core + thin loader);
  `test_player_windui_local_only.py` HELD; tap harness still HELD.

### Deploy (Madium Workspace)
- `afn_player_core.lua`, `afn_player_loader.lua`, `afn_player_windui.lua`,
  `afn_windui.lua` (vendor).

### How to run
1. Rejoin Afternight (clean idle — no strum residue from prior plays).
2. `madium.run_executor_file` → `afn_player_windui.lua` (pid of client).
3. Preflight → pick chart → Play → hit notes → Stop → rejoin.

### Live this session (PID 15352)
- `afn_player_windui.lua` boot OK: `[AFN-PlayerUI] UI ready`, PlaceId
  13042495892, `Charts found: 3`, `player_core 1.1.0 ready`, dropdown
  selected `afn_camp_hard_2_35_3_14_normal.chart.json`.
- Play/Stop of a picked chart: not clicked yet this session (rejoin if
  prior strum residue; session 4 already proved core play on synth).

### Hardening (review patch, same day)
- Chart ModuleScript source uses `string.format("%q", chartJson)` (no
  fixed `[=[` embedding). Offline adversarial escape test added.
- Play teardown is transactional: cleanup `ctx` registered before the
  first mutation; per-resource retryable steps; Stop refused while
  `phase=="preparing"`; incomplete cleanup retains `ctx` for retry.
- Docs/ROADMAP clarify non-invocation vs strict network silence.
- Converter: same-timestamp red timing points keep file order.

### Live Madium test (PID 26420, after hardening commit `5431890`)
- Fresh idle: PlaceId 13042495892, pools 0/0/0/0, `DescriptionReady`.
- WindUI boot OK: 3 charts, `player_core 1.1.0 ready`.
- Programmatic `core.play` synth wrapper, `keepAlive=false`, observe 3s:
  `load_ok` / `start_ok`; after load UnspawnedNotes=4 Strums=8
  Strumlines=2; Conductor YES (-92 → 2422 ms); note0 R/col0 @1200
  mustPress; stage `done-cleaned`; every teardown step `ok`
  (abruptGameEnd, leaveLoadingState, require, charRemote, ratings,
  registry, holder); `playing_after=false`.
- Live `%q` adversarial payload with `]=]` in song title: loadstring
  round-trip OK (`return "` form).
- Post-teardown pools observed 0/0/0/0 and residue preflight passed
  this run (unlike earlier sessions that required rejoin for strum
  residue). Do not yet treat same-session replay as a guaranteed
  workflow; hit/judgement via UI still unverified.
