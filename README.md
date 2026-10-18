# AfternightCustomSongs

A custom-chart system for **Project Afternight** (Roblox, PlaceId
`13042495892`), inspired by GakuranCustomSongs but a separate project with no
merge obligation. The current entry point is the Rayfield-based mod
`src/afn_rayfield.lua` (v2.3.0), driven from inside the game's menu; the
earlier WindUI / single-chart players remain in `src/` for reference.

## Current status (v2.3.0, 2026-10-18)

Custom charts with local audio are **playable and user-verified** end to end:
chart and difficulty selection, SV (spawn-window solver + teleport tamer),
noteskins, judgement art, covers, local stats, results and HUD labels all
work live. Same-session replay without rejoining is user-verified; rejoin only
if Stop ever reports `cleanup-incomplete` after a retry.
See [`ROADMAP.md`](ROADMAP.md) for the build history and
[`HANDOFF.md`](HANDOFF.md) for session-level evidence and known side effects.

| Capability | Status |
|---|---|
| Rayfield mod (`src/afn_rayfield.lua`) | v2.3.0 live-verified: menu, play/stop, stats, covers, skins, results |
| Engine discovery / note routing | Mapped; live-verified across all play paths |
| Full-play path + local audio | Live-verified and human-played (multi-key 4K-10K, SV, BPM changes) |
| Human hit / judgement path | User-verified playable (hits land, misses drain without killing the run) |
| Song-end results screen | User-verified (engine `endSong` allowlist; menu title + difficulty labels) |
| Sustain chains, SV, BPM changes | Holds convert and play; spawn-window solver + teleport tamer live-verified |
| Noteskins (osu!mania / Quaver / Etterna) | User-verified live, incl. 5K centre-lane art and Etterna scale normalization |
| Judgement / combo popup art | Built; pooled-label swap fixed (session 15); verified in live play |
| Repeated play without rejoining | User-verified working; rejoin only if Stop reports incomplete cleanup |
| Batch porting (SM/Etterna/.osz -> workspace) | Drove the wave-1 drop: 32 songs / 37 charts staged and played |

The mod uses a non-invocation boundary: it avoids direct score, persistence,
and remote API calls and does not install networking hooks; the single remote
fetch is the Rayfield UI library (`sirius.menu/rayfield`). This is **not** a
strict network-silence guarantee; engine-internal side effects are documented
in `HANDOFF.md` and must remain evidence-gated.

## Recent releases

- v2.3.0 - hold bodies pinned under receptors, 5K centre-lane pack art,
  results labels, Etterna skin scale.
- v2.2.1 - HUD shows the menu title + real difficulty.
- v2.2.0 - local play stats + Recent/Favourites sorting.
- v2.1.0 - song covers from staged pack art.

## Target game (observed, live client)

FNF-style rhythm engine: chart-driven gameplay module (`parseChart`,
`addNotesFromChart`, `createNote`, `startSong`, …), millisecond `strumTime`
notes with lane/sustain chains, FNF Conductor (BPM/BaseBPM/CurBPM, Offset),
**native** slider-velocity support (`svFunctions`), song audio transport
(`songPlayer`), map registry (`mapModule.Maps`).

## Layout

- `src/afn_rayfield.lua` — the current mod (v2.3.0): song/difficulty menu,
  play pipeline, SV solvers, skins, stats, covers, results + HUD labels.
- `src/player_core.lua` — callable preflight/play/stop core (pre-Rayfield player).
- `src/player_windui.lua` — local chart-picker UI using the vendored WindUI
  build (legacy).
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
  plus a manifest, with optional judgement/combo-digit art and per-direction
  scale normalization.
- `converters/batch_port.py` — batch scan/stage for SM/Etterna song folders or
  `.osz` archives (audio/cover auto-pick, per-stem no-overwrite copies); drove
  the wave-1 content drop.
- `tests/` — offline static checks, chart-model checks and converter regression
  tests; run by CI on every push.
- `fixtures/` — synthetic and converted chart JSON fixtures.
- `experiments/` and `docs/` — provenance, probes, decompile snapshots and reports.

## Requirements (from evidence)

- Executor: Madium (all 13 capabilities verified live: `getgc`, file I/O,
  assets, `gethui`, `getconnections`, introspection). No `delfile`.
- Deployment: `afn_rayfield.lua` at the executor workspace root; content lives
  in the workspace `AfternightCustomSongs/` folder (`Charts/`, `Audio/`,
  `Covers/`, `Skins/`, plus `Stats.json` / `Settings.json`). The legacy WindUI
  player deploys `afn_player_core.lua`, `afn_player_windui.lua` and the
  vendored `afn_windui.lua`.
- The vendor still contains dormant network/key-system paths; current player
  configuration does not enable those paths. See `src/player_windui.lua`.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: do not
  modify its production code, converters, charts, or verified outputs.

## Tests and CI

The suites are dependency-free Python 3 scripts (stdlib only). Run them all
with `python tests/test_*.py` plus `python experiments/validate_synth.py`. The
GitHub Actions workflow (`.github/workflows/python-tests.yml`) runs every suite
on each push and pull request.

## Provenance

Spike evidence: `experiments/` (probe sources) + `docs/` (reports).
Gakuran-side reference commit: `6ca111b` (frozen during the spike).
