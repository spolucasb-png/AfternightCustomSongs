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
    assert set(w) == {"song", "bpmChanges", "sliderVelocities"}
    assert s["bpm"] == 200.0 and s["keyCount"] == 4
    assert s["playerKeyCount"] == 4 and s["events"] == []
    sec = s["notes"]
    assert len(sec) == 1 and sec[0]["mustHitSection"] is False
    assert sec[0]["sectionNotes"] == [
        [1200, 4, 0], [1800, 5, 0], [2400, 6, 0], [3000, 7, 600]]
    assert w["bpmChanges"] == [{"startTime": 60000, "bpm": 240.0}]
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},  # t0 anchor (first .osu SV at 2000)
        {"startTime": 2000, "multiplier": 0.5}]
    assert "SVChanges" not in s
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


def test_multi_bpm_ramp(tmp):
    src = tmp / "ramp.osu"
    make_osu(
        src,
        timing=[
            "3015,363.636,4,2,0,100,1,0",    # 165 BPM base
            "40833,352.941,4,2,0,100,1,0",   # 170
            "43656,363.636,4,2,0,100,1,0",   # back to 165
            "50000,-80,4,2,0,100,0,0",       # SV 1.25
        ],
        objects=["64,192,5000,1,0,0:0:0:0:"],
    )
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["song"]["bpm"] == 165.0
    assert w["bpmChanges"] == [
        {"startTime": 40833, "bpm": 170.0},
        {"startTime": 43656, "bpm": 165.0},
    ]
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},  # t0 anchor (first .osu SV at 50000)
        {"startTime": 50000, "multiplier": 1.25}]
    print("PASS test_multi_bpm_ramp")


def test_sub_step_holds_clamped_to_one_step(tmp):
    src = tmp / "clamp.osu"
    make_osu(
        src,
        timing=["0,300,4,2,0,100,1,0"],  # 200 BPM -> 75 ms steps
        objects=[
            "64,192,1200,128,0,1240:0:0:0:0:",  # 40 ms hold -> clamped to 75
            "192,192,1800,128,0,2100:0:0:0:0:",  # 300 ms hold -> untouched
            "320,192,2400,1,0,0:0:0:0:",        # tap -> untouched
        ],
    )
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["song"]["notes"][0]["sectionNotes"] == [
        [1200, 4, 75.0], [1800, 5, 300], [2400, 6, 0]]
    print("PASS test_sub_step_holds_clamped_to_one_step")


def test_invalid_inputs_refused_cleanly(tmp):
    import contextlib
    import io
    # Garbage Mode must not raise.
    bad_mode = tmp / "bad_mode.osu"
    make_osu(bad_mode)
    bad_mode.write_text(
        bad_mode.read_text(encoding="utf-8").replace("Mode: 3", "Mode: mania"),
        encoding="utf-8")
    assert osu_to_afn.convert_file(bad_mode, tmp / "out1") is None
    # Garbage CircleSize must not raise.
    bad_cs = tmp / "bad_cs.osu"
    make_osu(bad_cs)
    bad_cs.write_text(
        bad_cs.read_text(encoding="utf-8").replace("CircleSize:4", "CircleSize: wide"),
        encoding="utf-8")
    assert osu_to_afn.convert_file(bad_cs, tmp / "out2") is None
    # Skipped rows (spinner + malformed hold) are reported, not silent.
    sk = tmp / "sk.osu"
    make_osu(sk, objects=[
        "64,192,1200,1,0,0:0:0:0:",          # kept tap
        "256,192,5000,12,0,0:0:0:0:",        # spinner -> skipped
        "192,192,1800,128,0,1500:0:0:0:0:",  # hold end <= start -> skipped
        "not,a,valid,row",                   # malformed -> skipped
    ])
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        w = osu_to_afn.convert_file(sk, tmp / "out3")
    assert w is not None
    assert w["song"]["notes"][0]["sectionNotes"] == [[1200, 4, 0]]
    assert "3 hit-object row(s) skipped" in buf.getvalue()
    print("PASS test_invalid_inputs_refused_cleanly")


def test_sv_no_anchor_when_first_sv_at_zero(tmp):
    src = tmp / "sv0.osu"
    make_osu(
        src,
        timing=[
            "0,363.636,4,2,0,100,1,0",
            "0,-103.0928,4,2,0,100,0,0",  # SV 0.97 already at t=0
        ],
    )
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["sliderVelocities"] == [{"startTime": 0, "multiplier": 0.97}]
    print("PASS test_sv_no_anchor_when_first_sv_at_zero")


def engine_track_pos(sv, speed=1.0):
    """Verbatim port of the engine SV math (client decompile 4624-4684):
    mapVelocityChanges + getPosFromTime/getPosFromTimeSV."""
    cum = [sv[0]["startTime"] * (speed * sv[0]["multiplier"])]
    for a, b in zip(sv, sv[1:]):
        cum.append(cum[-1] + (b["startTime"] - a["startTime"])
                   * (speed * a["multiplier"]))

    def pos(t):
        n = sum(1 for e in sv if e["startTime"] <= t)
        if n == 0:
            return t * speed
        return (cum[n - 1] + (t - sv[n - 1]["startTime"])
                * (speed * sv[n - 1]["multiplier"]))
    return pos


def test_sv_track_position_continuous(tmp):
    # Mimics SOUND ARCHITECT: base red at 3015, first inherited SV at 40833.
    src = tmp / "sa.osu"
    make_osu(
        src,
        timing=[
            "3015,363.636,4,2,0,100,1,0",
            "40833,-103.0928,4,2,0,100,0,0",
            "43656,-106.383,4,2,0,100,0,0",
        ],
        objects=["64,192,45000,1,0,0:0:0:0:"],
    )
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    sv = w["sliderVelocities"]
    assert sv[0] == {"startTime": 0, "multiplier": 1}
    pos = engine_track_pos(sv)
    worst = 0.0
    t = 0.0
    while t < 60000:
        worst = max(worst, abs(pos(t + 10) - pos(t)))
        t += 10
    # Smooth travel: no 10ms step may exceed speed*dt with margin (max mult ~1.0 here).
    assert worst <= 10 * 1.5, worst
    # The unanchored map must show the teleport (proves the test discriminates).
    pos_raw = engine_track_pos([e for e in sv if e["startTime"] > 0])
    worst_raw = 0.0
    t = 0.0
    while t < 60000:
        worst_raw = max(worst_raw, abs(pos_raw(t + 10) - pos_raw(t)))
        t += 10
    assert worst_raw > 1000, worst_raw
    print("PASS test_sv_track_position_continuous")


def test_fold_mixed_hold_tap_same_timestamp(tmp):
    # Regression: fold_columns crashed sorting (start, end, col) tuples when
    # a tap (end None) and a hold (end float) shared a timestamp
    # (Dragon Blade 6K / Blue Zenith 7K port, 2026-10-16).
    xs = [int((c + 0.5) * 512 / 7) for c in range(7)]
    objs = ([f"{x},192,1000,1,0,0:0:0:0:" for x in xs[:4]]
            + [f"{xs[4]},192,1000,128,0,2000:0:0:0:0:",
               f"{xs[5]},192,1000,1,0,0:0:0:0:",
               f"{xs[6]},192,2000,128,0,3000:0:0:0:0:"])
    src = tmp / "fh.osu"
    make_osu(src, keys=7, objects=objs, timing=["0,300,4,2,0,100,1,0"])
    w = osu_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    rows = w["song"]["notes"][0]["sectionNotes"]
    assert all(r[1] in (4, 5, 6, 7) for r in rows), rows
    assert any(r[2] > 0 for r in rows), rows  # the hold survived the fold
    print("PASS test_fold_mixed_hold_tap_same_timestamp")


def main():
    tests = [test_basic, test_fold_7k, test_fold_mixed_hold_tap_same_timestamp,
             test_idempotent_and_refusal,
             test_same_timestamp_red_lines_preserve_file_order,
             test_multi_bpm_ramp, test_sub_step_holds_clamped_to_one_step,
             test_invalid_inputs_refused_cleanly,
             test_sv_no_anchor_when_first_sv_at_zero,
             test_sv_track_position_continuous]
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
