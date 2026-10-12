#!/usr/bin/env python3
"""Offline MODEL check for the corrected Afternight synthetic Test A fixture.

SCOPE: a Python restatement of code paths READ (read-only) from the live Project
Afternight client decompile. It does NOT run the game and proves nothing about
runtime acceptance. PASS = "fixture satisfies the contract we read" and "the model
reproduces the failures already seen live when fed the old flat container".
Sources (Client:NNNN = original-source line markers from the decompile):
  ChartFixing.fixChart tail   if chart.notes then chart = {song = chart}
  parseChart   (Client:5287)  song = wrapper.song; reads bpm/keys/keyCount/playerKeyCount/
                              players/events; builds Strumlines BEFORE addNotesFromChart
  Conductor.mapBPMChanges     reads wrapper.song.bpm; no song.notes -> warn + early return
  addNotesFromChart (5053)    for each song.notes[i]: for each .sectionNotes row
  createNote   (Client:4761)  lane -> strumline/column via section.mustHitSection
UNMODELLED: the other ChartFixing format fixers, SV/camera/event handling, Note.new,
t_36 defaults before parseChart. Run: python tests/test_synth_a_fixture.py (exit 0 = ok)
"""
import json
import sys
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "afn_synth_a_taps.chart.json"
# Assumed shape of the A2 payload: the container built by experiments/validate_synth.py.
OLD_FLAT = {
    "song": "Synth A taps", "bpm": 200.0, "playerKeyCount": 4, "opponentKeyCount": 4,
    "notes": [{"mustHitSection": True,
               "sectionNotes": [[1200.0, 4, 0.0], [1800.0, 5, 0.0], [2400.0, 6, 0.0], [3000.0, 7, 0.0]]}],
    "events": [],
}


class LuaError(Exception):
    pass


def index(v, key):
    if v is None:
        raise LuaError(f"attempt to index nil with '{key}'")
    return v.get(key) if isinstance(v, dict) else None  # string field reads as nil


def iterate(v, what):
    if v is None:
        raise LuaError(f"attempt to iterate over a nil value  <{what}>")
    if isinstance(v, list):
        return list(enumerate(v, 1))
    if isinstance(v, dict):
        return list(v.items())
    raise LuaError(f"attempt to iterate over a {type(v).__name__} value  <{what}>")


def num(v):
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return v
    try:
        return float(v) if isinstance(v, str) else None
    except ValueError:
        return None


def lua_or(*vals):
    return next((v for v in vals if v is not None), None)


def fixchart_tail(chart):
    return {"song": chart} if isinstance(chart, dict) and chart.get("notes") is not None else chart


def route(lane, must_hit, left, right):
    """createNote, chartPlayers == 2 branch -> (side, column)."""
    lane %= left + right
    flag = bool(must_hit)
    if lane >= (right if flag else left):
        flag = not flag
    side = "R" if flag else "L"
    if not must_hit:
        col = lane if lane < left else (lane - left) % right
    else:
        col = lane if lane < right else (lane - right) % left
    return side, int(col)


class Engine:
    def __init__(self):
        self.strumlines, self.notes, self.warnings = {}, [], []
        self.left = self.right = 4  # ASSUMED pre-existing config (unproven; Test 1 only)

    def map_bpm(self, wrapper):
        song = index(wrapper, "song")
        bpm = index(song, "bpm")
        if index(wrapper, "bpmChanges") is None:
            if index(song, "notes") is None:
                self.warnings.append("There's something wrong with the chart? idk")
                return
            if bpm is None:
                raise LuaError("attempt to perform arithmetic on nil  <60 / CurBPM>")

    def parse_chart(self, wrapper):
        song = index(wrapper, "song")               # u12 = v764.song
        self.bpm = lua_or(index(song, "bpm"), 100)  # Conductor.init(u12.bpm or 100)
        self.map_bpm(wrapper)
        self.left = int(lua_or(num(index(song, "keys")), num(index(song, "keyCount")), 4))
        self.right = int(lua_or(num(index(song, "playerKeyCount")), self.left))
        players = int(lua_or(num(index(song, "players")), 2))
        assert players == 2, "model only covers chartPlayers == 2"
        for i in range(players):
            side = "R" if (i + 1) % 2 == 0 else "L"
            kc = self.right if side == "R" else self.left
            self.strumlines[i] = {"side": side, "strums": kc}
        self.add_notes(song)                        # Strumlines already exist here

    def add_notes(self, song):
        for _, section in iterate(index(song, "notes"), "arg263.notes"):
            if section is None:
                continue
            for _, row in iterate(index(section, "sectionNotes"), "section.sectionNotes"):
                t = num(row[0]) if isinstance(row, list) and row else None
                if t is None:
                    continue  # non-array rows vanish silently
                lane = num(row[1]) if len(row) > 1 else None
                if lane is None:
                    raise LuaError("attempt to compare nil with number  <row[2] < 0>")
                if lane < 0:
                    continue  # event row
                side, col = route(int(lane), index(section, "mustHitSection"), self.left, self.right)
                sl = self.strumlines.get(0 if side == "L" else 1)
                if sl is None:
                    raise LuaError("attempt to index nil with 'KeyCount'  <strumline missing>")
                if col >= sl["strums"]:
                    raise LuaError("attempt to index nil  <Strums[col]>")
                self.notes.append({"time": t, "side": side, "col": col})


def load_fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def raises(fn, needle):
    try:
        fn()
    except LuaError as e:
        assert needle in str(e), f"wrong error: {e}"
        return str(e)
    raise AssertionError("expected a LuaError, none raised")


def test_fixture_shape():
    fx = load_fixture()
    assert set(fx) == {"song"}, "top level must be {song = {...}}"
    s = fx["song"]
    assert isinstance(s["bpm"], (int, float)) and s["bpm"] > 0
    assert "opponentKeyCount" not in s, "parseChart never reads opponentKeyCount"
    assert isinstance(s["notes"], list) and s["notes"]
    seen = set()
    for sec in s["notes"]:
        assert isinstance(sec["mustHitSection"], bool)
        for row in sec["sectionNotes"]:
            assert isinstance(row, list) and len(row) >= 3, "rows must be arrays [ms, lane, sustainMs]"
            assert row[0] >= 0 and 4 <= row[1] <= 7 and row[2] == 0
            assert (row[0], row[1]) not in seen
            seen.add((row[0], row[1]))
    assert [r[0] for sec in s["notes"] for r in sec["sectionNotes"]] == [1200, 1800, 2400, 3000]


def test_model_accepts_fixture():
    e = Engine()
    e.parse_chart(fixchart_tail(load_fixture()))
    assert len(e.strumlines) == 2 and all(s["strums"] == 4 for s in e.strumlines.values())
    assert [(n["side"], n["col"], n["time"]) for n in e.notes] == [
        ("R", 0, 1200), ("R", 1, 1800), ("R", 2, 2400), ("R", 3, 3000)]
    assert not e.warnings


def test_flat_container_ok_only_via_fixchart():
    e = Engine()
    e.parse_chart(fixchart_tail(OLD_FLAT))  # normal path wraps it as {song = flat}
    assert len(e.notes) == 4


def test_reproduces_A2():
    e = Engine()
    msg = raises(lambda: e.parse_chart(OLD_FLAT), "iterate over a nil value")
    assert "arg263.notes" in msg
    assert len(e.strumlines) == 2 and sum(s["strums"] for s in e.strumlines.values()) == 8
    assert e.notes == [] and e.warnings == ["There's something wrong with the chart? idk"]


def test_reproduces_test1():
    raises(lambda: Engine().add_notes(OLD_FLAT), "'KeyCount'")


def test_alternative_candidate_same_message():
    flat_rows = {"song": {"bpm": 200, "notes": [[1200, 4, 0]]}}
    msg = raises(lambda: Engine().parse_chart(flat_rows), "iterate over a nil value")
    assert "sectionNotes" in msg  # same Luau message, different iterator: only the line number tells them apart


def test_side_rule():
    assert route(4, False, 4, 4) == ("R", 0) and route(7, False, 4, 4) == ("R", 3)
    assert route(0, True, 4, 4) == ("R", 0)
    assert route(4, True, 4, 4) == ("L", 0), "old preview (mustHitSection=true, lanes 4-7) hits the L strumline"


def main():
    tests = [(k, v) for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print("PASS", name)
        except (AssertionError, LuaError, KeyError) as e:
            failed += 1
            print("FAIL", name, "-", repr(e))
    print(f"{len(tests) - failed}/{len(tests)} passed (model-level only; NOT engine evidence)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
