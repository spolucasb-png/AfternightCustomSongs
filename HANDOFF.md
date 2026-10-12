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
2. Then **Test B2** (approved pattern, awaiting explicit go after rejoin):
   same wrapper; `parseChart(wrapper, {}, nil, nil)` →
   `addSectionsFromChart(wrapper.song)` → `addNotesFromChart(wrapper)`;
   sample lanes/times after EVERY stage; snapshot/restore all; stop on
   first error. Pass = 4 notes with R/0–3 @1200/1800/2400/3000.
3. After B2: sustain test, SV test, BPM test (one mechanic each), then the
   `src/` adapter decision.

## Standing rules

- Idle engine + pre/post snapshots for every state-changing call.
- One attempt per approval; stop on first error, no permutation sweeps.
- No `startSong` (server remote), no scores, no hooks, no files in game.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: never
  modify its production code, converters, charts, or outputs.
- Workspace probe files (`afn_probe_*`) cannot be deleted remotely (no
  `delfile`); they are inert and clearly named. Repo `experiments/` copies
  are canonical.
