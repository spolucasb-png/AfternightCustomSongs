# Takeover prompt: AfternightCustomSongs player bugs (paste to the new agent)

You inherit a working-but-regressing Roblox custom-chart player. Read this
whole file, then the repo docs it points to, before touching anything.

## 1. What this is

`AfternightCustomSongs` — local-only custom charts + local music for
**Project Afternight** (Roblox PlaceId `13042495892`), driven through the
**Madium executor** (its `readfile`/`writefile`/`getgc`/`getcustomasset`
filesystem root is `C:\Users\Administrator\AppData\Local\Madium\Workspace`).
Repo (git, local + GitHub remote, do NOT push without approval):
`C:\Users\Administrator\Desktop\Referencesandmods\AfternightCustomSongs`.
Reference-only, NEVER modify: `../gakurancustomsongs`
(`GakuranChart.lua` = architecture reference; `tools/osu2gakuran.py` =
timing reference, reimplement-don't-import; `FunkyChart_v1.23/FunkyChart.lua`
is a 112-byte HTTP stub, useless — only its `.osz` maps matter).

Canonical sources live in repo `src/`; the executor runs deploy copies
(`afn_player_core.lua`, `afn_player_windui.lua`, `afn_windui.lua` + charts in
`AfternightCustomSongs/Charts/`, music in `AfternightCustomSongs/Audio/`).
If you edit `src/`, redeploy by copying to the workspace. The user runs the
WindUI panel in-game and tests by hand (autoplay toggle included); client
PIDs change on every rejoin — always resolve the live PID first via the
Madium `runtime_status` tool.

## 2. How the player works (all live-proven, don't redesign blindly)

- Synthesize a chart ModuleScript (`Source` = JSON string), inject a
  `songIds["AFN Custom"]` registry entry, call the engine's real `loadSong`
  (found by `debug.info(f,"s")` contains `"PlayerScripts"` +
  `debug.info(f,"l")==8058`; upvalues [3]=engine `t_1`, [5]=state `t_7`,
  [6]=gameplay `t_21`, [1]=`v963` load flag), then
  `NetworkFunctions.remoteListen["Start"](0)`. Teardown is `abruptGameEnd`
  (via `getfenv(loadSong)`) + restoring every substitution.
- LoadSong/Start/teardown run at thread identity 2, restored after.
  Executor-made ModuleScripts fail the engine's `require`, so wrap
  `getfenv(loadSong).require` for that one instance only (restore on Stop).
- Local-only mitigations (all source-verified): `stage=nil` (all
  `fireStageRemote*` early-return), `SkipCountdown=true` (skips both
  Countdown asset fetches), clone `Ratings/Afternight`→`Ratings/<style>`
  (asset cache hit, no `RequestEvent`), `enterLoadingState` pre-flip with
  empty Sides (skips overhead Invoke), relocate `Main.Character` remote
  (character `Replicate()` no-ops). Residual: one `UpdPreferences`+`Sync`
  pair on first `loadStageCharacters` flip; `PlayerDeath/Reset` only on
  death/reset.
- Audio: registry `Audio={Instrumental=<Content>, Volume=1}` where Content
  comes ONLY from `Content.fromUri(getcustomasset(workspacePath))`
  (`SongPlayer.parsePath` accepts Content directly). No `Audio` key =
  audio-free free-run. Stop is audio-safe (engine unloads ~1 s later).
- Song end: the engine NEVER ends locally (audio end fires only a modchart
  hook; real ending is server `Clear`→`endSong`). Allowlisted (user
  approved): one `t21.endSong(true)` call at the audio-clock end → local
  results screen + standard cleanup; results stay until Stop.
- Autoplay: one `t21.SetAutoplay(true)` + reset-to-false in teardown
  (one-time test exception, UI toggle default off).
- Preflight gates everything (idle flags, pools zero, PlaceId, settings);
  locator retries the getgc scan 3× (it flaked once live).

## 3. Engine facts with sources (verify, don't assume)

- Decompiles: repo `experiments/decompiled/` (9 modules) + full client at
  `C:\Users\Administrator\.local\share\opencode\afn_client_decompiled.lua`
  (15,644 lines; loadSong ~12548, parseChart 8011, endSong 15288,
  song-end hook 11269-11272, spawn math 9297, sustain build 7528,
  per-frame sustain 10753-10820, BPM consume 9958-9992).
- `parseChart` → `Conductor.mapBPMChanges(fixed)` reads TOP-LEVEL
  `bpmChanges` (ms-anchored); SV reads TOP-LEVEL `sliderVelocities`, gated
  by DataManager flag `SVChanges` (live `true`); old `song.SVChanges`
  output was inert. `fixChart` passes marker-less charts through
  (BaseGame `generatedBy` guard, ModernPsych `format` guard).
- Holds: segment count = `sus // StepCrochet` AT PARSE (base-BPM grid);
  sub-step holds build zero segments → render as taps (converter now
  clamps them to one base step, warned). Scroll/position/clip math
  (`getPosFromTime`, MathFuncs `getYPosAt`/`getSusLength`) takes NO bpm
  input — positions are SV-map or raw-ms only.
- Converter (`converters/osu_to_afn.py`, tests 7/7): ms rows, lanes 4–7,
  `bpmChanges` = reds[1:] in file order, SV verbatim last-wins,
  `audioFile` basename passthrough, no-overwrite outputs. Audited clean:
  zero duplicates/overlaps song-wide, values exact.

## 4. The actual problems (why you're here)

The user reports MORE bugs than before — likely regressions from recent
work (hold clamp reconversion ≤10 ms; Ievan now plays with 4 live SVs that
were inert before; new Audio/Autoplay toggles; untested endSong watcher).
Symptoms, SOUND ARCHITECT (~6 min, 4659 rows, 865 holds, 30 SV, 32 BPM
changes 165→222→165): notes/hold-bodies misplaced around 41–47 s (window
moved between reports: first 50–70 s), self-correcting per section; dense
parts choppy while botplay logic stays perfect (render-side strain).
KILLED already: converter fault (audit clean), SV path (SV-stripped test:
glitch stayed), BPM map (VOID — that test ran audio-free by accident, so it
isolated the audio clock, not the map). Prime suspect now: audio-driven vs
free-run conductor (discrete audio-clock reads vs uniform clock). Decisive
test pending: FULL chart audio-free, autoplay, watch 41–47 s. Workspace
currently holds only Ievan + SOUND ARCHITECT (+mp3s); test charts were
deleted per user request.

## 5. How to work (non-negotiable)

- Local-only by non-invocation; current allowlist is §2 (loadSong direct,
  Start listener, one endSong(true), one SetAutoplay pair) — everything
  else server/persistence/score/hook-shaped stays out. Static boundary
  tests must stay green: `tests/test_player_local_only.py`,
  `tests/test_player_windui_local_only.py` (+ converter/loader suites).
- Evidence before claims: no runtime verdict without a live observation;
  pre/post snapshots around every state-changing call; one attempt per
  approval; stop on first error; expect rejoin (PID changes) between
  attempts. Read `HANDOFF.md` (sessions 1–8) + `ROADMAP.md` (§5–§12) for
  full evidence trails, then update them as you go.
- No commits or pushes without explicit user approval. Never touch
  `../gakurancustomsongs`. WindUI is vendored+patched (`src/vendor/`),
  no runtime downloads.
- Suggested restart ladder (the user asked to go back to basics):
  parse-only (B2-min) → taps → holds → SV → BPM (each was green; re-prove
  on the current build) → smoke play → full audio play → replay → results
  screen (never yet tested live — needs a full 146 s+ song via the UI,
  over the executor window). Then attack §4 with the basics green.
