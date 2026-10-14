# Roadmap (AfternightCustomSongs)

## Working rules

1. Evidence first: no runtime claim without a live observation (probe/test id).
2. Idle engine + snapshots for every state-changing call; stop on first error.
3. One mechanic per test (taps → holds → SV → BPM). No permutation sweeps.
4. Gakuran repo is reference-only; chart schema there stays frozen.
5. No commits without explicit user approval.
6. Player non-invocation boundary: do not directly call server, persistence,
   or score APIs; do not hook/block networking to force silence. Known engine
   residuals include one `UpdPreferences` + `Sync` pair during a documented
   `loadStageCharacters` transition; moving `Main.Character` is a mitigation,
   not proof of network silence. `stageRemote` is set to nil for the play path.
   Static identifier scans cannot prove engine-internal behavior; all live
   claims require explicit observations and source evidence.

## Do in order

### 1. Spike: read-only engine mapping — DONE
Probes A–J (capabilities, discovery, chart module, song model, assets,
preflight, songdata, section rows, callers, orchestrator). Native row format
`[ms, lane, sustain]`, live pools, Conductor, native SV established.

### 2. Test A (direct spawner call, idle) — DONE, failed cleanly
`nil with 'KeyCount'`, zero state change. Verdict: missing strumline
context. Led to the parse-first sequence.

### 3. Test A2 (parse → sections → notes) — DONE, partial success
Parse OK (8 strums + 2 strumlines); sections rejected the wrapper
(`nil.notes`); 4/4 notes created by parse itself (lanes/times unverified —
sampler bug, fixed for next time). Pools + Conductor/SV restored; strums
persist → rejoin required. Lesson: constant cross-referencing misses
aliased internal calls.

### 4. Test B2-min: parse-only harness — PASS (2026-10-12, direct run)
4/4 notes with R/0–3 @1200/1800/2400/3000, player-side routing live-proven
(`side="R"`, `mustPress=true`). Pools restored, Conductor/SV verified;
rejoin mandatory (strum residue). The 3-stage B2 stays withdrawn.

### 5. Mechanic tests — ALL THREE PASS LIVE (2026-10-13, PID 6604)
- BPM map: 32 entries, base 165, songTime/BPM values exact vs converter.
- SV: `sliderVelocities` 30 entries ingested with exact values (previously
  inert — all earlier plays ran SV-free).
- Sustain: chains present (800 heads, sample +454.5 ms x5 segs, R/col0);
  pool holds heads + segments (6259 entries from 4659 rows).
- Each a load/read/stop; Stop clean, pools 0, flags false.

### 6. Adapter decision (after mechanics pass)
- [ ] Define the `src/` boundary (discover/register/assets/start-stop/map/cleanup).
- [ ] Converter half exists (`converters/osu_to_afn.py`, offline-tested);
  in-game staging/inject waits for the tap verdict. UI stays native
  (catalog libs need external downloads — violates rule 6).
- [ ] Reuse converters + `{b,l,d}`/SV math; write the Afternight timing map.
- [ ] Combine with Gakuran loader only if a real shared boundary emerges.

## Later / explicitly out of scope

- Menu/song-select integration, skins, results handling.
- Server-interaction mapping (optional requirement; `fireStageRemote` noted).
- Publishing a remote repo (local git only until requested).

## In progress (session 4, 2026-10-12)

### 7. Full-play local loader — first live run GREEN (2026-10-12, session 4)
- Contract closed from sources (`experiments/decompiled/`, 9 modules).
- `src/player_loader.lua` (one-shot, preflight-gated, full teardown).
- `tests/test_player_local_only.py` HELD (static).
- Two blockers found and fixed in the live run (diagnosed with Logger.warn
  hook + traceback, not guessed):
  1. `loadSong` returned ok but built nothing: warn `Chart is not valid!`.
     The engine's own `require(chartMod)` rejects an executor-created
     ModuleScript (still fails at identity 2). Fix: wrap `require` in
     `getfenv(loadSong)` for that one instance only; restore in teardown.
  2. `BaseHUD.Switch` -> `require(HUD:Clone())` threw `Cannot require a
     non-RobloxScript module from a RobloxScript` at the executor's identity
     8 => no HUD => Start crashed on `ShowHUD` nil. Fix: run loadSong, Start
     and teardown at identity 2, restore afterwards.
- Live report: all gates pass; load_ok; UnspawnedNotes 4, Strums 8,
  Strumlines 2; Start ok; Conductor advancing (-71.8 -> 2426.9 ms in ~2.5 s);
  note0 = R/col 3 @3000, mustPress; teardown clean (inSong false, charRemote
  restored, registry entry + ratings clone gone, identity restored).
- Rejoin still required after a run (strum/HUD/camera residue by design).
- Not yet verified live: a human actually hitting notes (input/judgement
  path), audio (none by design), and a second run in the same session
  (single-attempt lockout is intentional).
- Next (session 5 started): WindUI file-picker — see §8.

### 8. WindUI chart player — BUILT (UI boot recorded; Play-via-UI pending)
- `src/player_core.lua` callable play/stop; `src/player_windui.lua` library
  UI with dropdown over `AfternightCustomSongs/Charts/*.chart.json`.
- Offline convert: `python converters/osu_to_afn.py <file.osu> --out-dir
  <Madium>/AfternightCustomSongs/Charts`.
- Deploy: `afn_player_core.lua` + `afn_player_windui.lua` + `afn_windui.lua`.
- Hardening: `%q` chart Source, transactional teardown, non-invocation
  docs, converter same-timestamp red-line order, CI workflow for offline
  Python checks (`tests/test_chart_source_escape.py` + existing suite).
- [x] Live: boot UI (PID 15352, again 26420) — 3 charts listed, core ready.
- [x] Live: programmatic Play synth via hardened core (PID 26420) —
      load/start/observe/teardown all ok; `%q` adversarial round-trip ok.
- [ ] Live: Play synth / easy_001 / Camp via UI buttons, human hits.
- [ ] Live: Play synth / easy_001 / Camp through the UI, Stop, and verify a second chart starts in the same session.
- [ ] If cleanup reports incomplete, press Stop again and inspect per-resource teardown results; rejoin only if retry still fails.
- [ ] Then mechanic tests (sustain, SV, BPM) in item 5.

### 9. Same-session replay recovery — IMPLEMENTED IN CODE; LIVE TEST PENDING
- `player_core` v1.2.0 adds `forceIdle` teardown steps for state flags, Notes / UnspawnedNotes, and best-effort Strums / Strumlines table clearing.
- The simple UI runs preflight inside Play and exposes only Chart, Refresh, Play, and Stop.
- Emptying Lua tables is not proof that all Roblox Instances or render/camera/HUD state are gone. Do not claim the rejoin issue is solved until live repeat-play checks pass.

### 10. Local-audio playback — PIPELINE BUILT + PROBE GREEN; PLAY TEST PENDING (2026-10-13)
- Contract: registry `Audio={Instrumental=<Content>, Volume=1}` -> engine
  `SongPlayer:load()`; Content only from `getcustomasset` (no asset IDs).
- Probe live (PID 17616): Ievan mp3 -> Content ok, TimeLength **146.52 s**,
  probe instances destroyed. Camp audio file missing; synth/easy_001 none.
- `player_core` **1.3.0** (`opts.audioFile`), converter `song.audioFile`,
  WindUI **Audio** dropdown with stem auto-match — all offline-tested
  (osu 4/4, both local-only boundaries HELD) and deployed to workspace.
- [x] Live (approved, PID 17616, `afn_audio_test.lua`): idle preflight ->
  Play Ievan + matched mp3 -> `SongPlayer` unpaused, time 0->5.02 s,
  Conductor locked to audio clock -> Stop `stopped`, all steps ok, post
  flags false / pools 0 / audio unloaded. Transport PASS. Human ear still
  has to confirm audibility; same-session replay still unproven.
- [x] UI boot splash: native loading screen while vendor+core load.
- [x] User confirms music was audible during the test window.
- [x] User confirms Stop + same-session replay work with no problems —
  custom chart with local music is PLAYABLE (2026-10-13, PID 17616).
- [x] Camp: NO AUDIO EXISTS (user: Camp is a game-source test file, no mp3).
  Camp stays audio-free permanently — dropped from audio backfill.
- [x] Workspace cleanup (user-approved both sets): test charts deleted
  (Camp/synth/easy_001 — Ievan kept, chart backed up to
  `fixtures/converted/`); all recon/probe/savedecomp/verify/decomp-save
  `.lua` removed from workspace.
- [ ] USER LIVE TEST: play Ievan to the end via UI -> engine results
  screen appears -> "Finished" notice -> Stop tears down. (Full song is
  146 s, over the executor window — UI-only test.)

### 11. Song-end / results screen — BUILT, AWAITING USER LIVE TEST (2026-10-13)
- Root cause: the engine has no local end-of-song path (audio end fires
  only a modchart hook, decompile 11269-11272; ending is server `Clear` ->
  `endSong` -> results, which never arrives locally).
- Fix: keepAlive watcher calls the allowlisted `t21.endSong(true)` at the
  audio-clock end (local `createResults`, `ShowResults=true` live, no
  remotes, no score submission) + standard `clearUp`; results stay up
  until Stop. Boundary exception user-approved. Audio-free unchanged
  (Stop-only). Residual: `MedalAutoclip=true` live may attempt a
  `TriggerClip` inside `endSong` (pcall-wrapped, abruptGameEnd fallback).

### 12. Mechanics + multi-BPM — CONVERTER DONE, LIVE CHECKS PENDING (2026-10-13)
- Engine evidence (source-read): `parseChart` -> `mapBPMChanges(fixed)`
  reads TOP-LEVEL `bpmChanges` (ms-anchored); section-`changeBPM` fallback
  not used. SV reads TOP-LEVEL `sliderVelocities`, gated by client flag
  `SVChanges` (live `true`). Both fixers pass marker-less charts through,
  so top-level keys survive `fixChart`. Consequence: ALL previous plays
  ran with SV inert (we emitted `song.SVChanges`, which nothing reads).
- Converter now emits `bpmChanges` (reds[1:], file order) + top-level
  `sliderVelocities`, drops dead `song.SVChanges`; taps/holds stay
  absolute-ms (no conversion needed). Tests 6/6 (new multi-BPM ramp test).
- Sub-step holds (`sus < base step`) are clamped up to one base step with a
  warning: the engine builds `sus // StepCrochet` segments, so unclamped
  they render as taps (65 in SOUND ARCHITECT, 6 in the 50–70 s window).
  Tests 7/7; both workspace charts reconverted (stable names) + redeployed.
  Side effect: Ievan now plays with its 4 real SVs (were inert before).
- SOUND ARCHITECT staged as the combined case (4659 rows, 865 holds, 30
  SV, 32 changes 165->222->165 BPM, ~357 s, 9.1 MB audio; stem-matched
  mp3 deployed). Isolated live checks still need approval: BPM map (read
  `Conductor.BPMChangeMap` after load), SV (`svFunctions.sliderVelocities`
  + built map), sustain (note-chain shape) — each a quick load/read/stop.

### 13. SOUND ARCHITECT placement bug — ROOT CAUSE FOUND, FIX DEPLOYED, LIVE TEST PENDING (2026-10-14, session 11)
- Mechanism (source-traced, numerically proven): SV map discontinuity at
  the first entry when it starts after t=0 (engine anchors cumulative
  position at SV[1] but runs raw time*speed before it). SA: 1225 ms-equiv
  teleport at 40.8 s; Ievan immune (4 x1.0 SVs). BPM map and audio clock
  exonerated for placement. Full evidence: HANDOFF session 11.
- Fix: SV t0-anchor (`{0, x1.0}` prepended when SV[1] starts > 0) in the
  converter (emitted + warned), `player_core.normalizeChart` (WindUI path)
  and Rayfield `readChart` (in-memory; deployed charts need no
  reconversion). Static suites green (osu 9/9, all boundaries HELD);
  anchor logic 7/7 in real Luau; workspace player files redeployed.
- [ ] Decisive live test (needs user approval + fresh PID): FULL SA chart +
  mp3 + autoplay, watch 35-45 s. Expect NO teleport. Clean => confirmed.
  Glitch persists => re-open (also re-runs the non-fitting session-8
  "SV-stripped still glitched" verdict).
- Prior session-9 plan (FULL audio-free 2x2, Test A/B, bpmChanges-omission
  converter option) is SUPERSEDED by the anchor fix — do not pursue unless
  the live test fails.
- (Session 9 trail, kept for context): SongPlayer clock is os.clock-based;
  audio `TimePosition` feeds only <=10 resyncs after Resume; Conductor =
  `setSongPos(SongPlayer.timePosition)` once >0, else dt-accumulated
  free-run. SA's first BPM change + first SV are both at 40.8 s; Ievan has
  0 BPM changes. The BPM-change trigger hypothesis is superseded by the
  SV-discontinuity mechanism above.

## Known limits

- Upvalue names unavailable (positional indices only); arity unavailable
  (`debug` table absent); no game-code decompiler on this side.
- No `delfile`: workspace probe files were removed via local shell on
  2026-10-13 (user-approved) instead; repo `experiments/` copies are canonical.
- `getSongData()` with zero args fails; `SaveData/` path form unknown.
- `Maps` empty even with songs loaded; song-select flow unobserved.
- Strum/strumline userdata cannot be restored by hand → rejoin recovery.
