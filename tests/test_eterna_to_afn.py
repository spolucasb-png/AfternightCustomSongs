#!/usr/bin/env python3
"""Offline tests for converters/eterna_to_afn.py (no client needed)."""
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "converters"))
import eterna_to_afn  # noqa: E402


def make_sm(path, bpms="0.000=120.000", notes=None, title="SMTest",
            music="song.ogg", extra=""):
    # notes: row strings; "," items are measure separators.
    if notes is None:
        notes = ["1000", "0100", "0010", "0001"]
    body = "\n".join(r if r != "," else "," for r in notes)
    path.write_text("\n".join([
        "#TITLE:" + title + ";", "#ARTIST:Test;", "#MUSIC:" + music + ";",
        "#BPMS:" + bpms + ";",
        extra,
        "#NOTES:dance-single::Challenge:10:0.9,0.8,0.7,0.6,0.5:",
        body + ";",
    ]), encoding="utf-8")


def test_basic(tmp):
    src = tmp / "t.sm"
    make_sm(src)
    w = eterna_to_afn.convert_file(src, tmp / "out")
    assert w is not None and len(w) == 1
    w = w[0]
    s = w["song"]
    assert set(w) == {"song", "bpmChanges", "sliderVelocities"}
    assert s["bpm"] == 120.0 and s["keyCount"] == 4
    # one measure, 4 rows: beats 0..3 at 120 BPM = 0/500/1000/1500ms
    assert s["notes"][0]["sectionNotes"] == [
        [0, 4, 0], [500, 5, 0], [1000, 6, 0], [1500, 7, 0]], \
        s["notes"][0]["sectionNotes"]
    assert w["bpmChanges"] == [] and w["sliderVelocities"] == []
    assert s["audioFile"] == "song.ogg"
    print("PASS test_basic")


def test_hold_mine_roll_lift(tmp):
    src = tmp / "h.sm"
    make_sm(src, notes=[
        "2000",   # hold head col 1 (beat 0)
        "0000",
        "3000",   # tail (beat 2)
        "010M",   # tap col 2 + mine col 4 (beat 3)
        ",",
        "0004",   # roll head col 4 (beat 4)
        "0000",
        "0003",   # tail (beat 6)
        "L000",   # lift -> tap (beat 7)
    ])
    w = eterna_to_afn.convert_file(src, tmp / "out")[0]
    rows = w["song"]["notes"][0]["sectionNotes"]
    # beat .5s grid at 120: head@0 sus 1000; tap@1500; roll@2000 sus 1000;
    # lift@3500 tap. Mine skipped.
    assert rows == [
        [0, 4, 1000.0], [1500, 5, 0], [2000, 7, 1000.0], [3500, 4, 0]], rows
    print("PASS test_hold_mine_roll_lift")


def test_multi_bpm_and_scrolls(tmp):
    src = tmp / "ramp.sm"
    make_sm(src, bpms="0.000=120.000,8.000=150.000",
            extra="#SCROLLS:0.000=1.000,8.000=0.500;",
            notes=["1000"])
    w = eterna_to_afn.convert_file(src, tmp / "out")[0]
    assert w["song"]["bpm"] == 120.0
    # beat 8 at 120 BPM = 4000ms
    assert w["bpmChanges"] == [{"startTime": 4000.0, "bpm": 150.0}]
    assert w["sliderVelocities"] == [
        {"startTime": 0, "multiplier": 1.0},
        {"startTime": 4000.0, "multiplier": 0.5}]
    print("PASS test_multi_bpm_and_scrolls")


def test_stop_warp_math(tmp):
    # 120 BPM: beat 4 = 2000ms. Stop 1s at beat 4 -> beat 8 lands at 5000ms.
    # Warp beats 8-12: beat 16 lands at 8000-2000 = 6000ms... plus the stop.
    src = tmp / "sw.sm"
    make_sm(src, bpms="0.000=120.000",
            extra="#STOPS:4.000=1.000;\n#WARPS:8.000=4.000;",
            notes=["1000"])
    w = eterna_to_afn.convert_file(src, tmp / "out")[0]
    ms, _warp = eterna_to_afn.make_clock([(0.0, 120.0)], [(4.0, 1.0)], [],
                                         [(8.0, 4.0)])
    assert ms(4.0) == 2000.0, ms(4.0)
    assert ms(8.0) == 5000.0, ms(8.0)   # 4000 + 1000 stop
    assert ms(16.0) == 7000.0, ms(16.0)  # 8000 + 1000 stop - 2000 warp
    assert _warp(10.0) is True and _warp(4.0) is False
    print("PASS test_stop_warp_math")


def test_warp_notes_dropped(tmp):
    src = tmp / "w.sm"
    make_sm(src, bpms="0.000=120.000",
            extra="#WARPS:0.000=4.000;",
            notes=["1000", "0100"])  # beats 0,1: inside warp
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        w = eterna_to_afn.convert_file(src, tmp / "out")
    assert w == []  # all notes dropped -> no chart, loud skip
    assert "warp" in buf.getvalue()
    print("PASS test_warp_notes_dropped")


def test_idempotent_and_refusal(tmp):
    src = tmp / "t.sm"
    make_sm(src)
    out = tmp / "out"
    w1 = eterna_to_afn.convert_file(src, out)
    assert w1 is not None
    assert eterna_to_afn.convert_file(src, out) is not None
    dest = next(out.glob("*.chart.json"))
    dest.write_text(json.dumps({"different": True}))
    assert eterna_to_afn.convert_file(src, out) is None
    assert json.loads(dest.read_text()) == {"different": True}
    print("PASS test_idempotent_and_refusal")


def test_invalid_inputs_refused_cleanly(tmp):
    bad = tmp / "bad.sm"
    bad.write_text("#TITLE:x;\n", encoding="utf-8")
    assert eterna_to_afn.convert_file(bad, tmp / "out1") is None
    pump = tmp / "pump.sm"
    make_sm(pump)
    pump.write_text(pump.read_text(encoding="utf-8").replace(
        "dance-single", "pump-single"), encoding="utf-8")
    assert eterna_to_afn.convert_file(pump, tmp / "out2") is None
    print("PASS test_invalid_inputs_refused_cleanly")


def main():
    tests = [test_basic, test_hold_mine_roll_lift, test_multi_bpm_and_scrolls,
             test_stop_warp_math, test_warp_notes_dropped,
             test_idempotent_and_refusal, test_invalid_inputs_refused_cleanly]
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
