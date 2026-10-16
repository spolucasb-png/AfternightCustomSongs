#!/usr/bin/env python3
"""Shared chart-building core for the *2afn converters (osu/quaver/etterna).

Extracted verbatim from converters/osu_to_afn.py so every source format
produces byte-identical engine wrappers for identical musical content:
ms rows, lanes 4-7, sub-step hold clamp, stacks warning, verbatim SV with
last-wins dedup, t0 SV anchor, no-overwrite outputs.

The player (src/afn_rayfield.lua) and its boundary tests pin this output
shape; do not change emission semantics without updating all converters
and their suites.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

LANES = 4
FOLD_MIN_GAP_MS = 25.0


def sanitize_id(s, limit=64):
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower() or "chart"
    if len(s) <= limit:
        return s
    return s[: limit - 9].rstrip("_") + "_" + hashlib.sha1(
        s.encode("utf-8")).hexdigest()[:8]


def column_lanes(col, keys, lanes=LANES):
    lo, hi = (col - 1) * lanes, col * lanes
    overlap = [max(0, min(hi, (j + 1) * keys) - max(lo, j * keys))
               for j in range(lanes)]
    best = max(overlap)
    natural = tuple(j + 1 for j, o in enumerate(overlap) if o == best)
    centre2 = lo + hi
    order = sorted(range(1, lanes + 1),
                   key=lambda L: (abs(centre2 - (2 * L - 1) * keys), L))
    return natural, order


def fold_columns(objs, keys, lanes=LANES, min_gap_ms=FOLD_MIN_GAP_MS):
    best, duplicates = {}, 0
    for start, end, col in objs:
        key = (start, col)
        if key in best:
            duplicates += 1
            if end is not None and (best[key] is None or end > best[key]):
                best[key] = end
        else:
            best[key] = end
    items = sorted(((k[0], v, k[1]) for k, v in best.items()))
    free_at = [float("-inf")] * lanes
    last_use = [float("-inf")] * lanes
    placed = []
    rerouted = dropped = dropped_holds = 0

    def place(lane, start, end):
        free_at[lane - 1] = (end if end is not None else start) + min_gap_ms
        last_use[lane - 1] = start
        placed.append((start, end, lane))

    i = 0
    while i < len(items):
        j = i
        while j < len(items) and items[j][0] == items[i][0]:
            j += 1
        group, start = items[i:j], items[i][0]
        i = j
        pending = []
        for _, end, col in group:
            natural, order = column_lanes(col, keys, lanes)
            free = [L for L in natural if free_at[L - 1] <= start]
            if free:
                place(min(free, key=lambda L: (last_use[L - 1], L)), start, end)
            else:
                pending.append((end, col, order))
        pending.sort(key=lambda p: (p[0] is None, p[1]))
        for end, _, order in pending:
            free = [L for L in order if free_at[L - 1] <= start]
            if free:
                place(free[0], start, end)
                rerouted += 1
            else:
                dropped += 1
                if end is not None:
                    dropped_holds += 1
    stats = {"from": keys, "to": lanes, "source": len(items),
             "kept": len(placed), "rerouted": rerouted, "dropped": dropped,
             "droppedHolds": dropped_holds, "duplicates": duplicates}
    return placed, stats


def build_rows(placed, base_bpm):
    """placed [(start_ms, end_ms|None, lane_1based)] -> AFN sectionNotes
    rows (lanes 4-7) with the sub-step hold clamp. Returns (rows, clamped,
    warnings)."""
    warnings = []
    rows = []
    base_step_ms = 60000.0 / base_bpm / 4.0
    clamped = 0
    for t, end, lane in placed:
        sus = round((end - t), 3) if end is not None else 0
        if 0 < sus < base_step_ms:
            # The engine builds sus // StepCrochet segments at parse time, so
            # a sub-step hold renders as a plain tap. Lengthen to one base
            # step to preserve the map's hold (max +1 step of hold).
            sus = round(base_step_ms, 3)
            clamped += 1
        rows.append([round(t, 3), (lane - 1) + 4, sus])  # lanes 1-4 -> 4-7
    rows.sort(key=lambda r: (r[0], r[1]))
    if clamped:
        warnings.append(
            f"{clamped} sub-step hold(s) lengthened to one base step "
            f"({round(base_step_ms, 1)}ms) so the engine renders them")
    return rows, clamped, warnings


def check_stacks(rows):
    """Warn about same-lane pairs <5ms apart (engine dedups loudly)."""
    stacks = sum(1 for a, b in zip(rows, rows[1:])
                 if b[0] - a[0] < 5 and b[1] == a[1])
    if stacks:
        return (f"{stacks} same-lane pair(s) <5ms apart: engine dedups "
                f"stacked notes loudly at inject time")
    return None


def build_sv_rates(svs, first_tag):
    """svs [(t_ms, mult)] (file order, ties adjacent) -> engine
    sliderVelocities with non-finite rejection, last-in-file dedup and the
    t0 anchor. first_tag names the source in the anchor warning
    (e.g. '.osu SV'). Returns (sv_rates, warnings)."""
    warnings = []
    sv_rates = []
    for t, m in svs:
        if m != m or abs(m) == float("inf"):
            warnings.append(f"non-finite SV {m} at {t}ms skipped")
            continue
        sv_rates.append({"startTime": round(t, 3), "multiplier": round(m, 4)})
    # Same-time duplicates collapse to last-in-file (input order kept).
    deduped = []
    for e in sv_rates:
        if deduped and deduped[-1]["startTime"] == e["startTime"]:
            deduped[-1] = e
        else:
            deduped.append(e)
    sv_rates = deduped
    if sv_rates and sv_rates[0]["startTime"] > 0:
        # SV-map anchor at t=0: the engine anchors cumulative track position
        # at SV[1].startTime but runs raw time*speed before it, so a first SV
        # after t=0 teleports every on-screen note at that timestamp
        # (SOUND ARCHITECT glitch at 40.8s). Rhythm games run SV 1.0 before
        # the first change; materialize it so the map is continuous.
        sv_rates.insert(0, {"startTime": 0, "multiplier": 1})
        warnings.append(
            "prepended implicit SV {t=0ms x1.0}: first " + first_tag +
            f" is at t={sv_rates[1]['startTime']}ms")
    return sv_rates, warnings


def build_wrapper(chart_id, base_bpm, rows, bpm_changes, sv_rates,
                  audio_name=None):
    song = {
        "song": chart_id,
        "bpm": base_bpm,
        "keyCount": 4,
        "playerKeyCount": 4,
        "notes": [{"mustHitSection": False, "sectionNotes": rows}],
        "events": [],
    }
    if audio_name:
        # Basename only: the player resolves it under the executor
        # workspace Audio dir (e.g. AfternightCustomSongs/Audio/<name>).
        song["audioFile"] = Path(audio_name).name
    return {
        "song": song,
        "bpmChanges": bpm_changes,
        "sliderVelocities": sv_rates,
    }


def write_wrapper(out_dir, chart_id, wrapper):
    """Write <chart_id>.chart.json with no-overwrite semantics. Returns the
    dest Path, or None on refusal."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / f"{chart_id}.chart.json"
    blob = json.dumps(wrapper, ensure_ascii=False, separators=(",", ":"))
    if dest.exists():
        if dest.read_text(encoding="utf-8") == blob:
            pass
        else:
            print(f"ERROR: refusing to overwrite '{dest.name}' (different "
                  f"content)", file=sys.stderr)
            return None
    else:
        dest.write_text(blob, encoding="utf-8")
    return dest


def report_chart(dest, rows, base_bpm, bpm_changes, sv_rates, warnings):
    print(f"-> {dest.name}: {len(rows)} rows, "
          f"{base_bpm} BPM, {len(bpm_changes)} BPM changes, "
          f"{len(sv_rates)} SV")
    for w in warnings:
        print(f"! {w}", file=sys.stderr)
