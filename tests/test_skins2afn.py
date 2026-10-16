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


def test_judge_ini_refs(tmp):
    # skin.ini Hit* refs (Judgements/ subfolder) beat mania-hit* files.
    src = tmp / "skin"
    make_skin(
        src,
        ini_extra=["Hit300: Judgements/best300", "Hit0: Judgements/worst0"],
        files={"Judgements/best300.png": (20, 12, (255, 0, 0)),
               "Judgements/worst0.png": (18, 11, (0, 0, 0)),
               "mania-hit300.png": (20, 12, (0, 0, 255)),
               "mania-hit0.png": (18, 11, (0, 255, 0))},
    )
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    pack = Path(out)
    w, h, px = skins2afn.png_decode(
        (pack / "judge" / "hit300.png").read_bytes())
    assert (w, h) == (20, 12) and bytes(px[0:3]) == bytes((255, 0, 0))
    w, h, px = skins2afn.png_decode(
        (pack / "judge" / "hit0.png").read_bytes())
    assert (w, h) == (18, 11) and bytes(px[0:3]) == bytes((0, 0, 0))
    print("PASS test_judge_ini_refs")


def test_uniform_digit_cell(tmp):
    src = tmp / "skin"
    make_skin(src, files={
        "score-0.png": (10, 12, (255, 255, 255)),   # wide
        "score-1.png": (6, 10, (240, 240, 240)),    # narrow + short
        "score-dot.png": (4, 12, (200, 200, 200)),  # punctuation: native
    })
    out = skins2afn.convert_osu_skin(str(src), str(tmp / "out"))
    assert out is not None
    pack = Path(out)
    w0, h0, px0 = skins2afn.png_decode(
        (pack / "digits" / "score-0.png").read_bytes())
    w1, h1, px1 = skins2afn.png_decode(
        (pack / "digits" / "score-1.png").read_bytes())
    assert (w0, h0) == (10, 12) and (w1, h1) == (10, 12)
    # narrow art centered: art pixel lands at ((10-6)//2, (12-10)//2)
    assert bytes(px1[(1 * 10 + 2) * 4:(1 * 10 + 2) * 4 + 3]) == bytes(
        (240, 240, 240))
    assert bytes(px1[0:4]) == bytes((0, 0, 0, 0))  # padding transparent
    wd, hd, _pxd = skins2afn.png_decode(
        (pack / "digits" / "score-dot.png").read_bytes())
    assert (wd, hd) == (4, 12)
    print("PASS test_uniform_digit_cell")


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


# ------------------------------------------------- multi-game (Quaver/Etterna)

def rgba_png(w, h, fn):
    """PNG whose pixel (x, y) is fn(x, y) -> (r, g, b, a)."""
    px = bytearray()
    for y in range(h):
        for x in range(w):
            px += bytes(fn(x, y))
    return skins2afn.png_encode(w, h, bytes(px))


def frame_rect(pack, color, frame):
    import re
    xml = (pack / f"{color}.xml").read_text(encoding="utf-8")
    m = re.search(r'name="%s0000" x="(\d+)" y="(\d+)" width="(\d+)" '
                  r'height="(\d+)"' % re.escape(frame), xml)
    assert m, f"{color}.xml lacks frame {frame!r}"
    return tuple(int(g) for g in m.groups())


def sheet_px(pack, manifest, dirname, x, y):
    w, _h, px = skins2afn.png_decode(
        (pack / manifest["dirs"][dirname]["png"]).read_bytes())
    i = (y * w + x) * 4
    return tuple(px[i:i + 4])


def test_blank_judgement_kept(tmp):
    """A fully transparent judgement is the author hiding it: kept as a
    1x1 blank (engine art must NOT reappear), not dropped as missing."""
    skin = tmp / "skin"
    make_skin(skin)
    (skin / "mania-hit300g.png").write_bytes(solid(20, 10, alpha=0))
    out = tmp / "out"
    assert skins2afn.convert_osu_skin(str(skin), str(out)) is not None
    pack, manifest = read_pack(out)
    assert manifest["judgements"]["300g"] == "judge/hit300g.png"
    w, h, px = skins2afn.png_decode((pack / "judge/hit300g.png").read_bytes())
    assert (w, h) == (1, 1) and px[3] == 0, (w, h, px)
    print("PASS test_blank_judgement_kept")


def make_quaver(path):
    hit = path / "4k" / "HitObjects"
    rec = path / "4k" / "Receptors"
    for d in (hit, rec, path / "Judgements", path / "Numbers"):
        d.mkdir(parents=True, exist_ok=True)
    (path / "skin.ini").write_text(
        "[General]\nName = Q Test\nAuthor = t\n\n[4K]\nColumnSize = 100\n",
        encoding="utf-8")
    for n in range(1, 5):
        rgb = (255, 0, 0) if n == 1 else (0, 255, 0)
        (hit / f"note-hitobject-{n}.png").write_bytes(solid(20, 20, rgb))
        (hit / f"note-holdbody-{n}.png").write_bytes(solid(20, 10, (0, 0, 255)))
        # end cap: top half white, bottom half black (orientation marker)
        (hit / f"note-holdend-{n}.png").write_bytes(rgba_png(
            20, 10, lambda x, y: (255, 255, 255, 255) if y < 5
            else (0, 0, 0, 255)))
        (rec / f"receptor-up-{n}.png").write_bytes(solid(16, 16, (90, 90, 90)))
        (rec / f"receptor-down-{n}.png").write_bytes(
            solid(16, 16, (200, 200, 200)))
    for g in ("perf", "great", "good", "okay", "miss"):
        (path / "Judgements" / f"judge-{g}.png").write_bytes(
            solid(30, 12, (255, 200, 0)))
    (path / "Judgements" / "judge-marv.png").write_bytes(solid(30, 12, alpha=0))
    for d in "01":
        (path / "Numbers" / f"combo-{d}.png").write_bytes(
            solid(10, 14, (255, 255, 255)))
        (path / "Numbers" / f"score-{d}.png").write_bytes(
            solid(6, 8, (128, 128, 128)))
    (path / "Numbers" / "score-decimal.png").write_bytes(solid(4, 14))


def test_quaver_basic(tmp):
    skin = tmp / "qskin"
    make_quaver(skin)
    assert skins2afn.detect_game(str(skin)) == "quaver"
    out = tmp / "out"
    assert skins2afn.convert_quaver_skin(str(skin), str(out)) is not None
    pack, m = read_pack(out)
    assert m["name"] == "Q Test" and m["source"]["game"] == "quaver"
    # lane 1 has its own art -> its own sheet; lanes 2-4 share sheet.png
    assert m["dirs"]["Left"]["png"] == "sheet_left.png"
    assert m["dirs"]["Down"]["png"] == "sheet.png"
    # receptors scaled to note height (16 -> 20)
    assert m["dirs"]["Down"]["receptorScale"] == 1.25
    # end cap flipped: Quaver authors it top-anchored, FNF is bottom-anchored
    x, y, w, h = frame_rect(pack, "blue", "blue hold end")
    assert sheet_px(pack, m, "Down", x, y)[:3] == (0, 0, 0)
    assert sheet_px(pack, m, "Down", x, y + h - 1)[:3] == (255, 255, 255)
    # grades by mania equivalence; blank Marv kept as a hidden 1x1
    assert set(m["judgements"]) == {"300g", "300", "200", "100", "50", "0"}
    jw, jh, _ = skins2afn.png_decode((pack / "judge/hit300g.png").read_bytes())
    assert (jw, jh) == (1, 1)
    # combo-N preferred over score-N (FNF_Combo is the combo counter)
    dw, dh, _ = skins2afn.png_decode((pack / "digits/score-0.png").read_bytes())
    assert (dw, dh) == (10, 14), (dw, dh)
    assert "dot" in m["digits"] and "comma" not in m["digits"]
    print("PASS test_quaver_basic")


def test_etterna_redirect_rotation(tmp):
    """Classic SM noteskin: only Down art, other buttons redirect to Down
    and rotate (clockwise) like NoteSkin Load(); holds never rotate."""
    skin = tmp / "ettskin"
    for d in ("Notes", "Receptors", "Holds"):
        (skin / d).mkdir(parents=True, exist_ok=True)
    (skin / "Noteskin.lua").write_text(
        'local N = {}\nN.ButtonRedir = {\n\tUp = "Down",\n\tDown = "Down",'
        '\n\tLeft = "Down",\n\tRight = "Down",\n}\n'
        'N.Rotate = {\n\tUp = 180,\n\tDown = 0,\n\tLeft = 90,\n\tRight = -90,'
        '\n}\nreturn N\n', encoding="utf-8")
    # 16x16 opaque, red marker in the top-left 4x4, green elsewhere
    marker = rgba_png(16, 16, lambda x, y: (255, 0, 0, 255)
                      if x < 4 and y < 4 else (0, 255, 0, 255))
    (skin / "Notes" / "_Down Tap Note 1x1 (res 16x16).png").write_bytes(marker)
    (skin / "Receptors" / "_Down Go Receptor 1x1.png").write_bytes(marker)
    (skin / "Holds" / "Down Hold Body Active (doubleres).png").write_bytes(
        solid(32, 64, (0, 0, 255)))
    (skin / "Holds" / "Down Hold BottomCap Active (doubleres).png").write_bytes(
        solid(32, 16, (255, 255, 0)))
    assert skins2afn.detect_game(str(skin)) == "etterna"
    out = tmp / "out"
    # full-width so the doubleres halving is measured on its own (the FNF
    # body-band squeeze is a separate pass, covered by the osu! tests)
    assert skins2afn.convert_etterna_skin(str(skin), str(out),
                                          body_scale=1.0) is not None
    pack, m = read_pack(out)
    assert m["source"]["game"] == "etterna"
    assert m["source"]["redirected"] == ["Left", "Right", "Up"]

    def marker_corner(dirname, color):
        x, y, w, h = frame_rect(pack, color, color)
        corners = {"tl": (x, y), "tr": (x + w - 1, y),
                   "bl": (x, y + h - 1), "br": (x + w - 1, y + h - 1)}
        reds = [k for k, (cx, cy) in corners.items()
                if sheet_px(pack, m, dirname, cx, cy)[:3] == (255, 0, 0)]
        assert len(reds) == 1, (dirname, reds)
        return reds[0]

    assert marker_corner("Down", "blue") == "tl"      # 0
    assert marker_corner("Left", "purple") == "tr"    # 90 cw
    assert marker_corner("Up", "green") == "br"       # 180
    assert marker_corner("Right", "red") == "bl"      # -90
    # doubleres halves hold art to note scale; bodies are not rotated
    assert frame_rect(pack, "purple", "purple hold piece")[2:] == (16, 32)
    assert frame_rect(pack, "purple", "purple hold end")[2:] == (16, 8)
    # no judgement/combo art in SM noteskins
    assert m["judgements"] == {} and m["digits"] == {}
    print("PASS test_etterna_redirect_rotation")


def test_etterna_own_art_frames(tmp):
    """Ambie-style: per-direction tap/receptor art used as-is (no rotation
    even with a redirect table), first cell of an NxM sheet, hold head =
    the lane's OWN tap, pressed receptor missing -> lane's own receptor."""
    skin = tmp / "amb"
    for d in ("Notes", "Receptors", "Holds"):
        (skin / d).mkdir(parents=True, exist_ok=True)
    (skin / "Noteskin.lua").write_text(
        'X.ButtonRedir = { Up = "Up", Down = "Up", Left = "Up", Right = "Up" }\n'
        'X.Rotate = { Up = 0, Down = 0, Left = 0, Right = 0 }\n',
        encoding="utf-8")
    colors = {"Left": (255, 0, 0), "Down": (0, 255, 0),
              "Up": (0, 0, 255), "Right": (255, 255, 0)}
    for d, rgb in colors.items():
        # 2x1 frame sheet: first cell = lane colour, second cell = magenta
        (skin / "Notes" / f"_{d} Tap Note 2x1.png").write_bytes(rgba_png(
            24, 12, lambda x, y, c=rgb: (*c, 255) if x < 12
            else (255, 0, 255, 255)))
        (skin / "Receptors" / f"_{d} Go Receptor 1x1.png").write_bytes(
            solid(12, 12, (60, 60, 60)))
    (skin / "Holds" / "Up Hold Body Active.png").write_bytes(
        solid(12, 30, (10, 10, 10)))
    out = tmp / "out"
    assert skins2afn.convert_etterna_skin(str(skin), str(out)) is not None
    pack, m = read_pack(out)
    for d, color in skins2afn.DIRS:
        x, y, w, h = frame_rect(pack, color, color)
        assert (w, h) == (12, 12), (d, w, h)          # first cell only
        assert sheet_px(pack, m, d, x + 6, y + 6)[:3] == colors[d]
        hx, hy, _hw, _hh = frame_rect(pack, color, f"{color} hold")
        assert sheet_px(pack, m, d, hx + 6, hy + 6)[:3] == colors[d], d
        px_, py_, _pw, _ph = frame_rect(pack, color, "receptor press")
        assert sheet_px(pack, m, d, px_ + 6, py_ + 6)[:3] == (60, 60, 60)
    assert m["source"]["redirected"] == ["Down", "Left", "Right"]
    print("PASS test_etterna_own_art_frames")


def test_detect_game(tmp):
    osu = tmp / "osu"
    make_skin(osu)
    assert skins2afn.detect_game(str(osu)) == "osu"
    # an osu! skin with a 4K/ art folder is still osu! ([Mania] present)
    (osu / "4K" / "HitObjects").mkdir(parents=True)
    assert skins2afn.detect_game(str(osu)) == "osu"
    empty = tmp / "empty"
    empty.mkdir()
    assert skins2afn.detect_game(str(empty)) is None
    print("PASS test_detect_game")


def main():
    tests = [test_basic, test_per_lane_split,
             test_fallbacks_no_body_cap_pressed, test_receptor_scale_off,
             test_full_width_body, test_judge_digits, test_judge_ini_refs,
             test_uniform_digit_cell,
             test_idempotent_and_refusal, test_codec_roundtrip,
             test_blank_judgement_kept, test_detect_game, test_quaver_basic,
             test_etterna_redirect_rotation, test_etterna_own_art_frames]
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
