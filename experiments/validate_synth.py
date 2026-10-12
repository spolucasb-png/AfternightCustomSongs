#!/usr/bin/env python3
"""Offline self-check for the Afternight synthetic Test A candidate.

Validates ONLY our side: fixture well-formedness (counts, lane bounds,
monotonic millisecond times, required fields, unique id) and the
deterministic preview mapping our beats -> FNF sectionNote rows
[timeMs, lane, sustainMs]. This is NOT gameplay evidence: the engine's
chart-container schema is unproven (see probe_f_preflight constants).
Run: python experiments/afternight/validate_synth.py (exit 0 = all passed).
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "synth_a_candidate.json"
BPM = 200.0
BEAT_MS = 60000.0 / BPM


def fail(msg):
    print("FAIL:", msg)
    return False


def main():
    ok = True
    try:
        chart = json.loads(FIXTURE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print("FAIL: unreadable fixture:", e)
        return 1
    for key in ("id", "songId", "bpm", "notes"):
        if key not in chart:
            ok = fail(f"missing required field {key!r}") and ok
    if not ok:
        return 1
    if not isinstance(chart["id"], str) or not chart["id"].startswith("afn_synth_"):
        ok = fail("id must be a unique afn_synth_-prefixed test identifier")
    notes = chart["notes"]
    if not isinstance(notes, list) or not notes:
        print("FAIL: notes must be a non-empty list")
        return 1
    prev_t = -1.0
    rows = []
    for i, n in enumerate(notes):
        if not isinstance(n, dict):
            ok = fail(f"note {i} not an object") and ok
            continue
        b, l, d = n.get("b"), n.get("l"), n.get("d", 0)
        if not (isinstance(b, (int, float)) and isinstance(l, int)):
            ok = fail(f"note {i} needs numeric b + integer l") and ok
            continue
        if not (1 <= l <= 4):
            ok = fail(f"note {i} lane {l} out of 1..4") and ok
        t_ms = b * BEAT_MS
        if t_ms < 0 or (d is not None and d < 0):
            ok = fail(f"note {i} negative time/length") and ok
        if t_ms < prev_t:
            ok = fail(f"note {i} breaks time order") and ok
        prev_t = t_ms
        # player side: our lanes 1-4 -> FNF lanes 4-7 (mustHitSection sections)
        rows.append([round(t_ms, 3), (l - 1) + 4, round((d or 0) * BEAT_MS, 3)])
    # holds, if any, must be last-segment chains we can already describe
    print(f"notes: {len(notes)}, lanes ok, times monotonic ms, id ok")
    print("FNF-row preview [timeMs, lane0, sustainMs]:")
    for r in rows:
        print(" ", r)
    print("mapping: lane = (l-1)+4 player-side, timeMs = b*%.3f, sustainMs = d*%.3f" % (BEAT_MS, BEAT_MS))
    container = {
        "song": chart.get("title", chart["id"]),
        "bpm": chart["bpm"],
        "notes": [{
            "mustHitSection": True,
            "sectionNotes": [[t, l, s] for (t, l, s) in rows],
        }],
        "events": [],
    }
    print("Afternight container preview (field names per probe-F constants +")
    print("live section objects; top-level nesting per FNF convention):")
    print(json.dumps(container))
    print("NOTE: container accepted by engine UNPROVEN; preview is format math only.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
