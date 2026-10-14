# Handoff (AfternightCustomSongs)

## Current state (2026-10-13 — session 7; audio + replay USER-VERIFIED playable)

Local audio play is green live AND human-verified: user reports audio works,
Stop + replay work, no problems, chart is playable (PID 17616). Same-session
replay and audibility are no longer pending — both confirmed by user testing.
`player_core` 1.3.0 + WindUI Audio picker + boot splash are built, tested
(offline suites green), committed (`33cdef1`), and deployed. UI re-executed
fresh on user request (splash + retry fix now live in the running window).

## Standing rule change (2026-10-14, user): "no server" means the IN-GAME
server only (no game remotes/traffic). External servers and library
downloads (e.g. Rayfield via HTTP) are ALLOWED and optional — the old
vendored-only UI requirement is lifted. Next script restarts from basics
with a Rayfield UI; decompiles are kept as evidence.

## Session 10 (2026-10-14) — new Rayfield script (built, static-green, NOT run live)

- `src/afn_rayfield.lua` v1.0.0 (self-contained, staged to workspace as
  `afn_rayfield.lua`, 53 kB): FunkyChart-style flow (Charts/Audio/Assets
  folders, chart list + audio auto-match, options, underframe, Play/Stop),
  Gakuran-style shell (capability check, gen cleanup + Rayfield sweep,
  Settings.json, chart validation, Rayfield tabs Charts/Options/Misc),
  player_core 1.3.0 play path ported verbatim (preflight, subs, synth %q,
  registry + local Content audio, loadSong @8058 identity 2, Start
  listener, autoplay, endSong(true) watcher, abruptGameEnd teardown).
  Side fixed "R" (proven); offset slider shifts rows at play (logged).
  Rayfield loads via one HttpGet to sirius.menu/rayfield (rule-lifted).
- Static: new `tests/test_afn_rayfield_local_only.py` HELD; existing
  player/windui/osu suites still HELD.
- LIVE TEST (PID 13152, 2026-10-14, approved "do some tests in game"):
  pre-snapshot clean (PlaceId ok, pools 0/0/0/0, loadSong@8058 found,
  loadedSong=false, inSong=false, v963=false). Boot `afn_rayfield.lua`:
  gen=1, Rayfield window created (visible, all 5 elements), notify wired.
  Driven via `firesignal(MouseButton1Click)` on the real UI buttons
  (madium click_gui_button could not resolve gethui() paths; inspect_visible_ui
  crashes on a foreign ReNotifyV2 ImageButton — tool bugs, not ours).
  Results, all PASS in one session:
  1. Chart dropdown select (Ievan) -> info label "119 BPM | 948 notes |
     0 BPM changes | 4 SV | audio: audio.mp3", audio auto-matched to the
     stem mp3, "Chart loaded" notify.
  2. Play (Ievan): stage=playing, load=true, start=true, Unspawned=948,
     Strums=8, note0=R/0@399, audio=local mp3, Conductor advancing
     18.2s -> 20.3s over 2s (audio clock). Stop -> stage=stopped;
     post pools all 0, loadedSong/inSong false, holder+remoteHold gone,
     Character remote back, ratings clone destroyed, AFN registry nil.
  3. SAME-SESSION REPLAY: second Play/Stop cycle identical PASS.
  4. Refresh button -> "Refreshed: 2 row(s)"; SOUND ARCHITECT select ->
     validated "4659 notes (865 holds) | 32 BPM changes | 30 SV" (exact
     converter match), audio auto-matched. Play: Unspawned=6259,
     note0=R/0@3015, load/start true; Stop -> stopped. Post idle re-read:
     pools 0, flags false, v963 false, AFN entry nil, HideLobby=false,
     SVChanges=true, ShowResults=true.
  NOT yet tested live: song-end results screen (needs a full song through
  the UI), autoplay toggle, offset slider, background options.
  Caveat: console showed foreign "Aimbot/ESP" Rayfield labels — another
  script shares the Rayfield GUI container; our elements are distinct
  paths (Main/Elements/Charts/*) and unaffected.

## Session 7 (2026-10-13) — local-audio pipeline (probe GREEN, play test pending)

The full-play core and WindUI chart picker are implemented; UI boot and
three-chart discovery are recorded live, and a full-play smoke path succeeded in
session 4. This change adds a `forceIdle` cleanup attempt for idle flags and pool
tables plus a simplified Chart / Refresh / Play / Stop UI. Same-session replay
is NOT yet live-verified. Table clearing cannot prove orphaned Roblox Instances,
render bindings, camera, or HUD state are restored; rejoin only if Stop remains
`cleanup-incomplete` after retry until live evidence establishes a stronger
recovery contract. The player's boundary is non-invocation, not strict network
silence: see the documented indirect `UpdPreferences`/`Sync` side effect below.

### Session 7 detail — local-audio pipeline (probe GREEN, play test pending)

Goal from user: charts play but no music yet — wire local music in-game.

Engine audio contract (read from source):
- `songIds[Mod].Songs[name].Audio` -> `t_14.SoundInfo` -> `v90:load(SoundInfo)`
  (client decompile 12929, 13443-13445). `load()` wraps a bare table as
  `{Paths={_default=<SoundInfo>}}`, so the registry `Audio` table IS the
  path desc `parsePath` consumes.
- `parsePath` non-segment branch builds `SoundNames` from
  `Instrumental`/`Voices` keys; a `Content` object value is used directly
  (no `rbxassetid` round-trip) — `afn_decomp_SongPlayer.lua:296-338`.
- `_CachedAudio` attr is only a length fallback when `timeLength<=0`
  (decompile 14210-14216) — kept as-is; real audio reports its own length.
- Stop is audio-safe: `abruptGameEnd` -> `clearUp(true)` tweens `Music` to 0
  and `v90:unload()`s ~1s later (decompile 11476-11488). No extra teardown
  needed, but a Play within ~1s of Stop could race the delayed unload.

Live probe (PID 17616, PlaceId 13042495892 — approved copy+probe):
- Copied `.../_scratch_convert/extract/993703/audio.mp3` (2,344,662 B) to
  workspace `AfternightCustomSongs/Audio/afn_ievan_polkka_4k_nsv.mp3`.
- Probe (temp `AudioPlayer` in `SoundService`, destroyed after): `isfile`
  true, `getcustomasset` -> `rbxasset://...` string,
  `Content.fromUri` -> Content ok, `TimeLength` 0 -> **146.52 s in 0.25 s**,
  preload call ok, cleanup `yes`. Local audio loads — engine path viable.
- Camp's `AudioFilename: audio.mp3` has NO file in its folder (audio
  missing); synth/easy_001 have no audio. Ievan is the first audio test.

Built (uncommitted, offline-tested, deployed — NOT played live):
- `src/player_core.lua` **1.3.0**: new `opts.audioFile` (workspace path).
  Resolved live via `Content.fromUri(getcustomasset(path))` into registry
  `Audio={Instrumental=<Content>, Volume=1}`; resolve failure aborts to
  `audio-resolve-failed` with full teardown. Omitted -> audio-free
  free-run as before. `rep.audioFile` / `rep.subs["audio"]` recorded.
- `converters/osu_to_afn.py`: records `song.audioFile` basename from the
  `.osu` `AudioFilename` (workspace `Audio/` resolution is a player
  concern). Existing fixtures unchanged (no reconversion).
- `src/player_windui.lua`: new **Audio** dropdown over
  `AfternightCustomSongs/Audio/*.{mp3,ogg,wav}`, auto-match by chart stem
  (`<stem>.mp3/...`) else the chart's `audioFile` hint; manual override;
  passed as `audioFile` to `core.play`; Play desc updated.
- Tests: `test_osu_to_afn.py` 4/4 (new `audioFile` assert),
  `test_player_local_only.py` HELD (audio gated on `opts.audioFile`,
  getcustomasset+Content.fromUri only, single Instrumental site, no
  `rbxassetid` literals), `test_player_windui_local_only.py` HELD (audio
  dir/dropdown/automatch checks); tap harness + escape + synth suites
  still pass.
- Deployed (file copy only): workspace `afn_player_core.lua` (1.3.0) +
  `afn_player_windui.lua`. Workspace Ievan chart verified: 948 notes,
  119 BPM, no `audioFile` key (old converter) — stem auto-match covers it.
- NOT yet run live: audio play (load+start+audible check+Stop) needs
  explicit approval per one-attempt rule. No engine state changed this
  session (probe instances only, destroyed).

### Live audio play (PID 17616 — approved, `afn_audio_test.lua`, one attempt)
- PRE: idle (pools 0/0/0/0, `SongPlayer` paused/curAudio nil/timeLength -1).
- PLAY Ievan + matched mp3 (`keepAlive`): `load_ok`, `start_ok`,
  `stage=playing`, UnspawnedNotes=**948**, Strums=8, Strumlines=2,
  note0=R/col0 @399 mustPress.
- OBSERVE 6 s: `SongPlayer` unpaused, `timePosition` 0 -> 2.00 -> 5.02 s,
  `timeLength` 146.52, 1 path/1 audio; Conductor -980 -> 2010 -> 5023 ms —
  **conductor tracks the audio clock** (2.005 s vs 2010 ms). Character
  survived (misses, no death). Transport-level PASS; speaker audibility
  needs a human ear (user asked to confirm).
- STOP: `stage=stopped`, `ok=true`, every step ok (abruptGameEnd,
  leaveLoadingState, idle-flags, pools-notes, pools-strums, require,
  charRemote, ratings, registry, holder). 2.5 s later: flags false, pools
  0/0/0/0, audio players unloaded (a Paths/audios 0, paused, pos frozen).
- Cosmetic bug found by the report: `stop.err` was always set
  (`rep.ok and nil or x` is always x in Lua). Fixed with if/else in
  `player_core` (uncommitted) + redeployed workspace core. UI unaffected
  (it branches on `stage`/`ok`, not `err`).
- Same-session replay still NOT proven (second play unattempted); strum
  Instance/HUD/camera residue unknown. Rejoin advised before next play.
- UI re-executed on user request: fresh boot, splash + locator-retry fix
  now live in the running window (`player_core 1.3.0 ready`, 4 charts).
- USER VERDICT (2026-10-13, PID 17616): audio works, Stop + replay work,
  no problems at all — custom chart with local music is PLAYABLE. This
  clears the two pending live items: speaker audibility and same-session
  replay, both confirmed by human testing rather than instrumentation.
- User bug report: songs never end (no end screen; only Stop works) +
  "delete test files" (both workspace sets).
- Root cause (source-read, decompile 11269-11272): at audio end the engine
  only fires the `onSongEnded` modchart hook; real ending is server-driven
  (`Clear` -> `endSong` -> `createResults` + `clearUp`), which never arrives
  locally. `createResults` itself is fully local (score/judgement reads +
  `Results.create` UI; the only server lines in the 15k-line client are
  elsewhere), `ShowResults=true` live, `t21.endSong` is a function, and
  loadSong ends with `v963=false` (14303) so `endSong`'s `clearUp(true)`
  takes the full path. Residual: `MedalAutoclip=true` live may attempt a
  `TriggerClip` inside `endSong` (module exists, required at boot) —
  our call is pcall-wrapped with an abruptGameEnd fallback.

## Session 8 (2026-10-13) — song-end + results screen (built, needs a full-song live test)

- `player_core` (uncommitted): keepAlive path spawns a song-end watcher
  (0.5 s poll, exits on Stop/phase change). At audio-clock end
  (`timeLength-timePosition<=0.25`, unpaused) it calls the ONE allowlisted
  `t21.endSong(true)` at game identity: local results screen, then
  `phase="ended"`, `stage="ended-results"` — results stay up until the
  user's Stop. Failure -> fallback full stop (`ended-fallback-stop`).
  Stop refuses only during transient `preparing`/`finishing`. Audio-free
  plays have no clock end: Stop-only, unchanged.
- `player_windui` (uncommitted): finish poller notifies "Finished — results
  on screen" when the report flips to `ended-results`. No `endSong` in UI.
- Boundary tests updated (endSong allowlist: one resolve site, one
  `endFn(true)` site, never createResults, clock-gated): all suites green
  (core/windui HELD, osu 4/4, escape 2/2, synth 7/7, tap harness HELD).
- Deployed to workspace (core + windui). Live test needs a FULL 146 s song
  (>MCP 120 s window), so it runs via the user's UI, not via executor call.
- Workspace cleanup done (user-approved): test charts deleted (Camp, synth,
  easy_001 — Ievan kept; Ievan chart backed up to
  `fixtures/converted/`), all recon/probe/savedecomp/verify/decomp-save
  `.lua` removed. Deployed player files + Charts/Ievan + Audio/mp3 kept.
- UI boot for user testing (PID 17616, `afn_player_windui.lua`): `boot
  gen=1`, 4 charts, `player_core 1.3.0 ready`. Default select is Camp
  (audio-free, file missing); picking the Ievan chart auto-matches its mp3.
- Boot splash (user request): native `AFN-Loading` ScreenGui in PlayerGui
  with status lines (library -> window -> charts -> core), destroyed on
  ready and on every abort path; re-exec cleanup removes strays. Boundary
  test covers order + teardown (HELD). Needs a UI file re-execution to be
  seen live.
- First UI Play failed at `loadSong-found` with an idle engine; the second
  press (no rejoin, nothing else) played fully (948 notes + audio, clean
  Stop). Verdict: one-off locator flake in the getgc/debug.info scan, not
  engine state — proven by 5/5 read-only preflights passing right after
  (49–198 ms scan time). Fix: `findFnByLine` retries 3x (reads only) and
  records `locator-attempts`; boundary test extended, still HELD;
  workspace core redeployed (running UI still holds the pre-fix table
  until the file is re-executed).
- External AI review triaged (no files changed by reviewer): accepted and
  done now = README status reconciled with HANDOFF/ROADMAP (replay, UI
  play, hits all user-verified; results screen pending) + converter input
  hardening (garbage Mode/CircleSize refused cleanly, skipped rows counted
  and reported; new offline test, suite now 5/5). Deferred with reasons =
  per-mechanic live tests + multi-BPM conversion (need live engine work,
  stay in ROADMAP §5/§6), large-chart limits (Ievan-size loads fine;
  premature), engine-internals reliance (already gated by preflight;
  nothing actionable).
- Mechanics unblocked from source (no live calls): `mapBPMChanges` reads
  top-level `bpmChanges`; SV reads top-level `sliderVelocities` behind the
  client `SVChanges` flag (live true) — prior `song.SVChanges` was inert,
  so every play so far ran SV-free. Converter emits both (tests 6/6);
  SOUND ARCHITECT (4659 rows / 865 holds / 30 SV / 32 BPM changes /
  9.1 MB audio) converted + staged in workspace for the combined live
  case. Isolated BPM/SV/sustain checks proposed, awaiting approval.
- Converter-fault audit (user's question — verdict: NOT the converter):
  SOUND ARCHITECT output vs `.osu`: times verbatim ms, lanes standard,
  zero exact duplicates (song-wide), zero same-lane overlaps (song-wide),
  SV/BPM values exact per live checks; sole transform is the documented
  sub-step clamp (<=10 ms, warned). Output is a faithful transcription.
- Video forensics (4.6 s clip, 60 fps, autoplay MFC): the 0:37 green bar
  aligns with the 37196/728 ms lane-6 hold under a long spawn lead
  (spawn lead = noteSpawnTime/|SV| shows notes seconds early) — consistent
  with normal early-spawn rendering, not a phantom. "Future section"
  feeling matches spawn lead directly. Proposed discriminator: SV-stripped
  diagnostic copy (awaiting user ok).
- SV discriminator DONE (user): glitch stays without SVs — scroll math
  acquitted. BPM-mirror discriminator DONE (user): positions CORRECT with
  empty map (just choppy; botplay fine) — tempo machinery implicated for
  placement. Both temp files deleted after verdicts.
- MathFuncs decompiled live (`Other.MathFuncs`): `getYPosAt` =
  `(CurrentTrackPos - initialPos)` (SV map) or `(SongPosition - pos) ×
  speed` (no SV) — NO bpm input anywhere in Y math; `getSusLength` same.
  Every positional code path is map-clean, yet misplacement correlates
  with the map. Standing confound: was the NOBPM run WITH audio? NOBPM
  can't auto-match the mp3 — audio-free (uniform free-run clock) vs
  audio-driven full chart (SongPlayer clock + correction snaps) could
  explain it WITHOUT the map. Asked user; decisive 2x2 pending.
- CONFOUND CONFIRMED (user): NOBPM ran AUDIO-FREE. The "BPM map" verdict
  is VOID — the isolated variable was the audio clock, not the map.
  Mechanism now favored: audio-driven conductor follows the AudioPlayer
  clock (update() blends toward discrete TimePosition reads); free-run is
  uniform. Note the complaint window MOVED between reports (50–70 s, then
  41–47 s) — weak section-lock, consistent with a systemic clock cause.
  Decisive test proposed: FULL chart audio-free (same notes+maps, silent
  clock). If correct -> audio clock; if misplaced -> map for real.
- User console log (NOBPM run): audio-free + autoplay, full 6259-note
  content, load/start clean — then a 5.3-MINUTE run ending in a clean
  `stopped` (12:10 -> 12:15). Long-session stability datapoint: no errors,
  teardown complete. NOBPM file has since been deleted (user later hit
  "file does not exist" trying to replay it — restore on request, though
  the decisive test needs only the full chart + "(no audio)").
- Reference note (user pointed at both): `GakuranChart.lua` stays the
  architectural reference (studied, read-only). `FunkyChart.lua` is a
  112-byte HTTP loader stub with no logic — not usable as a reference
  (fetching its remote payload would also break local-only rules); the
  `.osz` maps in its folder ARE useful and already in use. Gakuran's
  `osu2gakuran` clamps SV to [0.1, 10] (no hold-clamp precedent); our map
  SVs (0.74–1.1) need no clamping, so no transform added.
- SOUND ARCHITECT issue triage (user: "BPM used as SV" + 50–70 s rendering
  glitch). Source verdicts: (1) scroll math is provably BPM-independent
  (positions flow only through the SV map; hold SEGMENT COUNT is the sole
  BPM-derived value) — the visible coupling is the map's own design (SVs
  mirror BPMs inversely at identical timestamps: 165/170=0.97 etc.,
  constant pixels-per-beat); (2) 50–70 s input is clean (402 rows, chords
  <=2, zero stacks, min gap 40 ms) — no data defect. REAL defect found
  adjacent: sub-step holds (`sus // StepCrochet == 0`) build zero segments
  and render as taps — 65 song-wide, 6 in-window. Fix: converter clamps
  sub-step holds up to one base step + warns (test 7/7); both workspace
  charts reconverted (stable filenames) + redeployed. Note: Ievan now
  carries 4 real SVs (previously inert) — scroll will feel slightly
  different there. Remaining glitch (if any beyond vanishing holds) needs
  a sharper symptom or screenshot — no sampling per user.
- One-time test autoplay (user-authorized 2026-10-13, NOT a standing
  feature): `opts.autoplay` flips the engine's own `t21.SetAutoplay`
  botplay flag (a pure local setter; the dev-gate guards only its hotkey),
  verified via `GetAutoplay`, reset to false in teardown so it never leaks
  into the next play. UI Toggle "Autoplay (test)", default off. Boundary
  tests cover the single set/reset sites. Treat any future autoplay
  request as a new exception, not precedent.
- LIVE MECHANIC VERDICT (PID 6604, one load of SOUND ARCHITECT, 3/3 PASS):
  BPM map = 32 entries, base 165, times/BPMs exact; SV table = 30 entries,
  values exact (SV ingests now); sustain chains present (800 heads in pool,
  sample R/col0 @3015 +454.5 ms x5 segments; pool holds 6259 entries =
  heads + segments). Stop clean, post pools 0, `stop.err` nil (cosmetic
  fix confirmed live).

## Session 9 (2026-10-14) — takeover (new agent), static re-baseline; NO live calls yet

- Read FOR_NEXT_AGENT.md (untracked, takeover prompt) + HANDOFF + ROADMAP in full.
- Repo state: master, 1 commit ahead of origin (`eb92c26`); uncommitted:
  HANDOFF/ROADMAP, converter, player_core, player_windui, 3 test files.
  Untracked: `.cursor/`, FOR_NEXT_AGENT.md, `_extract_afn.txt`, `_last30.txt`.
  Nothing committed or pushed this session (needs explicit user approval).
- Static suites re-run (offline, all green): player local-only HELD, windui
  local-only HELD, loader local-only HELD, osu_to_afn 7/7, chart_source_escape
  2/2, synth_a_fixture 7/7. Static evidence only — not runtime proof.
- Madium `runtime_status`: one client alive, PID 13152 (connected ~100 s at
  check time). Read-only call; no executor code run, no files written to the
  workspace.
- Next: static read of conductor / SongPlayer.update (audio-clock vs free-run)
  to sharpen the pending decisive test (FULL SOUND ARCHITECT, audio-free,
  autoplay, watch 41-47 s). Live test only with explicit user approval and a
  freshly resolved PID.
- Deploy check (read-only hashes): `src/player_core.lua` and
  `src/player_windui.lua` match workspace `afn_player_core.lua` /
  `afn_player_windui.lua` (SHA256). Workspace Charts = Ievan + SOUND ARCHITECT
  (reconverted 2026-10-13 15:33); Audio = both mp3s (SA 9,121,430 B). Workspace
  root also holds older files not covered above (afn_holds_forensics.txt,
  afn_rl_bot.lua, afn_chart_reader.lua, afn_d1-4.lua, afn_loader_windui.lua;
  dated Oct 9-12) — left untouched, not part of this player.
- STATIC FINDING (decompile only, NOT live-verified) — clock model for the
  Instrumental (non-Segments) audio path. `SongPlayer.update`
  (`experiments/decompiled/afn_decomp_SongPlayer.lua:882-918`) sets
  `timePosition = (os.clock() - _startTime) * speed`. The audio object's
  `TimePosition` is consulted only while `_appliedFix ~= 10`: first advance
  hard-snaps `_startTime` (905-908), the next <=9 blend 0.2 (909).
  `_appliedFix` is reset to 0 only in `Resume` / `ResumeSyncedWith` (831, 849).
  Client `updateConductor` (client decompile 9564-9582): `timePosition<=0` ->
  free-run `RawTimePosition + dt*rate`, else `Conductor.setSongPos(timePosition)`.
  `usesSplits` is set only in the Segments branch (SongPlayer 205), not ours.
  Implication: after ~10 audio advances the "audio-driven" conductor is a plain
  os.clock clock, so per-frame discrete audio reads at 41-47 s are NOT
  supported by the source. This WEAKENS the takeover's prime suspect. Real
  audio vs free-run differences left: startup snap/blend, and dt-accumulated
  (free-run) vs absolute os.clock (audio) under frame hitches. Live check that
  would settle it (read-only): `_appliedFix`, `_startTime`, audio TimePosition
  vs `Conductor.SongPosition` during an audio play.
- Re-confirmed by grep of the client decompile: `StepCrochet`/`Crochet` appear
  only in parse-time sustain build (7528/7531: segs = sus // StepCrochet,
  susEndTime = start + segs*StepCrochet), DecimalStep/beat hits (9989) and
  effect durations (9510). Per-frame sustain (10753-10820) has no StepCrochet
  reference. No live-BPM dependence in note/hold placement found — consistent
  with the earlier audit.
- 2x2 status (BPM map x audio): NOBPM+free-run = OK (user); FULL map+audio =
  BAD (user); FULL map+free-run = PENDING (decisive); NOBPM+audio = PENDING
  (needs manual Audio pick; stem auto-match won't fire).
- USER UPDATE (2026-10-14 ~12:30): the visual glitch actually STARTS between
  ~35 s and ~45 s (earlier reports said 41-47 s, before that 50-70 s; the
  window keeps shifting, so treat it as 35-45 s from here). User APPROVED the
  decisive live test (FULL SOUND ARCHITECT, audio-free, autoplay, watch that
  window) and asked that progress handoffs be kept current after every step.
  Test plan: resolve live PID via runtime_status -> read-only pre-snapshot ->
  boot `afn_player_windui.lua` (the one state-changing executor call) -> user
  presses Play with Audio = (no audio) + Autoplay on -> post-snapshot after
  Stop. One attempt; stop on first error.

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
