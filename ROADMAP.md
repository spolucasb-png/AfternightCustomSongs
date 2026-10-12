# Roadmap (AfternightCustomSongs)

## Working rules

1. Evidence first: no runtime claim without a live observation (probe/test id).
2. Idle engine + snapshots for every state-changing call; stop on first error.
3. One mechanic per test (taps → holds → SV → BPM). No permutation sweeps.
4. Gakuran repo is reference-only; chart schema there stays frozen.
5. No commits without explicit user approval.
6. Local-only by non-invocation: never call server/persistence/score
   functions; never hook or block game networking to enforce it. The
   boundary is statically checked (`tests/test_loader_local_only.py`).

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

### 5. Mechanic tests (after B2 passes)
- [ ] Sustain: one hold, chain start/duration/completion vs `susLength`.
- [ ] SV: one non-neutral `{startTime, multiplier}`, spacing check.
- [ ] BPM: mapped change, timing reconstruction check.

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
- Next: WindUI file-picker wiring to `converters/osu_to_afn.py`, then the
  mechanic tests (sustain, SV, BPM) in item 5.

## Known limits

- Upvalue names unavailable (positional indices only); arity unavailable
  (`debug` table absent); no game-code decompiler on this side.
- No `delfile`: workspace probe files persist (inert, documented).
- `getSongData()` with zero args fails; `SaveData/` path form unknown.
- `Maps` empty even with songs loaded; song-select flow unobserved.
- Strum/strumline userdata cannot be restored by hand → rejoin recovery.
