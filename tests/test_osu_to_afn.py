#!/usr/bin/env python3
"""Offline tests for converters/osu_to_afn.py (prototype, no client needed)."""
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "converters"))
import osu_to_afn  # noqa: E402


def make_osu(path, keys=4, objects=None, timing=None):
    if objects is None:
        objects = [
            "64,192,1200,1,0,0:0:0:0:",       # col 1 tap
            "192,192,1800,1,0,0:0:0:0:",      # col 2 tap
            "320,192,2400,1,0,0:0:0:0:",      # col 3 tap
            "448,192,3000,128,0,3600:0:0:0:0:",  # col 4 hold 600ms
            "256,192,5000,12,0,0:0:0:0:",     # spinner -> skipped
        ]
    if timing is None:
        timing = ["0,300,4,2,0,100,1,0", "2000,-50,4,2,0,100,0,0",
                  "2000,-200,4,2,0,100,0,0", "60000,250,4,2,0,100,1,0"]
    path.write_text("\n".join([
        "osu file format v14", "[General]", "AudioFilename: audio.mp3",
        "Mode: 3", "[Metadata]", "Title:ProtoTest", "Artist:Test",
        "Creator:Test", "Version:4K", "[Difficulty]", f"CircleSize:{keys}",
        "[TimingPoints]"] + timing + ["[HitObjects]"] + objects),
        encoding="utf-8")


def test_basic(tmp):
    src = tmp / "t.osu"
    make_osu(src)
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    s = w["song"]
    assert set(w) == {"song"}
    assert s["bpm"] == 200.0 and s["keyCount"] == 4
    assert s["playerKeyCount"] == 4 and s["events"] == []
    sec = s["notes"]
    assert len(sec) == 1 and sec[0]["mustHitSection"] is False
    assert sec[0]["sectionNotes"] == [
        [1200, 4, 0], [1800, 5, 0], [2400, 6, 0], [3000, 7, 600]]
    assert s["SVChanges"] == [{"startTime": 2000, "multiplier": 0.5}]
    assert s["audioFile"] == "audio.mp3"
    print("PASS test_basic")


def test_fold_7k(tmp):
    xs = [int((c + 0.5) * 512 / 7) for c in range(7)]
    objs = [f"{x},192,1000,1,0,0:0:0:0:" for x in xs]
    src = tmp / "f.osu"
    make_osu(src, keys=7, objects=objs, timing=["0,300,4,2,0,100,1,0"])
    w = osu_to_afn.convert_file(src, tmp / "out")
    rows = w["song"]["notes"][0]["sectionNotes"]
    lanes = sorted(r[1] for r in rows)
    assert len(rows) == 4 and len(set(lanes)) == 4, lanes  # 7-at-once -> 4 kept
    assert set(lanes) <= {4, 5, 6, 7} and all(r[0] == 1000 for r in rows)
    print("PASS test_fold_7k")


def test_idempotent_and_refusal(tmp):
    src = tmp / "t.osu"
    make_osu(src)
    out = tmp / "out"
    w1 = osu_to_afn.convert_file(src, out)
    w2 = osu_to_afn.convert_file(src, out)  # byte-identical rerun ok
    assert w2 is not None
    dest = next(out.glob("*.chart.json"))
    dest.write_text(json.dumps({"different": True}))
    assert osu_to_afn.convert_file(src, out) is None  # refusal, no clobber
    assert json.loads(dest.read_text()) == {"different": True}
    assert w1 is not None
    print("PASS test_idempotent_and_refusal")


def test_same_timestamp_red_lines_preserve_file_order(tmp):
    src = tmp / "same_red_time.osu"
    make_osu(
        src,
        timing=[
            "0,300,4,2,0,100,1,0",  # first in file: 200 BPM
            "0,200,4,2,0,100,1,0",  # second at same time: 300 BPM
        ],
    )
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["song"]["bpm"] == 200.0
    print("PASS test_same_timestamp_red_lines_preserve_file_order")


def main():
    tests = [test_basic, test_fold_7k, test_idempotent_and_refusal,
             test_same_timestamp_red_lines_preserve_file_order]
    failed = 0
    for fn in tests:
        with tempfile.TemporaryDirectory() as td:
            try:
                fn(Path(td))
            except (AssertionError, ValueError) as e:
                failed += 1
                print("FAIL", fn.__name__, "-", repr(e))
    print(f"{len(tests) - failed}/{len(tests)} passed (offline only)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
