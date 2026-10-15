#!/usr/bin/env python3
"""Offline tests for converters/skins2afn.py (no client needed)."""
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "converters"))
import skins2afn  # noqa: E402


def solid(w, h, rgb=(255, 0, 0), alpha=255):
    px = bytearray()
    for _y in range(h):
        for _x in range(w):
            px += bytes((rgb[0], rgb[1], rgb[2], alpha))
    return skins2afn.png_encode(w, h, bytes(px))


def make_skin(path, keys=4, ini_extra=None, files=None):
    """Write a minimal osu!mania skin folder. `files` maps filename ->
    (w, h, rgb); the base lane (2) art is always written."""
    if files is None:
        files = {}
    defaults = {
        "tap1.png": (12, 10, (255, 0, 0)),
        "key1.png": (14, 8, (0, 255, 0)),
        "key1d.png": (14, 8, (0, 200, 0)),
        "body1.png": (8, 20, (0, 0, 255)),
        "cap1.png": (8, 6, (255, 255, 0)),
        "mania-hit300.png": (30, 12, (255, 215, 0)),
        "mania-hit100.png": (28, 12, (0, 255, 0)),
        "mania-hit50.png": (26, 12, (0, 200, 255)),
        "score-0.png": (8, 12, (255, 255, 255)),
        "score-1.png": (8, 12, (240, 240, 240)),
        "score-dot.png": (4, 12, (255, 255, 255)),
    }
    defaults.update(files)
    for fname, (w, h, rgb) in defaults.items():
        (path / fname).parent.mkdir(parents=True, exist_ok=True)
        (path / fname).write_bytes(solid(w, h, rgb))
    mania_lines = [f"Keys: {keys}",
                   "NoteImage1: tap1", "KeyImage1: key1",
                   "KeyImage1D: key1d", "NoteImage1L: body1",
                   "NoteImage1T: cap1"]
    if ini_extra:
        mania_lines += ini_extra
    path.mkdir(parents=True, exist_ok=True)
    (path / "skin.ini").write_text("\n".join(
        ["[General]", "Name: TestSkin", "[Mania]"] + mania_lines),
        encoding="utf-8")


def read_pack(out):
    packs = [p for p in out.iterdir() if p.is_dir()]
    assert len(packs) == 1, packs
    pack = packs[0]
    manifest = json.loads((pack / "manifest.json").read_text())
    return pack, manifest


def test_basic(tmp):
    src = tmp / "skin"
    make_skin(src)
    # convert (helper returns pack dir)
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    pack = Path(out)
    m = json.loads((pack / "manifest.json").read_text())
    assert m["format"] == "afn-skin/1" and m["name"] == "TestSkin"
    assert set(m["dirs"]) == {"Left", "Down", "Up", "Right"}
    # all lanes share base art -> single PNG
    pngs = {v["png"] for v in m["dirs"].values()}
    assert pngs == {"sheet.png"}, pngs
    assert (pack / "sheet.png").is_file()
    # every direction gets its XML with color + generic + receptor frames
    for d, color in (("Left", "purple"), ("Down", "blue"),
                     ("Up", "green"), ("Right", "red")):
        xml = (pack / m["dirs"][d]["xml"]).read_text()
        for frame in (f"{color}0000", f"{color} hold piece0000",
                      f"{color} hold end0000", "note0000",
                      "note hold piece0000", "receptor0000",
                      "receptor confirm0000", "receptor press0000"):
            assert f'name="{frame}"' in xml, (d, frame)
    # hold body/cap recorded, pressed receptor distinct from resting
    assert m["dirs"]["Down"]["body"] == "sheet.png"
    assert m["dirs"]["Down"]["tailCap"] == "sheet.png"
    # receptor auto-scale: key art 14x8 vs head 12x10 -> x1.25 -> 18x10
    assert m["dirs"]["Down"]["receptorScale"] == 1.25
    # narrow body: true body band 8px wide -> 45% -> 4px
    assert m["bodyScale"] == 0.45
    import xml.dom.minidom as minidom
    doc = minidom.parseString((pack / "blue.xml").read_text())
    rects = {n.getAttribute("name"): (n.getAttribute("width"),
                                      n.getAttribute("height"))
             for n in doc.getElementsByTagName("SubTexture")}
    assert rects["receptor0000"] == ("18", "10"), rects["receptor0000"]
    assert rects["blue0000"] == ("12", "10")
    assert rects["blue hold piece0000"] == ("4", "20"), \
        rects["blue hold piece0000"]
    print("PASS test_basic")


def test_full_width_body(tmp):
    src = tmp / "skin"
    make_skin(src)
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"),
                                     body_scale=1.0)
    assert out is not None
    m = json.loads((Path(out) / "manifest.json").read_text())
    assert m["bodyScale"] == 1.0
    import xml.dom.minidom as minidom
    doc = minidom.parseString((Path(out) / "blue.xml").read_text())
    rects = {n.getAttribute("name"): n.getAttribute("width")
             for n in doc.getElementsByTagName("SubTexture")}
    assert rects["blue hold piece0000"] == "8", rects["blue hold piece0000"]
    print("PASS test_full_width_body")


def test_per_lane_split(tmp):
    src = tmp / "skin"
    make_skin(src,
              ini_extra=["NoteImage0: tap0", "NoteImage3: tap3",
                         "KeyImage0: key0", "KeyImage3: key3"],
              files={"tap0.png": (11, 9, (1, 2, 3)),
                     "tap3.png": (13, 12, (4, 5, 6)),
                     "key0.png": (14, 8, (7, 8, 9)),
                     "key3.png": (14, 8, (10, 11, 12))})
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    m = json.loads((Path(out) / "manifest.json").read_text())
    pngs = {v["png"] for v in m["dirs"].values()}
    # base + lane1 + lane4 sheets
    assert pngs == {"sheet.png", "sheet_left.png", "sheet_right.png"}, pngs
    assert m["dirs"]["Left"]["png"] == "sheet_left.png"
    assert m["dirs"]["Down"]["png"] == "sheet.png"
    assert m["dirs"]["Right"]["png"] == "sheet_right.png"
    print("PASS test_per_lane_split")


def test_fallbacks_no_body_cap_pressed(tmp):
    src = tmp / "skin"
    src.mkdir(parents=True)
    (src / "tap1.png").write_bytes(solid(12, 10, (255, 0, 0)))
    (src / "key1.png").write_bytes(solid(14, 8, (0, 255, 0)))
    (src / "skin.ini").write_text("\n".join(
        ["[General]", "Name: BareSkin", "[Mania]", "Keys: 4",
         "NoteImage1: tap1", "KeyImage1: key1"]), encoding="utf-8")
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    pack = Path(out)
    m = json.loads((pack / "manifest.json").read_text())
    assert m["dirs"]["Down"]["body"] == "sheet.png"  # tap reused as bar
    assert m["dirs"]["Down"]["tailCap"] is None
    assert m["judgements"] == {} and m["digits"] == {}
    down_xml = (pack / m["dirs"]["Down"]["xml"]).read_text()
    assert "hold end" not in down_xml  # no tail frames without a cap
    assert 'name="receptor confirm0000"' in down_xml  # pressed = resting
    import xml.dom.minidom as minidom
    doc = minidom.parseString(down_xml)
    rects = {n.getAttribute("name"): (n.getAttribute("width"),
                                      n.getAttribute("height"))
             for n in doc.getElementsByTagName("SubTexture")}
    # head-art body fallback keeps full width (no narrowing)
    assert rects["note hold piece0000"] == rects["note0000"]
    print("PASS test_fallbacks_no_body_cap_pressed")


def test_receptor_scale_off(tmp):
    src = tmp / "skin"
    make_skin(src)
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"),
                                     receptor_scale=False)
    assert out is not None
    m = json.loads((Path(out) / "manifest.json").read_text())
    assert m["dirs"]["Down"]["receptorScale"] == 1.0
    import xml.dom.minidom as minidom
    doc = minidom.parseString(
        (Path(out) / "blue.xml").read_text())
    rects = {n.getAttribute("name"): (n.getAttribute("width"),
                                      n.getAttribute("height"))
             for n in doc.getElementsByTagName("SubTexture")}
    assert rects["receptor0000"] == ("14", "8"), rects["receptor0000"]
    print("PASS test_receptor_scale_off")


def test_judge_digits(tmp):
    src = tmp / "skin"
    make_skin(src)
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    pack = Path(out)
    m = json.loads((pack / "manifest.json").read_text())
    assert m["judgements"] == {
        "300": "judge/hit300.png",
        "100": "judge/hit100.png",
        "50": "judge/hit50.png",
    }, m["judgements"]
    assert m["digits"] == {
        "0": "digits/score-0.png",
        "1": "digits/score-1.png",
        "dot": "digits/score-dot.png",
    }, m["digits"]
    for rel in list(m["judgements"].values()) + list(m["digits"].values()):
        w, h, _px = skins2afn.png_decode((pack / rel).read_bytes())
        assert (w, h) != (0, 0)
    print("PASS test_judge_digits")


def test_idempotent_and_refusal(tmp):
    src = tmp / "skin"
    make_skin(src)
    out = tmp / "out"
    w1 = skins2afn.convert_osu_skin(str(src), str(out))
    assert w1 is not None
    w2 = skins2afn.convert_osu_skin(str(src), str(out))  # identical rerun ok
    assert w2 is not None
    pack = next(p for p in out.iterdir() if p.is_dir())
    (pack / "manifest.json").write_text(json.dumps({"different": True}))
    assert skins2afn.convert_osu_skin(str(src), str(out)) is None
    assert json.loads((pack / "manifest.json").read_text()) == {
        "different": True}
    print("PASS test_idempotent_and_refusal")


def test_codec_roundtrip(tmp):
    # RGBA + gray + palette sources must survive decode/encode.
    rgba = bytes((10, 20, 30, 40)) * 6
    w, h, px = skins2afn.png_decode(skins2afn.png_encode(3, 2, rgba))
    assert (w, h, bytes(px)) == (3, 2, rgba)

    def chunk(ctype, payload):
        import struct
        import zlib
        c = ctype + payload
        return (struct.pack(">I", len(payload)) + c
                + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))

    import struct
    import zlib
    gray_raw = b"\x00" + bytes((0, 128, 255, 64))
    gray_png = (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 1, 8, 0, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(gray_raw))
                + chunk(b"IEND", b""))
    w, h, px = skins2afn.png_decode(gray_png)
    assert (w, h) == (4, 1) and px[0:4] == bytes((0, 0, 0, 255))
    assert px[4:8] == bytes((128, 128, 128, 255))
    assert px[12:16] == bytes((64, 64, 64, 255))

    pal = bytes((255, 0, 0, 0, 255, 0))  # idx0=red, idx1=green
    pal_raw = b"\x00" + bytes((0, 1, 0, 1))
    pal_png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 1, 8, 3, 0, 0, 0))
               + chunk(b"PLTE", pal)
               + chunk(b"IDAT", zlib.compress(pal_raw))
               + chunk(b"IEND", b""))
    w, h, px = skins2afn.png_decode(pal_png)
    assert (w, h) == (4, 1)
    assert px[0:4] == bytes((255, 0, 0, 255)) and px[4:8] == bytes(
        (0, 255, 0, 255))
    print("PASS test_codec_roundtrip")


def main():
    tests = [test_basic, test_per_lane_split,
             test_fallbacks_no_body_cap_pressed, test_receptor_scale_off,
             test_full_width_body, test_judge_digits,
             test_idempotent_and_refusal, test_codec_roundtrip]
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
