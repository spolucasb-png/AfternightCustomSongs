# Roadmap (AfternightCustomSongs)

## Working rules

1. Evidence first: no runtime claim without a live observation (probe/test id).
2. Idle engine + snapshots for every state-changing call; stop on first error.
3. One mechanic per test (taps → holds → SV → BPM). No permutation sweeps.
4. Gakuran repo is reference-only; chart schema there stays frozen.
5. No commits without explicit user approval.

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

### 4. Test B2 (sections-arg fix + per-stage sampling) — NEXT, needs rejoin + go
Same wrapper; `parseChart(wrapper, {}, nil, nil)` →
`addSectionsFromChart(wrapper.song)` → `addNotesFromChart(wrapper)`. Pass =
4 notes R/0–3 @1200/1800/2400/3000, pools restored, rejoin after (strums).

### 5. Mechanic tests (after B2 passes)
- [ ] Sustain: one hold, chain start/duration/completion vs `susLength`.
- [ ] SV: one non-neutral `{startTime, multiplier}`, spacing check.
- [ ] BPM: mapped change, timing reconstruction check.

### 6. Adapter decision (after mechanics pass)
- [ ] Define the `src/` boundary (discover/register/assets/start-stop/map/cleanup).
- [ ] Reuse converters + `{b,l,d}`/SV math; write the Afternight timing map.
- [ ] Combine with Gakuran loader only if a real shared boundary emerges.

## Later / explicitly out of scope

- Full custom-chart loader before B2 passes.
- Menu/song-select integration, skins, results handling.
- Server-interaction mapping (optional requirement; `fireStageRemote` noted).
- Publishing a remote repo (local git only until requested).

## Known limits

- Upvalue names unavailable (positional indices only); arity unavailable
  (`debug` table absent); no game-code decompiler on this side.
- No `delfile`: workspace probe files persist (inert, documented).
- `getSongData()` with zero args fails; `SaveData/` path form unknown.
- `Maps` empty even with songs loaded; song-select flow unobserved.
- Strum/strumline userdata cannot be restored by hand → rejoin recovery.
