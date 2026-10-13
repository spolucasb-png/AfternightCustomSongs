# AfternightCustomSongs

Independent feasibility prototype: a custom-chart system for **Project Afternight**
(Roblox, PlaceId `13042495892`), inspired by GakuranCustomSongs but a separate
project with no merge obligation.

## Current status

This is a research prototype, not a production-ready chart platform. Stop now
attempts to reset module idle flags and note/strum pool tables; this does not
prove Roblox instances, render bindings, or camera/HUD state are fully restored.
Same-session replay remains unverified until the prescribed live test passes.
See [`HANDOFF.md`](HANDOFF.md) for session-level evidence and known side effects.

| Capability | Status |
|---|---|
| Engine discovery / note routing | Mapped; tap routing was live-verified in the documented test harness |
| Synthetic chart parse | Live-verified in the parse harness; not equivalent to live replay validation |
| Full-play smoke path | A successful live smoke run is recorded in `ROADMAP.md` |
| WindUI panel | UI boot and chart listing recorded; Play-through-UI remains unverified |
| Human hit / judgement path | Not verified |
| Sustain chains, SV, BPM changes | Pending mechanic tests |
| Repeated play without rejoining | `forceIdle` reset implemented; same-session replay still needs live verification |

The player uses a non-invocation boundary: it avoids direct score, persistence,
and remote API calls and does not install networking hooks. This is **not** a
strict network-silence guarantee; engine-internal side effects are documented
in `HANDOFF.md` and must remain evidence-gated.

## Target game (observed, live client)

FNF-style rhythm engine: chart-driven gameplay module (`parseChart`,
`addNotesFromChart`, `createNote`, `startSong`, …), millisecond `strumTime`
notes with lane/sustain chains, FNF Conductor (BPM/BaseBPM/CurBPM, Offset),
**native** slider-velocity support (`svFunctions`), song audio transport
(`songPlayer`), map registry (`mapModule.Maps`).

## Layout

- `src/player_core.lua` — callable preflight/play/stop core.
- `src/player_windui.lua` — local chart-picker UI using the vendored WindUI build.
- `src/test_loader.lua` — native UI tap harness; kept separate from the full-play path.
- `src/player_loader.lua` — one-shot smoke bootstrap for the player core.
- `converters/osu_to_afn.py` — offline osu!mania-to-Afternight prototype converter.
- `tests/` — offline static checks, chart-model checks and converter regression tests.
- `fixtures/` — synthetic and converted chart JSON fixtures.
- `experiments/` and `docs/` — provenance, probes, decompile snapshots and reports.

## Requirements (from evidence)

- Executor: Madium (all 13 capabilities verified live: `getgc`, file I/O,
  assets, `gethui`, `getconnections`, introspection). No `delfile`.
- Deployment files for the UI: `afn_player_core.lua`, `afn_player_windui.lua`,
  and the locally vendored `afn_windui.lua`; charts belong in
  `AfternightCustomSongs/Charts/` in the executor workspace.
- The vendor still contains dormant network/key-system paths; current player
  configuration does not enable those paths. See `src/player_windui.lua`.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: do not
  modify its production code, converters, charts, or verified outputs.

## Provenance

Spike evidence: `experiments/` (probe sources) + `docs/` (reports).
Gakuran-side reference commit: `6ca111b` (frozen during the spike).
