#!/usr/bin/env python3
"""Offline tests for converters/quaver_to_afn.py (no client needed)."""
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "converters"))
import quaver_to_afn  # noqa: E402


def make_qua(path, mode="Keys4", tps=None, svs=None, objects=None,
             title="QuaTest", diff="Insane", audio="song.ogg"):
    if tps is None:
        tps = ["- StartTime: 0", "  Bpm: 150"]
    if svs is None:
        svs = ["- StartTime: 2000", "  Multiplier: 0.5"]
    if objects is None:
        objects = [
            "- StartTime: 1200", "  Lane: 1",
            "- StartTime: 1800", "  Lane: 2",
            "- StartTime: 2400", "  Lane: 3",
            "- StartTime: 3000", "  Lane: 4", "  EndTime: 3600",
        ]
    lines = [f"Mode: {mode}", f"Title: {title}", f"Artist: Test",
             f"DifficultyName: {diff}", f"AudioFile: {audio}",
             "TimingPoints:"]
    lines += ["  " + l if not l.startswith("-") else l for l in tps]
    lines += ["SliderVelocities:"]
    lines += ["  " + l if not l.startswith("-") else l for l in svs]
    lines += ["HitObjects:"]
    lines += ["  " + l if not l.startswith("-") else l for l in objects]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_basic(tmp):
    src = tmp / "t.qua"
    make_qua(src)
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    s = w["song"]
    assert set(w) == {"song", "bpmChanges", "sliderVelocities"}
    assert s["bpm"] == 150.0 and s["keyCount"] == 4
    assert s["notes"][0]["sectionNotes"] == [
        [1200, 4, 0], [1800, 5, 0], [2400, 6, 0], [3000, 7, 600]]
    assert w["bpmChanges"] == []
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},
        {"startTime": 2000, "multiplier": 0.5}]
    assert s["audioFile"] == "song.ogg"
    print("PASS test_basic")


def test_multi_bpm_and_last_wins_sv(tmp):
    src = tmp / "ramp.qua"
    make_qua(src,
             tps=["- StartTime: 0", "  Bpm: 165",
                  "- StartTime: 40833", "  Bpm: 170",
                  "- StartTime: 40833", "  Bpm: 175"],
             svs=["- StartTime: 40833", "  Multiplier: 0.97",
                  "- StartTime: 40833", "  Multiplier: 0.94"])
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["song"]["bpm"] == 165.0
    # same-time reds keep file order (no accumulation in the engine)
    assert w["bpmChanges"] == [
        {"startTime": 40833, "bpm": 170.0},
        {"startTime": 40833, "bpm": 175.0}]
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},
        {"startTime": 40833, "multiplier": 0.94}]
    print("PASS test_multi_bpm_and_last_wins_sv")


def test_missing_multiplier_is_stop(tmp):
    # A missing Multiplier means Quaver rate 0 (full stop), kept verbatim.
    src = tmp / "stop.qua"
    make_qua(src, svs=["- StartTime: 1000"])
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},
        {"startTime": 1000, "multiplier": 0.0}]
    print("PASS test_missing_multiplier_is_stop")


def test_degenerate_hold_is_tap(tmp):
    src = tmp / "tap.qua"
    make_qua(src, objects=["- StartTime: 1200", "  Lane: 1",
                           "  EndTime: 1200"])
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    assert w["song"]["notes"][0]["sectionNotes"] == [[1200, 4, 0]]
    print("PASS test_degenerate_hold_is_tap")


def test_fold_7k(tmp):
    xs = [f"- StartTime: 1000\n  Lane: {c}" for c in range(1, 8)]
    src = tmp / "f.qua"
    make_qua(src, mode="Keys7",
             objects=[l for o in xs for l in o.splitlines()])
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    rows = w["song"]["notes"][0]["sectionNotes"]
    lanes = sorted(r[1] for r in rows)
    assert len(rows) == 4 and len(set(lanes)) == 4, lanes
    print("PASS test_fold_7k")


def test_idempotent_and_refusal(tmp):
    src = tmp / "t.qua"
    make_qua(src)
    out = tmp / "out"
    w1 = quaver_to_afn.convert_file(src, out)
    assert w1 is not None
    assert quaver_to_afn.convert_file(src, out) is not None
    dest = next(out.glob("*.chart.json"))
    dest.write_text(json.dumps({"different": True}))
    assert quaver_to_afn.convert_file(src, out) is None
    assert json.loads(dest.read_text()) == {"different": True}
    print("PASS test_idempotent_and_refusal")


def test_invalid_inputs_refused_cleanly(tmp):
    bad = tmp / "bad.qua"
    bad.write_text("Mode: Keys4\nTitle: x\n", encoding="utf-8")
    assert quaver_to_afn.convert_file(bad, tmp / "out1") is None
    drums = tmp / "drums.qua"
    make_qua(drums, mode="Drums")
    assert quaver_to_afn.convert_file(drums, tmp / "out2") is None
    print("PASS test_invalid_inputs_refused_cleanly")


def test_sub_ms_sv_times_kept_verbatim(tmp):
    # Teleport blips are ~0.016ms wide at x4.4M; rounding to 3 decimals
    # corrupts net-zero away/back pairs (ballin'/bozo, 2026-10-16).
    src = tmp / "blip.qua"
    make_qua(src, svs=["- StartTime: 9600.015625", "  Multiplier: 4442921.5",
                       "- StartTime: 9600.140625", "  Multiplier: -4442921.5",
                       "- StartTime: 9700", "  Multiplier: 1.0"])
    w = quaver_to_afn.convert_file(src, tmp / "out")
    assert w is not None
    times = [e["startTime"] for e in w["sliderVelocities"]]
    assert times == [0, 9600.015625, 9600.140625, 9700], times
    mults = [e["multiplier"] for e in w["sliderVelocities"]]
    assert mults == [1, 4442921.5, -4442921.5, 1.0], mults
    print("PASS test_sub_ms_sv_times_kept_verbatim")


def test_sv_cap_tames_teleports_only(tmp):
    # --sv-cap clamps |M|>cap, leaves sane SVs (and the t0 anchor) alone.
    src = tmp / "tame.qua"
    make_qua(src, svs=["- StartTime: 1000", "  Multiplier: 4442921.5",
                       "- StartTime: 2000", "  Multiplier: -0.5",
                       "- StartTime: 3000", "  Multiplier: 1.5"])
    w = quaver_to_afn.convert_file(src, tmp / "out", sv_cap=3.0)
    assert w is not None
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1},
        {"startTime": 1000, "multiplier": 3.0},
        {"startTime": 2000, "multiplier": -0.5},
        {"startTime": 3000, "multiplier": 1.5}]
    w2 = quaver_to_afn.convert_file(src, tmp / "out2")
    assert w2["sliderVelocities"][1] == {"startTime": 1000,
                                        "multiplier": 4442921.5}
    print("PASS test_sv_cap_tames_teleports_only")


def main():
    tests = [test_basic, test_multi_bpm_and_last_wins_sv,
             test_missing_multiplier_is_stop, test_degenerate_hold_is_tap,
             test_fold_7k, test_idempotent_and_refusal,
             test_invalid_inputs_refused_cleanly,
             test_sub_ms_sv_times_kept_verbatim,
             test_sv_cap_tames_teleports_only]
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
