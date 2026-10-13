#!/usr/bin/env python3
"""osu!mania (.osu) -> AfternightCustomSongs chart-wrapper converter (prototype).

Output is the engine's chart-container shape (see fixtures/):
  {"song": {"song": id, "bpm": <first red>, "keyCount": 4,
            "playerKeyCount": 4,
            "notes": [{"mustHitSection": false,
                       "sectionNotes": [[timeMs, lane, sustainMs], ...]}],
            "events": [], "SVChanges": [{"startTime": ms, "multiplier": m}],
            "audioFile": "<AudioFilename basename, if present>"}}

Timing math follows gakurancustomsongs/tools/osu2gakuran.py (reference only;
nothing imported): stable time sort with last-in-file winning same-time SV,
mania column = int(x * keys / 512) + 1, holds via endTime, >4K folded to 4
lanes. Afternight rows are MILLISECONDS (not beats); lanes 4-7 in a
mustHitSection=false section route player-side R/0-3 per the decompile model
(unverified live until the tap test passes).

Prototype scope (deliberate):
- osu!mania only; other modes are refused, not approximated.
- Single base BPM (first red line). Extra red lines produce a loud warning
  and are otherwise ignored (multi-BPM timing is a pending live test).
- SV rates verbatim; same-time duplicates collapse to last-in-file.
- SVChanges placement (inside song) is the best-supported guess from
  parseChart constants (SVChanges + mapVelocityChanges + sliderVelocities);
  NOT verified live. SV itself is a pending live test.
- Never overwrites an existing file with different bytes.

Run: python converters/osu_to_afn.py <in.osu> --out-dir fixtures/
"""
import argparse
import json
import re
import sys
from pathlib import Path

LANES = 4
FOLD_MIN_GAP_MS = 25.0


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


def sanitize_id(s, limit=64):
    import hashlib
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower() or "chart"
    if len(s) <= limit:
        return s
    return s[: limit - 9].rstrip("_") + "_" + hashlib.sha1(
        s.encode("utf-8")).hexdigest()[:8]


def convert_file(osu_path, out_dir):
    warnings = []
    text = Path(osu_path).read_text(encoding="utf-8", errors="replace")
    sections = parse_osu(text)
    mode = int(meta(sections, "Mode", "0") or 0)
    if mode != 3:
        print("ERROR: only osu!mania (Mode 3) is supported by this prototype",
              file=sys.stderr)
        return None
    keys = max(1, min(18, int(float(meta(sections, "CircleSize", "4") or 4))))
    reds, svs = parse_timing(sections)
    if not reds:
        print("ERROR: no uninherited timing points", file=sys.stderr)
        return None
    if len(reds) > 1:
        warnings.append(
            f"{len(reds) - 1} extra red line(s) ignored (prototype is "
            f"single-BPM; base {round(60000.0 / reds[0][1], 3)} from t={reds[0][0]}ms)")

    objs = []  # (start_ms, end_ms|None, col_1based)
    skipped = 0
    for line in sections.get("HitObjects", []):
        parts = line.split(",")
        if len(parts) < 4:
            continue
        try:
            x, t, htype = float(parts[0]), float(parts[2]), int(parts[3])
        except ValueError:
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

    rows = []
    for t, end, lane in placed:
        sus = round((end - t), 3) if end is not None else 0
        rows.append([round(t, 3), (lane - 1) + 4, sus])  # lanes 1-4 -> 4-7
    rows.sort(key=lambda r: (r[0], r[1]))

    stacks = sum(1 for a, b in zip(rows, rows[1:])
                 if b[0] - a[0] < 5 and b[1] == a[1])
    if stacks:
        warnings.append(
            f"{stacks} same-lane pair(s) <5ms apart: engine dedups stacked "
            f"notes loudly at inject time")

    sv_changes = []
    for t, m in svs:
        if m != m or abs(m) == float("inf"):
            warnings.append(f"non-finite SV {m} at {t}ms skipped")
            continue
        sv_changes.append({"startTime": round(t, 3), "multiplier": round(m, 4)})

    title = meta(sections, "Title", "Unknown")
    version = meta(sections, "Version", "Normal")
    chart_id = sanitize_id(f"afn_{title}_{version}")
    song = {
        "song": chart_id,
        "bpm": round(60000.0 / reds[0][1], 3),
        "keyCount": 4,
        "playerKeyCount": 4,
        "notes": [{"mustHitSection": False, "sectionNotes": rows}],
        "events": [],
        "SVChanges": sv_changes,
    }
    audio_name = meta(sections, "AudioFilename", None)
    if audio_name:
        # Basename only: the player resolves it under the executor
        # workspace Audio dir (e.g. AfternightCustomSongs/Audio/<name>).
        song["audioFile"] = Path(audio_name).name
    wrapper = {"song": song}
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
    print(f"-> {dest.name}: {len(rows)} rows, "
          f"{wrapper['song']['bpm']} BPM, {len(sv_changes)} SV")
    for w in warnings:
        print(f"! {w}", file=sys.stderr)
    return wrapper


def main():
    ap = argparse.ArgumentParser(description="Convert osu!mania to Afternight chart wrappers (prototype)")
    ap.add_argument("input", type=Path, help=".osu file")
    ap.add_argument("--out-dir", type=Path, required=True)
    args = ap.parse_args()
    return 0 if convert_file(args.input, args.out_dir) else 1


if __name__ == "__main__":
    sys.exit(main())
