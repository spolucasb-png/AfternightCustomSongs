# AfternightCustomSongs

Independent feasibility prototype: a custom-chart system for **Project Afternight**
(Roblox, PlaceId `13042495892`), inspired by GakuranCustomSongs but a separate
project with no merge obligation.

## Status

Phase 4 (spike): engine mapped read-only; synthetic-chart test designed but not
executed. See `docs/` for phase reports.

`src/test_loader.lua` (staged, **never executed in-game**) is the one-call
synthetic tap harness: native Roblox UI, explicit button-gated
`parseChart(wrapper, {}, nil, nil)` using the
`fixtures/afn_synth_a_taps.chart.json` structure, read-only preflight, and
best-effort pool/timing restore that explicitly does **not** claim a clean
session (strumline/registry residue → rejoin required). Static checks on the
staged file pass (single parser call site, no playback/remote/HTTP calls);
there are **no live-game results** — code-level validation only.

## Target game (observed, live client)

FNF-style rhythm engine: chart-driven gameplay module (`parseChart`,
`addNotesFromChart`, `createNote`, `startSong`, …), millisecond `strumTime`
notes with lane/sustain chains, FNF Conductor (BPM/BaseBPM/CurBPM, Offset),
**native** slider-velocity support (`svFunctions`), song audio transport
(`songPlayer`), map registry (`mapModule.Maps`).

## Layout

- `src/` — `test_loader.lua`: staged one-call tap harness (see below).
  Not executed live; no results claimed. No full adapter until taps verify.
- `converters/` — source-format converters, when needed. Reuse GakuranCustomSongs
  algorithms; do not copy its Gakuran hooks, registry, playback or UI code.
- `tests/` — offline checks (runnable here, no client needed).
- `fixtures/` — synthetic chart candidates (clearly-labeled test ids).
- `experiments/` — transferred read-only probe sources from the spike.
- `docs/` — executor/runtime requirements, mechanics support notes, reports.

## Requirements (from evidence)

- Executor: Madium (all 13 capabilities verified live: `getgc`, file I/O,
  assets, `gethui`, `getconnections`, introspection). No `delfile`.
- Server interaction on normal playback exists (`fireStageRemote` in
  `startSong`); any test design must account for it. Server-cleanliness is
  desired but not a hard requirement for this target.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: do not
  modify its production code, converters, charts, or verified outputs.

## Provenance

Spike evidence: `experiments/` (probe sources) + `docs/` (reports).
Gakuran-side reference commit: `6ca111b` (frozen during the spike).
