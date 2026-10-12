# Handoff (AfternightCustomSongs)

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

## Standing rules

- Idle engine + pre/post snapshots for every state-changing call.
- One attempt per approval; stop on first error, no permutation sweeps.
- No `startSong` (server remote), no scores, no hooks, no files in game.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: never
  modify its production code, converters, charts, or outputs.
- Workspace probe files (`afn_probe_*`) cannot be deleted remotely (no
  `delfile`); they are inert and clearly named. Repo `experiments/` copies
  are canonical.
