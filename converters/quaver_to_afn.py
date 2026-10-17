#!/usr/bin/env python3
"""Quaver (.qua) -> AfternightCustomSongs chart-wrapper converter.

.quaffs are YAML; parsed here with a small targeted reader for exactly the
fields a conversion needs (no PyYAML dependency), mirroring
gakurancustomsongs/tools/qua2gakuran.py (reference only; nothing imported):
  * Mode must be KeysN (lane = StartTime/Lane 1-based taps, EndTime holds)
  * .qua clock is MILLISECONDS (no beat integration needed)
  * TimingPoints (StartTime/Bpm, Bpm>0) -> base BPM + bpmChanges[1:]
  * SliderVelocities (StartTime/Multiplier, verbatim incl. 0.0 = Quaver
    full stop, which the AFN engine renders the same way) -> SV map
  * Same-timestamp entries keep file order (stable sort), last wins

Shared emission (ms rows, lanes 4-7, hold clamp, stacks warning, SV anchor,
no-overwrite) lives in converters/afn_common.py.

Keys4 maps 1:1; more keys fold to 4 (shared folder); fewer keys map onto
lanes 1..K directly (right lanes stay empty), same as the osu! converter.

Run: python converters/quaver_to_afn.py <in.qua> --out-dir <charts dir>
"""
import argparse
import sys
from pathlib import Path

from afn_common import (LANES, NATIVE_MAX, build_rows, build_sv_rates,
                        build_wrapper, check_stacks, fold_columns,
                        report_chart, sanitize_id, write_wrapper)


def parse_qua(text):
    """Return (scalars, lists) for TimingPoints/SliderVelocities/HitObjects.
    Flat YAML subset only: top-level `Key: value` scalars and `- ` list
    items of `key: value` pairs. Anything else is ignored."""
    lists = {"TimingPoints": [], "SliderVelocities": [], "HitObjects": []}
    scalars, cur, item = {}, None, None
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        if indent == 0 and ":" in s and not s.startswith("-"):
            k, v = s.split(":", 1)
            k, v = k.strip(), v.strip()
            if k in lists and v == "":
                cur, item = k, None
                continue
            cur, item = None, None
            scalars[k] = v
        elif cur and s.startswith("- "):
            item = {}
            lists[cur].append(item)
            rest = s[2:].strip()
            if ":" in rest:
                k, v = rest.split(":", 1)
                item[k.strip()] = v.strip()
        elif cur and item is not None and ":" in s and not s.startswith("-"):
            k, v = s.split(":", 1)
            item[k.strip()] = v.strip()
    return scalars, lists


def fnum(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def unquote(v):
    """Quaver writes YAML-ish scalars; some authors quote strings. Strip one
    matching pair of surrounding quotes for DISPLAY values only (chart ids
    keep the raw value, which sanitize_id strips identically)."""
    v = (v or "").strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("\"", "'"):
        v = v[1:-1].strip()
    return v


def convert_file(qua_path, out_dir, sv_cap=None):
    import re
    warnings = []
    text = Path(qua_path).read_text(encoding="utf-8", errors="replace")
    scalars, lists = parse_qua(text)

    m = re.match(r"Keys(\d+)$", scalars.get("Mode", ""))
    if not m:
        print(f"ERROR: Mode {scalars.get('Mode', '?')!r} is not Keys "
              f"(only Quaver Keys maps are supported)", file=sys.stderr)
        return None
    try:
        keys = max(1, min(18, int(m.group(1))))
    except (TypeError, ValueError):
        print(f"ERROR: unparsable key count in Mode {m.group(0)!r}",
              file=sys.stderr)
        return None

    tps = [(fnum(i.get("StartTime")), fnum(i.get("Bpm")))
           for i in lists["TimingPoints"]]
    tps = [(t, b) for t, b in tps if b > 0]
    tps.sort(key=lambda p: p[0])  # stable: file order kept for ties
    if not tps:
        print(f"ERROR: no timing points in '{Path(qua_path).name}'",
              file=sys.stderr)
        return None
    base_bpm = round(tps[0][1], 3)
    bpm_changes = [
        {"startTime": round(t, 3), "bpm": round(b, 3)}
        for t, b in tps[1:]
    ]
    if bpm_changes:
        warnings.append(
            f"{len(bpm_changes)} BPM change(s) emitted as top-level "
            f"bpmChanges (base {base_bpm} from t={tps[0][0]}ms)")

    svs = sorted(((fnum(i.get("StartTime")), fnum(i.get("Multiplier"), 0.0))
                  for i in lists["SliderVelocities"]), key=lambda p: p[0])

    objs = []  # (start_ms, end_ms|None, col_1based)
    skipped = 0
    for h in lists["HitObjects"]:
        t = fnum(h.get("StartTime"))
        try:
            col = int(fnum(h.get("Lane"), 1))
        except (TypeError, ValueError):
            skipped += 1
            continue
        col = max(1, min(keys, col))
        end = fnum(h["EndTime"]) if "EndTime" in h else None
        if end is not None and end <= t:
            end = None  # degenerate hold: keep the tap
        objs.append((t, end, col))
    if not objs:
        print(f"ERROR: no convertible hit objects in '{Path(qua_path).name}'",
              file=sys.stderr)
        return None
    if skipped:
        warnings.append(f"{skipped} hit-object row(s) skipped (bad lane)")

    if keys > NATIVE_MAX:
        placed, stats = fold_columns(objs, keys, LANES)
        warnings.append(
            f"folded {keys}K -> {LANES} lanes: {stats['source']} objects, "
            f"{stats['kept']} kept, {stats['rerouted']} rerouted, "
            f"{stats['dropped']} dropped")
        lanes = LANES
    else:
        placed = [(t, e, c) for t, e, c in
                  sorted(objs, key=lambda o: (o[0], o[1] if o[1] is not None else float("inf"), o[2]))]
        stats = None
        lanes = keys
        if keys != LANES:
            warnings.append(
                f"native {keys}K: player rows use lanes {keys}-{2 * keys - 1}")

    rows, _clamped, row_warnings = build_rows(placed, base_bpm, lanes)
    warnings.extend(row_warnings)
    stacks_warning = check_stacks(rows)
    if stacks_warning:
        warnings.append(stacks_warning)

    sv_rates, sv_warnings = build_sv_rates(svs, ".qua SV", cap=sv_cap)
    warnings.extend(sv_warnings)
    if "BackgroundFile" in scalars:
        warnings.append("BackgroundFile ignored (no AFN background support)")

    title = scalars.get("Title", "Unknown").strip() or "Unknown"
    diff = scalars.get("DifficultyName", "Normal").strip() or "Normal"
    chart_id = sanitize_id(f"afn_{title}_{diff}")
    audio_name = scalars.get("AudioFile", "").strip() or None
    wrapper = build_wrapper(chart_id, base_bpm, rows, bpm_changes,
                            sv_rates, audio_name,
                            meta={"title": unquote(title),
                                  "artist": unquote(scalars.get("Artist")),
                                  "difficulty": unquote(diff)},
                            lanes=lanes)
    dest = write_wrapper(out_dir, chart_id, wrapper)
    if dest is None:
        return None
    report_chart(dest, rows, base_bpm, bpm_changes, sv_rates, warnings,
                 lanes=lanes)
    return wrapper


def main():
    ap = argparse.ArgumentParser(description="Convert Quaver .qua to Afternight chart wrappers")
    ap.add_argument("input", type=Path, help=".qua file (or directory of .qua)")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--sv-cap", type=float, default=None,
                    help="clamp |SV multiplier| (teleport tamer; default: verbatim)")
    args = ap.parse_args()
    inp = args.input
    quas = sorted(inp.glob("*.qua")) if inp.is_dir() else [inp]
    if not quas:
        print(f"ERROR: no .qua found at '{inp}'", file=sys.stderr)
        return 1
    results = [convert_file(q, args.out_dir, sv_cap=args.sv_cap) for q in quas]
    results = [r for r in results if r is not None]
    print(f"Done: {len(results)} chart(s) converted")
    return 0 if results else 1


if __name__ == "__main__":
    sys.exit(main())
