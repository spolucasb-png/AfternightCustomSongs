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

- Menu/song-select integration, results handling.- Server-interaction mapping (optional requirement; `fireStageRemote` noted).
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
- [x] Decisive live test (session 11, user-verified): FULL SA chart + mp3 +
  autoplay, watched 35-45 s. NO teleport. Root cause CONFIRMED; the
  session-8 "SV-stripped still glitched" verdict is discarded as a test
  error.
- Prior session-9 plan (FULL audio-free 2x2, Test A/B, bpmChanges-omission
  converter option) is SUPERSEDED by the anchor fix — do not pursue unless
  the live test fails.
- (Session 9 trail, kept for context): SongPlayer clock is os.clock-based;
  audio `TimePosition` feeds only <=10 resyncs after Resume; Conductor =
  `setSongPos(SongPlayer.timePosition)` once >0, else dt-accumulated
  free-run. SA's first BPM change + first SV are both at 40.8 s; Ievan has
  0 BPM changes. The BPM-change trigger hypothesis is superseded by the
  SV-discontinuity mechanism above.

### 14. Skins (noteskin + judgement/combo art) — BUILT; visual test pending
- [x] Phase 0 recon, Phase 1 converter, Phase 2 player support, Phase 3
  teardown verify, Phase 4/5 judgements + combo digits (see HANDOFF
  session 12-14 for the evidence trail).
- [x] Judgement/combo swap: popup `.Image` needs an ID STRING (a `Content`
  object throws), AND the pooled-label latch was freezing every swap after
  the first — fixed as a per-value revision marker (session 15).
- [x] Skin converter now takes three source games: osu!mania (unchanged,
  byte-identical output verified), Quaver (new), Etterna/SM5 (new).
  Shared `build_pack`; 15/15 offline tests; all deployed packs validated
  with the game's own XMLParser live (19 SubTextures/direction, no missing
  frame names).
- [ ] VISUAL: play once with a skin picked and skins that carry
  judgements (Still's Circles) — confirm popups reskin across a full combo
  (the revision fix) and eyeball the Quaver/Etterna highway art.
- [ ] Unverified-orientation calls resting on reasoning, not eyes: Quaver
  end-cap flip, Etterna `Rotate` handling (hold pieces are never rotated,
  by SM5 design).

### 15. Map porting (Quaver / Etterna / osu! → workspace Charts/) — COMPLETE (2026-10-17)
- [x] Quaver (session 20): skrubble's ball, ballin' (SV), bozo (SV),
  halloween (SV) staged + stem-matched mp3s; oversized JSONs load through
  the chunked-synth fix (ModuleScript.Source 200k char cap).
- [x] osu! (session 20): Dragon 6K Blade (folded 6K), Day by day,
  Blue Zenith (folded, drops noted), -+- 4K SC, me & u, d_for staged +
  matched mp3s; artist added to ids.
- [x] Etterna (session 21): insert_coin (535/388) + Sayonara Cruel World
  (803/232) staged + stem-matched mp3s; the live "audio delayed" report
  caught the #OFFSET sign bug (charts came out 2x OFFSET late) — fixed in
  eterna_to_afn.py (8/8; negative-note warning; new test), charts
  reconverted + replaced. Workspace: 14 charts + 14 audio.
- [x] LIVE (session 21): ballin' played by the user — Play line
  `tame=hooked(4472@x1)`; the chunked-synth chart loaded and ran to
  results ("works so well"). `synth_chunks=` is now printed in the Play
  line (the report carried it, the summarizer did not).
- [ ] LIVE: replay insert_coin / sayonara after the OFFSET fix (re-select
  the chart so the mod re-reads it). Then user sign-off.

### 16. SV spawn feel — engine spawn hook + teleport tamer (built; live-check pending)
- Root cause (session 20): the engine spawn gate lead = spawnTime/|SV|.
  Quaver teleport blips (sub-ms, +-x4.4M) hold insane SV across note
  ranges, so notes spawn at the receptor (pop-in). Motion itself is
  bit-faithful; no motion-preserving game-side fix exists.
- [x] SV timestamps at full precision (round-3 had corrupted 20,039
  timestamps; restaged verbatim) + opt-in `--sv-cap` on all 3 converters.
- [x] Player-side teleport tamer (default ON, +-x3 copy clamp, toggle;
  svflat still wins).
- [x] Engine spawn hook (explicit user approval): chunk-global
  `getSVFromTime` clamped to +-x1.0; install/passthrough/restore branches
  live-verified, restores the prior value. Session 24: installs for ANY
  SV map — day by day's 0.01/2.0/6.0 wobble slipped past the old
  |SV| > 10 trigger (its max is exactly 10.00); sim says 15.3% -> 0.2% of
  its notes spawned below half the line. Session 25: sane-SV charts now
  get the window SOLVER — the hook walks the SV table to the exact
  1750-unit spawn distance per note (live-validated 1750.00, error 0.000
  on 16 samples incl. all day-by-day stutter spots; 0 fallbacks across
  the staged set) — flingy charts keep the clamp. Day-by-day hold bodies:
  traced to its |SV|<=0.05 stop stutters; geometry is integrated-correct
  (map-intended squash); flat toggle / optional SV-floor offered.
- [x] ONE live ballin' Play (session 21): Play line `tame=hooked(4472@x1)`;
  user: "works so well".
- [ ] If the feel still needs work, user picks: `--sv-cap C` (C=3
  suggested), the svflat toggle, or raw.

### 17. Song grouping + difficulty selection in both UIs — BUILT (2026-10-17, session 22)
- [x] Converters emit `song.title` / `song.artist` / `song.difficulty`;
  all 14 staged charts reconverted (12 byte-identical; SA/Ievan renamed to
  the artist-in-id standard with their mp3s). 14 charts = 13 songs.
- [x] In-game Custom tab: one row per song; native difficulty buttons per
  diff (click = select + audio preview); song-level favourite star; search
  covers title/artist/difficulty.
- [x] Rayfield (custom UI): Chart dropdown = songs + new Difficulty
  dropdown (per selected song).
- [x] LIVE (user): "works perfectly" — menu tab rows/difficulties/preview
  and the Rayfield Chart→Difficulty flow all verified in play.

### 18. Multi-key charts (5K-10K native) — BUILT (2026-10-17, session 23)
- [x] Engine recon: ManiaData dirs/angles cover 1-21 lanes per side;
  keybinds per count exist in saved data; createNote maps player rows at
  lanes [keyCount, keyCount+playerKeyCount).
- [x] Converters: native emission up to 10K (keyCount=playerKeyCount=N,
  rows N..2N-1); >10K folds to 4K with the loud warning. Suites updated.
- [x] Staged: Dragon 6K + Zenith 7K restaged native (1531 notes restored
  on Zenith); -+ 5K NM/SC + Ievan 7K NSV added; workspace 17 charts.
- [x] Player: keyCount-driven validation + display; custom skins apply to
  wide charts — engine dir fallbacks cover the extra lanes, and the centre
  Square borrows the game's own "Space" art when the pack lacks one (subs
  `skin-square=stock|pack|fallback(Up)`; loader v2.0.0).
- [x] LIVE (user): wide charts play correctly — lanes, layout and keybinds
  "work!"; the skin-apply fix rides the same build (one more Play to
  eyeball the centre art).

### 19. Song covers — BUILT (2026-10-17, session 26, v2.1.0)
- [x] Data: `Workspace/AfternightCustomSongs/Covers/<chart-stem>.<png|jpg|jpeg>`
  (same stem as chart/audio). Art extracted from the source packs — Quaver
  `.qp` BackgroundFile / largest image, osu `.osz` [Events] background /
  largest non-storyboard image, Etterna folder art. 17/17 staged charts
  covered (9 png / 8 jpg); halloween-vs-SA `bg.jpg` staging collision fixed.
- [x] Player: `listCoverFiles()` + `automatchCover(entry)` (stem, then any
  sibling chart stem of the song group). Applied to the native
  `SelectedSong.Icon` (Crop, default image + ScaleType restored when no
  cover) and every menu row's `BG` (Crop; dimmed >= 0.35 while unselected,
  full art when selected, accent gradient kept on top).
- [x] LIVE (user): "nice! looks so well" — the in-menu tab shows row art +
  the selected-song icon from the staged covers.

### 20. Local play stats + Recent/Favourites sorting — BUILT (2026-10-17, session 27, v2.2.0)
- [x] Data: own `Stats.json` in the workspace (game saved data untouched).
  Per chart stem: starts `n`, finishes `f`, last/best accuracy + score, best
  combo, cleared flag, last finish time; 80-entry Recent list (newest first).
  `noteRecent` runs at play start (quits count and show in Recent);
  `recordResult` runs when our own endSong raises the local results screen.
- [x] Capture: `installStatsHook` wraps the engine's `Results.create` for the
  length of OUR play only (copies score/accuracy/topCombo/cleared, forwards
  every call unchanged); restored in teardown (`step "stats-hook"`).
- [x] UI: in-menu panel shows Plays/Finishes + Best/Last accuracy (+ best
  score) once a chart has a finish. Sorting `settings.sortMode` = az|recent|
  favs — in-menu header Sort button (live LayoutOrder re-sort, no rebuild)
  and a Rayfield "Sort songs" dropdown; recent ranks by earliest recent-list
  hit, never-played trail A-Z.
- [x] Tests: +5 boundary checks; full suite green; whole file compiles under
  Luau `loadstring` (negative control rejected). LIVE: botplay verification
  wrote a real record, then real plays kept it growing (6 recent entries
  across osz/Quaver/Etterna charts).
- Note: reset = delete `AfternightCustomSongs/Stats.json` in the workspace;
  recreated on the next play.

### 21. HUD labels: menu title + real difficulty — BUILT + LIVE (2026-10-17, session 28, v2.2.1)
- [x] Bug (user screenshots): Now Playing card / time bar read the chart id
  and a fixed "Easy" — the engine reads
  `SongName = Song:GetAttribute("DisplayName") or Song.Name` and
  `DisplayDiffName = Difficulties_<Chart.Name>` (raw name as fallback).
- [x] Fix: `currentEntry` (set in both selection paths) + `playLabels`;
  `songInst:SetAttribute("DisplayName", title)`; the chart ModuleScript is
  named with the menu difficulty label (`4K SC`, `Daniel's NM`, ...); the
  loading banner and Rayfield toast use the same labels; `rep.title`/
  `rep.diff` carry them. `Song.Name` stays the internal id (registry key).
- [x] LIVE (user): "the live checks out ... everything works!" — Now Playing
  "-+ / By: daisan", time bar "-+ (4K SC)".
- Note: legacy single-chart players (`player_core.lua`, `player_windui.lua`)
  still label by id / "Easy"; the game's own second loading-state call may
  still show the id.

### 22. Content wave: batch porter + osu diff families — WAVE 1 STAGED & PLAYED (2026-10-17, sessions 26-27)
- [x] Tool: `converters/batch_port.py` — scan/stage for SM/Etterna song
  folders or `.osz` archives; audio from `#MUSIC`/`AudioFilename` (largest
  fallback), cover auto-pick (bg/jacket/name hints, else largest >= 8 KB);
  per-stem copies into `Charts/` + `Audio/` + `Covers/`; no-overwrite
  inherited from the converters.
- [x] Etterna LN megapack scanned (255 folders -> 280-row report,
  `docs/megapack_scan.csv`); wave-1 = 32 songs / 37 charts
  (`docs/wave1_picks.txt`, `docs/wave1_staged.csv`). osu diff families
  finished (`docs/osu_families_staged.csv`): Blue Zenith 10 diffs, -+ 6,
  me & u 5, Ievan 4 (4K/7K SV + NSV).
- [x] Workspace now 42 songs / 72 charts — Charts/Audio/Covers all in sync
  (72/72/72), ~313 MB.
- [x] LIVE (user plays): Stats.json shows wave songs played (Overdrivers,
  Daisan 4K SC, day by day, Blacksphere, ...).
- [ ] Remainder: wave-2 cherry-picks from `docs/megapack_scan.csv`; the tool
  + reports are still untracked in git.

## Known limits

- Upvalue names unavailable (positional indices only); arity unavailable
  (`debug` table absent); no game-code decompiler on this side.
- No `delfile`: workspace probe files were removed via local shell on
  2026-10-13 (user-approved) instead; repo `experiments/` copies are canonical.
- `getSongData()` with zero args fails; `SaveData/` path form unknown.
- `Maps` empty even with songs loaded; song-select flow unobserved.
- Strum/strumline userdata cannot be restored by hand → rejoin recovery.
