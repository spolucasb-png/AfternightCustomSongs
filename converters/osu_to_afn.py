#!/usr/bin/env python3
"""osu!mania (.osu) -> AfternightCustomSongs chart-wrapper converter (prototype).

Output is the engine's fixed-chart shape (see fixtures/):
  {"song": {"song": id, "bpm": <first red>, "keyCount": 4,
            "playerKeyCount": 4,
            "notes": [{"mustHitSection": false,
                       "sectionNotes": [[timeMs, lane, sustainMs], ...]}],
            "events": [],
            "audioFile": "<AudioFilename basename, if present>"},
   "bpmChanges": [{"startTime": ms, "bpm": n}, ...],       # reds[1:], file order
   "sliderVelocities": [{"startTime": ms, "multiplier": m}]}

Placement is source-read, not guessed: `parseChart` calls
`Conductor.mapBPMChanges(fixedChart)`, which reads TOP-LEVEL `bpmChanges`
(ms-anchored entries) and otherwise falls back to section `changeBPM` flags
we do not emit; SV reads TOP-LEVEL `sliderVelocities` (gated live by the
client's SVChanges flag, observed true). Taps/holds stay absolute-ms rows
in a single section, so BPM changes need no note-time conversion (unlike
beat-axis engines). Fixers pass charts without `generatedBy`/`version` or
`format` markers through untouched, so top-level keys survive `fixChart`.

Timing math follows gakurancustomsongs/tools/osu2gakuran.py (reference only;
nothing imported): stable time sort with last-in-file winning same-time SV,
mania column = int(x * keys / 512) + 1, holds via endTime, >4K folded to 4
lanes. Afternight rows are MILLISECONDS (not beats); lanes 4-7 in a
mustHitSection=false section route player-side R/0-3 per the decompile model
(live-proven by the tap test).

Timing math follows gakurancustomsongs/tools/osu2gakuran.py (reference only;
nothing imported): stable time sort with last-in-file winning same-time SV,
mania column = int(x * keys / 512) + 1, holds via endTime, >4K folded to 4
lanes. Afternight rows are MILLISECONDS (not beats); lanes 4-7 in a
mustHitSection=false section route player-side R/0-3 per the decompile model
(unverified live until the tap test passes).

Prototype scope (deliberate):
- osu!mania only; other modes are refused, not approximated.
- Multi-BPM via top-level `bpmChanges` (every red line after the first, in
  file order). Same-timestamp reds are kept in file order; the engine skips
  no-change entries on its own.
- SV rates verbatim as top-level `sliderVelocities`; same-time duplicates
  collapse to last-in-file.
- Never overwrites an existing file with different bytes.

Run: python converters/osu_to_afn.py <in.osu> --out-dir fixtures/
"""
import argparse
import json
import re
import sys
from pathlib import Path

from afn_common import (FOLD_MIN_GAP_MS, LANES, build_rows, build_sv_rates,
                        build_wrapper, check_stacks, fold_columns,
                        report_chart, sanitize_id, write_wrapper)


def parse_osu(text):
    sections, current = {}, None
    for raw in text.splitlines():
        line = raw.strip().lstrip("\ufeff").rstrip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections[current] = []
        elif current is not None and not line.startswith("//"):
            sections[current].append(line)
    return sections


def meta(sections, key, default=None):
    for sec in ("Metadata", "General", "Difficulty"):
        for line in sections.get(sec, []):
            if line.startswith(key + ":"):
                return line.split(":", 1)[1].strip()
    return default


def parse_timing(sections):
    reds, svs = [], []
    for line in sections.get("TimingPoints", []):
        parts = line.split(",")
        if len(parts) < 2:
            continue
        try:
            t, bl = float(parts[0]), float(parts[1])
        except ValueError:
            continue
        uninherited = parts[6].strip() == "1" if len(parts) > 6 else bl > 0
        if uninherited and bl > 0:
            reds.append((t, bl))
        elif bl < 0:
            svs.append((t, -100.0 / bl))
    reds.sort(key=lambda p: p[0])  # stable: preserve file order for same-time reds
    svs.sort(key=lambda p: p[0])  # stable: file order kept for ties
    deduped = []
    for t, m in svs:
        if deduped and deduped[-1][0] == t:
            deduped[-1] = (t, m)  # last in file wins
        else:
            deduped.append((t, m))
    return reds, deduped


def convert_file(osu_path, out_dir, sv_cap=None):
    warnings = []
    text = Path(osu_path).read_text(encoding="utf-8", errors="replace")
    sections = parse_osu(text)
    try:
        mode = int(meta(sections, "Mode", "0") or 0)
    except (TypeError, ValueError):
        print(f"ERROR: unparsable Mode {meta(sections, 'Mode', None)!r} "
              f"(only osu!mania, Mode 3, is supported)", file=sys.stderr)
        return None
    if mode != 3:
        print("ERROR: only osu!mania (Mode 3) is supported by this prototype",
              file=sys.stderr)
        return None
    try:
        keys = max(1, min(18, int(float(meta(sections, "CircleSize", "4") or 4))))
    except (TypeError, ValueError):
        print(f"ERROR: unparsable CircleSize {meta(sections, 'CircleSize', None)!r}",
              file=sys.stderr)
        return None
    reds, svs = parse_timing(sections)
    if not reds:
        print("ERROR: no uninherited timing points", file=sys.stderr)
        return None
    base_bpm = round(60000.0 / reds[0][1], 3)
    bpm_changes = [
        {"startTime": round(t, 3), "bpm": round(60000.0 / bl, 3)}
        for t, bl in reds[1:]
    ]
    if bpm_changes:
        warnings.append(
            f"{len(bpm_changes)} BPM change(s) emitted as top-level "
            f"bpmChanges (base {base_bpm} from t={reds[0][0]}ms)")

    objs = []  # (start_ms, end_ms|None, col_1based)
    skipped = 0
    for line in sections.get("HitObjects", []):
        parts = line.split(",")
        if len(parts) < 4:
            skipped += 1
            continue
        try:
            x, t, htype = float(parts[0]), float(parts[2]), int(parts[3])
        except ValueError:
            skipped += 1
            continue
        col = max(1, min(keys, int(x * keys / 512.0) + 1))
        if htype & 128 and len(parts) > 5:
            m = re.match(r"[-+]?\d+(?:\.\d+)?", parts[5])
            if not m:
                skipped += 1
                continue
            end = float(m.group())
            if end <= t:
                skipped += 1
                continue
            objs.append((t, end, col))
        elif htype & 1:
            objs.append((t, None, col))
        else:
            skipped += 1
    if not objs:
        print("ERROR: no convertible hit objects", file=sys.stderr)
        return None
    if skipped:
        warnings.append(
            f"{skipped} hit-object row(s) skipped (unsupported type, "
            f"malformed, or invalid hold end)")

    if keys > LANES:
        placed, stats = fold_columns(objs, keys, LANES)
        warnings.append(
            f"folded {keys}K -> {LANES} lanes: {stats['source']} objects, "
            f"{stats['kept']} kept, {stats['rerouted']} rerouted, "
            f"{stats['dropped']} dropped")
    else:
        placed = [(t, e, c) for t, e, c in
                  sorted(objs, key=lambda o: (o[0], o[1] if o[1] is not None else float("inf"), o[2]))]
        stats = None

    rows, _clamped, row_warnings = build_rows(placed, base_bpm)
    warnings.extend(row_warnings)

    stacks_warning = check_stacks(rows)
    if stacks_warning:
        warnings.append(stacks_warning)

    sv_rates, sv_warnings = build_sv_rates(svs, ".osu SV", cap=sv_cap)
    warnings.extend(sv_warnings)

    title = meta(sections, "Title", "Unknown")
    artist = meta(sections, "Artist", "")
    version = meta(sections, "Version", "Normal")
    chart_id = sanitize_id(f"afn_{artist}_{title}_{version}")
    audio_name = meta(sections, "AudioFilename", None)
    wrapper = build_wrapper(chart_id, base_bpm, rows, bpm_changes,
                            sv_rates, audio_name)
    dest = write_wrapper(out_dir, chart_id, wrapper)
    if dest is None:
        return None
    report_chart(dest, rows, base_bpm, bpm_changes, sv_rates, warnings)
    return wrapper


def main():
    ap = argparse.ArgumentParser(description="Convert osu!mania to Afternight chart wrappers (prototype)")
    ap.add_argument("input", type=Path, help=".osu file")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--sv-cap", type=float, default=None,
                    help="clamp |SV multiplier| (teleport tamer; default: verbatim)")
    args = ap.parse_args()
    return 0 if convert_file(args.input, args.out_dir, sv_cap=args.sv_cap) else 1


if __name__ == "__main__":
    sys.exit(main())
