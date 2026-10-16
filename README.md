# AfternightCustomSongs

Independent feasibility prototype: a custom-chart system for **Project Afternight**
(Roblox, PlaceId `13042495892`), inspired by GakuranCustomSongs but a separate
project with no merge obligation.

## Current status

Custom charts with local music are **playable and user-verified** (2026-10-13,
live client): audio playback, Stop, and same-session replay all work with no
problems. Stop attempts to reset module idle flags and note/strum pool tables;
table clearing alone never proved render/HUD recovery, but a human replay test
has since passed, so routine reuse without rejoining is supported (rejoin only
if Stop ever reports `cleanup-incomplete` after retry).
See [`HANDOFF.md`](HANDOFF.md) for session-level evidence and known side effects.

| Capability | Status |
|---|---|
| Engine discovery / note routing | Mapped; tap routing was live-verified in the documented test harness |
| Synthetic chart parse | Live-verified in the parse harness; not equivalent to live replay validation |
| Full-play path + local audio | Live-verified (146 s song, conductor locked to audio clock) and human-played |
| WindUI panel | UI boot, chart listing, Play-through-UI, and Stop user-verified |
| Human hit / judgement path | User-verified playable (hits land, misses drain without killing the run) |
| Song-end results screen | Built (engine `endSong` allowlist); awaiting a full-song live test |
| Sustain chains, SV, BPM changes | Holds convert and play; isolated per-mechanic live tests still pending |
| Noteskins (osu!mania / Quaver / Etterna) | Converter + player apply built and offline-tested; packs validated with the game's own XML parse; highway art not yet eyeballed live |
| Judgement / combo popup art | Built; the pooled-label swap bug is fixed (session 15), awaiting a live combo |
| Repeated play without rejoining | User-verified working; rejoin only if Stop reports incomplete cleanup |

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
- `converters/quaver_to_afn.py` — offline Quaver `.qua`-to-Afternight
  converter (ms-native clock, Keys4 direct, wider keys folded).
- `converters/eterna_to_afn.py` — offline Etterna/SM `.sm`/`.ssc`-to-Afternight
  converter (dance-single blocks; beat clock integrates BPM/stops/delays,
  warps drop unhittable notes, SM5 scrolls become SV).
- `converters/afn_common.py` — shared chart emission both map converters
  build on (ms rows, hold clamp, stacks check, SV anchor, no-overwrite).
- `converters/skins2afn.py` — offline noteskin converter for three source
  games (`--game auto|osu|quaver|etterna`): writes an
  `AfternightCustomSongs/Skins/<slug>/` pack of per-direction Sparrow sheets
  plus a manifest, with optional judgement/combo-digit art.
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
