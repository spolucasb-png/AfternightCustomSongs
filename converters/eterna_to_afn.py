#!/usr/bin/env python3
"""Etterna/SM5 (.sm/.ssc) -> AfternightCustomSongs chart-wrapper converter.

StepMania timing is BEAT-anchored and must be integrated to the engine's
absolute-ms axis:
  * #BPMS beat=bpm,... (beat 0 required) -> base BPM + bpmChanges[1:] in ms
  * #STOPS/#DELAYS beat=seconds lengthen song time: all beats strictly
    AFTER the event beat shift later (notes exactly on the event beat are
    unshifted; sub-10ms corner, documented)
  * #WARPS beat=lengthBeats are unhittable skips: notes inside are dropped
    with a warning, and warped time is removed from later beats
  * #SCROLLS (SM5) beat=mult -> SV map in ms
  * #OFFSET seconds shifts every timestamp
Steps: #NOTES dance-single blocks only (4 columns: 1 tap, 2/4 hold/roll
head, 3 tail, M mine skipped, K keysound skipped, F fake skipped, L lift
as tap). Every dance-single block converts (id carries difficulty+meter);
non-4K Styles are refused, not approximated.

Shared emission (ms rows, lanes 4-7, hold clamp, stacks warning, SV anchor,
no-overwrite) lives in converters/afn_common.py.

Run: python converters/eterna_to_afn.py <in.sm|in.ssc> --out-dir <charts>
"""
import argparse
import re
import sys
from pathlib import Path

from afn_common import (LANES, build_rows, build_sv_rates, build_wrapper,
                        check_stacks, fold_columns, report_chart,
                        sanitize_id, write_wrapper)


def parse_sm(text):
    """Return list of (TAG, value) in file order; values are raw (may span
    lines). Only well-formed #TAG:...; pairs are kept."""
    out = []
    for m in re.finditer(r"#([A-Za-z0-9]+):(.*?);", text, re.DOTALL):
        out.append((m.group(1).upper(), m.group(2).strip()))
    return out


def fnum(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def parse_pairs(value):
    """Parse 'beat=val,beat=val,...' -> [(beat, val)] skipping malformed."""
    pairs = []
    for chunk in value.split(","):
        chunk = chunk.strip()
        if not chunk or "=" not in chunk:
            continue
        b, v = chunk.split("=", 1)
        beat, val = fnum(b.strip()), fnum(v.strip())
        if beat is None or val is None or beat < 0:
            continue
        pairs.append((beat, val))
    pairs.sort(key=lambda p: p[0])  # stable: file order kept for ties
    return pairs


def make_clock(bpms, stops, delays, warps):
    """Beat -> song-ms conversion. bpms [(beat, bpm>0)] sorted; stops/delays
    [(beat, sec)]; warps [(beat, lenBeats)]."""
    segs = [(b, 60000.0 / bpm) for b, bpm in bpms]

    def seg_ms(beat):
        msb = segs[0][1]
        for sb, sm in segs:
            if sb <= beat:
                msb = sm
            else:
                break
        return msb

    def base_ms(b):
        # integrate piecewise from 0..b
        t = 0.0
        marks = sorted({0.0} | {sb for sb, _ in segs if sb < b} | {b})
        for lo, hi in zip(marks, marks[1:]):
            t += (hi - lo) * seg_ms(lo)
        for eb, sec in stops + delays:
            if eb < b and sec > 0:
                t += sec * 1000.0
        return t

    def warped_out(b):
        cut = 0.0
        for w0, wl in warps:
            if wl <= 0 or b <= w0:
                continue
            cut += base_ms(min(b, w0 + wl)) - base_ms(w0)
        return cut

    def ms(beat):
        return base_ms(beat) - warped_out(beat)

    def in_warp(beat):
        return any(w0 <= beat < w0 + wl for w0, wl in warps if wl > 0)

    return ms, in_warp


def parse_notes_block(value):
    """Split a #NOTES value into (stepstype, difficulty, meter, notedata).
    Returns None when the header is malformed."""
    parts = value.split(":", 5)
    if len(parts) < 6:
        return None
    stepstype = parts[0].strip().lower()
    return stepstype, parts[2].strip(), parts[3].strip(), parts[5]


def extract_measures(notedata):
    """Yield (measure_index, [row_str, ...]) for non-empty measures."""
    idx = 0
    for chunk in notedata.split(","):
        rows = [ln.strip() for ln in chunk.replace(";", "").splitlines()]
        rows = [r for r in rows if r]
        if rows:
            yield idx, rows
            idx += 1


def convert_file(sm_path, out_dir, difficulty=None, sv_cap=None):
    warnings = []
    text = Path(sm_path).read_text(encoding="utf-8", errors="replace")
    tags = parse_sm(text)
    single = {}
    for tag, value in tags:
        single.setdefault(tag, value)

    title = (single.get("TITLE", "") or "Unknown").strip() or "Unknown"
    audio_name = (single.get("MUSIC", "") or "").strip() or None
    # SM/SSD timing treats beat 0 as sitting at second = -#OFFSET: the
    # initial timing line segment ends at end_second =
    # -m_fBeat0OffsetInSeconds (StepMania TimingData.cpp), i.e. every beat's
    # audio position is integral(beat) - OFFSET. A positive #OFFSET moves
    # all chart content BEFORE the audio start. The old +offset application
    # put charts 2x OFFSET late (caught staging insert_coin/sayonara: the
    # last note fell ~1.2 s past the end of the 38.5 s insert_coin mp3;
    # with the flip it lands 0.18 s before the end).
    offset_ms = -((fnum(single.get("OFFSET", "0"), 0.0) or 0.0) * 1000.0)

    bpms = [(b, v) for b, v in parse_pairs(single.get("BPMS", ""))
            if v > 0]
    if not bpms:
        print(f"ERROR: no usable #BPMS in '{Path(sm_path).name}'",
              file=sys.stderr)
        return None
    stops = [(b, v) for b, v in parse_pairs(single.get("STOPS", ""))
             if v > 0]
    delays = [(b, v) for b, v in parse_pairs(single.get("DELAYS", ""))
              if v > 0]
    warps = [(b, v) for b, v in parse_pairs(single.get("WARPS", ""))
             if v > 0]
    if stops or delays:
        warnings.append(
            f"{len(stops)} stop(s), {len(delays)} delay(s): beats strictly "
            f"after each event shift later (notes exactly on an event beat "
            f"are unshifted)")
    if warps:
        warnings.append(
            f"{len(warps)} warp(s): notes inside warped beats are unhittable "
            f"in SM and are dropped")
    ms_of, in_warp = make_clock(bpms, stops, delays, warps)

    base_bpm = round(bpms[0][1], 3)
    bpm_changes = [
        {"startTime": round(ms_of(b) + offset_ms, 3), "bpm": round(v, 3)}
        for b, v in bpms[1:]
    ]
    if bpm_changes:
        warnings.append(
            f"{len(bpm_changes)} BPM change(s) emitted as top-level "
            f"bpmChanges (base {base_bpm})")

    scrolls = parse_pairs(single.get("SCROLLS", ""))
    svs = sorted(((ms_of(b) + offset_ms, m) for b, m in scrolls),
                 key=lambda p: p[0])

    blocks = []
    for tag, value in tags:
        if tag != "NOTES":
            continue
        parsed = parse_notes_block(value)
        if parsed is None:
            warnings.append("a #NOTES block with a malformed header skipped")
            continue
        stepstype, diff, meter, notedata = parsed
        if stepstype != "dance-single":
            warnings.append(f"StepsType '{stepstype}' skipped (4K only)")
            continue
        if difficulty and diff.lower() != difficulty.lower():
            continue
        blocks.append((diff or "Unknown", meter or "?", notedata))
    if not blocks:
        print(f"ERROR: no dance-single #NOTES in '{Path(sm_path).name}'",
              file=sys.stderr)
        return None

    wrappers = []
    for diff, meter, notedata in blocks:
        objs = []  # (start_ms, end_ms|None, col_1based)
        skipped = warped_dropped = mines = 0
        open_heads = {}  # col -> head beat
        ncols = 0
        for _midx, rows in extract_measures(notedata):
            nrows = len(rows)
            for ri, row in enumerate(rows):
                if ncols == 0:
                    ncols = len(row)
                if len(row) != ncols:
                    skipped += 1
                    continue
                beat = _midx * 4.0 + ri * (4.0 / nrows)
                for ci, ch in enumerate(row):
                    col = ci + 1
                    if ch in ("1", "L"):
                        # L (lift) has no AFN equivalent: tap, documented.
                        if in_warp(beat):
                            warped_dropped += 1
                            continue
                        objs.append((ms_of(beat) + offset_ms, None, col))
                    elif ch in ("2", "4"):
                        if in_warp(beat):
                            warped_dropped += 1
                            continue
                        if col in open_heads:
                            warnings.append(
                                f"overlapping hold head at beat {beat} "
                                f"(kept the later one)")
                        open_heads[col] = beat
                    elif ch == "3":
                        if col in open_heads:
                            hb = open_heads.pop(col)
                            if in_warp(beat) or in_warp(hb):
                                warped_dropped += 1
                                continue
                            end = ms_of(beat) + offset_ms
                            start = ms_of(hb) + offset_ms
                            objs.append((start, end if end > start else None,
                                         col))
                        else:
                            skipped += 1  # stray tail
                    elif ch == "M":
                        mines += 1
                    elif ch in ("K", "F"):
                        skipped += 1  # keysound/fake: no hit
                    elif ch not in ("0",):
                        skipped += 1
        for col in sorted(open_heads):
            warnings.append(f"unclosed hold in column {col}: kept as tap")
            objs.append((ms_of(open_heads[col]) + offset_ms, None, col))
        if mines:
            warnings.append(f"{mines} mine(s) skipped (no AFN equivalent)")
        if warped_dropped:
            warnings.append(f"{warped_dropped} hold(s) crossing warps dropped")
        if skipped:
            warnings.append(
                f"{skipped} note row(s) skipped (malformed, stray tails, "
                f"keysounds/fakes)")
        if not objs:
            warnings.append(f"difficulty '{diff}' produced no notes; skipped")
            for wmsg in warnings:
                print(f"! {wmsg}", file=sys.stderr)
            warnings.clear()
            continue

        keys = max(c for _, _, c in objs)
        if keys > LANES:
            placed, stats = fold_columns(objs, keys, LANES)
            warnings.append(
                f"folded {keys}K -> {LANES} lanes: {stats['source']} objects, "
                f"{stats['kept']} kept, {stats['rerouted']} rerouted, "
                f"{stats['dropped']} dropped")
        else:
            placed = [(t, e, c) for t, e, c in
                      sorted(objs, key=lambda o: (o[0], o[1] if o[1] is not None else float("inf"), o[2]))]

        rows, _clamped, row_warnings = build_rows(placed, base_bpm)
        early = sum(1 for t, _e, _c in placed if t < 0)
        if early:
            warnings.append(
                f"{early} note(s) start before the audio (negative ms) — "
                f"the SM chart expects silence there")
        warnings.extend(row_warnings)
        stacks_warning = check_stacks(rows)
        if stacks_warning:
            warnings.append(stacks_warning)

        chart_id = sanitize_id(f"afn_{title}_{diff}_{meter}")
        diff_label = (diff if meter in ("", "?") else f"{diff} {meter}").strip() or diff
        sv_rates, sv_w = build_sv_rates(svs, "#SCROLLS SV", cap=sv_cap)
        wrapper = build_wrapper(chart_id, base_bpm, rows, bpm_changes,
                                sv_rates, audio_name,
                                meta={"title": title,
                                      "artist": (single.get("ARTIST", "") or "").strip(),
                                      "difficulty": diff_label})
        dest = write_wrapper(out_dir, chart_id, wrapper)
        if dest is None:
            return None
        report_chart(dest, rows, base_bpm, bpm_changes, sv_rates,
                     warnings + sv_w)
        wrappers.append(wrapper)
    return wrappers


def main():
    ap = argparse.ArgumentParser(description="Convert Etterna/SM .sm/.ssc to Afternight chart wrappers")
    ap.add_argument("input", type=Path, help=".sm/.ssc file (or directory)")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--difficulty", default=None,
                    help="only convert this difficulty name (default: all dance-single)")
    ap.add_argument("--sv-cap", type=float, default=None,
                    help="clamp |SV multiplier| (teleport tamer; default: verbatim)")
    args = ap.parse_args()
    inp = args.input
    if inp.is_dir():
        files = sorted([p for p in inp.iterdir()
                        if p.suffix.lower() in (".sm", ".ssc")])
    else:
        files = [inp]
    if not files:
        print(f"ERROR: no .sm/.ssc found at '{inp}'", file=sys.stderr)
        return 1
    results = []
    for f in files:
        w = convert_file(f, args.out_dir, difficulty=args.difficulty,
                         sv_cap=args.sv_cap)
        if w:
            results.extend(w)
    print(f"Done: {len(results)} chart(s) converted")
    return 0 if results else 1


if __name__ == "__main__":
    sys.exit(main())
