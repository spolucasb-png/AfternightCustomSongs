#!/usr/bin/env python3
"""osu!mania skin -> AfternightCustomSongs skin pack converter (skins2afn).

Reads an osu! skin folder (skin.ini [Mania] Keys:N section, NoteImage*/
KeyImage* references with stable-name fallback) and produces an
AfternightCustomSongs/Skins/<slug>/ pack: one PNG atlas + one Sparrow
XML per 4K direction, plus a manifest.json.

Engine contract (Phase 0 recon, all source-read + live-verified):
  * A noteskin set = per-direction ModuleScripts whose Source is
    `return "<Sparrow XML>"` (require() returns the XML string) with an
    `Image` attribute = the spritesheet. The player (Phase 2) builds those
    instances from this pack's files at Play time.
  * Per-direction frame names the engine looks up (client decompile
    cacheNoteType/cacheNoteSet + live ManiaData.dirXmlColor):
      notes:      {color}0            (Left=purple, Down=blue, Up=green,
                                       Right=red) + generic note0
      hold body:  {color} hold piece0 + generic note hold piece0
      hold head:  {color} hold0       + generic note hold0
      hold tail:  {color} hold end0   + generic note hold end0
      receptor:   receptor0 / receptor confirm0 / receptor press0
  * Sparrow XML: SubTexture name/x/y/width/height; animation names are the
    SubTexture name minus its last 4 chars, so single-frame sprites are
    emitted as `<name>0000`.
  * No aspect framing: the engine uses exact XML rects (unlike Gakuran's
    Fit rendering), so sprites keep native pixels, alpha-cropped.
  * Engine stretches the hold body piece itself; tail metrics are unknown
    until the Phase 3 visual check (manifest records sizes).

Pure stdlib (no Pillow): PNG decode/encode for 8-bit RGB/RGBA/gray/
gray-alpha/palette, non-interlaced.

Usage:
    python converters/skins2afn.py "C:/path/to/osu skin"
        --out AfternightCustomSongs/Skins [--keys 4] [--lane 2] [--name X]
"""

import argparse
import json
import os
import re
import struct
import sys
import zlib
import xml.sax.saxutils as saxutils

# 4K direction -> engine XML color (live ManiaData.dirXmlColor).
DIRS = (("Left", "purple"), ("Down", "blue"),
        ("Up", "green"), ("Right", "red"))

# Atlas padding between stacked sprites (px, transparent).
PAD = 2


# ---------------------------------------------------------------- PNG codec

def png_decode(data: bytes):
    """Return (width, height, rgba_bytes). 8-bit RGB/RGBA/gray/gray-alpha/
    palette, non-interlaced. Reimplemented for this converter (no imports
    from the reference repo)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    pos = 8
    idat = bytearray()
    plte = None
    trns = None
    w = h = None
    bitdepth = colortype = interlace = None
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            w, h, bitdepth, colortype, _comp, _filt, interlace = \
                struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"PLTE":
            plte = chunk
        elif ctype == b"tRNS":
            trns = chunk
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
    if w is None:
        raise ValueError("PNG missing IHDR")
    if bitdepth != 8 or interlace != 0:
        raise ValueError(
            f"unsupported PNG (bitdepth={bitdepth}, interlace={interlace})")
    if colortype not in (0, 2, 3, 4, 6):
        raise ValueError(f"unsupported PNG colortype {colortype}")

    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    stride = w * bpp
    raw = zlib.decompress(bytes(idat))

    lines = []
    prev = bytearray(stride)
    p = 0
    for _y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa = abs(b - c)
                pb = abs(a - c)
                pc = abs(a + b - 2 * c)
                if pa <= pb and pa <= pc:
                    pr = a
                elif pb <= pc:
                    pr = b
                else:
                    pr = c
                line[i] = (line[i] + pr) & 255
        elif f != 0:
            raise ValueError(f"unknown PNG filter {f}")
        lines.append(line)
        prev = line

    out = bytearray(w * h * 4)
    for y, line in enumerate(lines):
        o = y * w * 4
        if colortype == 6:
            out[o:o + w * 4] = line
        elif colortype == 2:
            for x in range(w):
                out[o + x * 4:o + x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[o + x * 4 + 3] = 255
        elif colortype == 0:
            for x in range(w):
                g = line[x]
                out[o + x * 4:o + x * 4 + 4] = bytes((g, g, g, 255))
        elif colortype == 4:
            for x in range(w):
                g = line[x * 2]
                a = line[x * 2 + 1]
                out[o + x * 4:o + x * 4 + 4] = bytes((g, g, g, a))
        elif colortype == 3:
            if plte is None:
                raise ValueError("palette PNG missing PLTE")
            for x in range(w):
                idx = line[x]
                out[o + x * 4:o + x * 4 + 3] = plte[idx * 3:idx * 3 + 3]
                out[o + x * 4 + 3] = \
                    trns[idx] if (trns and idx < len(trns)) else 255
    return w, h, out


def png_encode(w: int, h: int, rgba: bytes) -> bytes:
    def chunk(ctype: bytes, payload: bytes) -> bytes:
        c = ctype + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(
            ">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)  # filter: none
        raw += rgba[y * stride:(y + 1) * stride]
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))


def alpha_bbox(rgba: bytes, w: int, h: int, threshold: int = 8):
    """Opaque bounding box, or None when fully transparent."""
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3] > threshold:
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
    if maxx < 0:
        return None
    return minx, miny, maxx + 1, maxy + 1


def crop_box(rgba: bytes, w: int, h: int, box):
    minx, miny, maxx, maxy = box
    cw, ch = maxx - minx, maxy - miny
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        src = ((miny + y) * w + minx) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = rgba[src:src + cw * 4]
    return cw, ch, out


# ------------------------------------------------------------- skin.ini I/O

def parse_ini(path: str):
    """Return list of (section_name, {key: value}); keeps duplicates."""
    sections = []
    cur = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.split("//")[0].split(";")[0].strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                cur = (line[1:-1].strip(), {})
                sections.append(cur)
            elif ":" in line and cur is not None:
                k, v = line.split(":", 1)
                cur[1][k.strip()] = v.strip()
    return sections


def pick_mania(sections, keys: int):
    for name, kv in sections:
        if name.lower() == "mania" and kv.get("Keys", "").strip() == str(keys):
            return kv
    for name, kv in sections:
        if name.lower() == "mania":
            return kv
    return {}


def ci_lookup(base: str, name: str, exts=(".png",)):
    """Case-insensitive file lookup; prefers @2x variants."""
    if not os.path.isdir(base):
        return None
    entries = {e.lower(): e for e in os.listdir(base)}
    for ext in exts:
        for candidate in (name + "@2x" + ext, name + ext,
                          name.lower() + "@2x" + ext, name.lower() + ext):
            real = entries.get(candidate.lower())
            if real:
                return os.path.join(base, real)
    return None


def resolve_ref(skin_dir: str, ref: str):
    """Resolve a skin.ini image reference like '4K\\lefto' (no extension)."""
    if not ref or ref.strip().lower() in ("blank", "none"):
        return None
    parts = ref.replace("/", "\\").split("\\")
    cur = skin_dir
    for part in parts[:-1]:
        found = None
        if os.path.isdir(cur):
            for e in os.listdir(cur):
                if e.lower() == part.lower() and os.path.isdir(
                        os.path.join(cur, e)):
                    found = os.path.join(cur, e)
                    break
        if not found:
            return None
        cur = found
    return ci_lookup(cur, parts[-1])


# ------------------------------------------------------------- pack builder

def load_sprite(path, label, warnings):
    """Decode + alpha-crop; None (with warning) when unreadable/empty."""
    try:
        with open(path, "rb") as f:
            w, h, px = png_decode(f.read())
    except (ValueError, OSError, IndexError, zlib.error, struct.error) as e:
        warnings.append(f"{label} ({os.path.basename(path)}) unreadable: "
                        f"{e}; skipped")
        return None
    box = alpha_bbox(px, w, h)
    if box is None:
        warnings.append(f"{label} ({os.path.basename(path)}) is fully "
                        f"transparent; skipped")
        return None
    return crop_box(px, w, h, box)


def build_atlas(sprites):
    """Stack named (w,h,rgba) sprites vertically with PAD; return
    (atlas_w, atlas_h, atlas_rgba, rects{name:(x,y,w,h)})."""
    rects = {}
    atlas_w = 0
    for _name, (w, _h, _px) in sprites:
        atlas_w = max(atlas_w, w)
    atlas_h = sum(h for _n, (_w, h, _p) in sprites) + PAD * (len(sprites) - 1)
    atlas = bytearray(atlas_w * atlas_h * 4)
    y = 0
    for name, (w, h, px) in sprites:
        rects[name] = (0, y, w, h)
        for row in range(h):
            dst = ((y + row) * atlas_w) * 4
            atlas[dst:dst + w * 4] = px[row * w * 4:(row + 1) * w * 4]
        y += h + PAD
    return atlas_w, atlas_h, atlas, rects


def sparrow_xml(rects):
    """Sparrow TextureAtlas XML for {frame_name: (x,y,w,h)}; every name gets
    the trailing 0000 the engine strips to form animation names."""
    lines = ['<?xml version="1.0" encoding="utf-8"?>', '<TextureAtlas>']
    for name in sorted(rects):
        x, y, w, h = rects[name]
        lines.append(
            f'\t<SubTexture name="{saxutils.escape(name)}0000" '
            f'x="{x}" y="{y}" width="{w}" height="{h}"/>')
    lines.append('</TextureAtlas>')
    return "\n".join(lines) + "\n"


def frame_entries(color, has_tail):
    """(xml_frame_name, sprite_key) pairs for one direction color."""
    entries = [
        (f"{color}", "note"),
        (f"{color} alone", "note"),
        ("note", "note"),
        ("note alone", "note"),
        (f"{color} hold", "hold"),
        (f"{color} hold piece", "piece"),
        ("note hold", "hold"),
        ("note hold piece", "piece"),
        ("receptor", "receptor"),
        ("receptor static", "receptor"),
        ("receptor confirm", "press"),
        ("receptor press", "press"),
        ("receptor pressed", "press"),
    ]
    if has_tail:
        entries += [
            (f"{color} hold end", "end"),
            (f"{color} end hold", "end"),
            (f"{color} tail", "end"),
            ("note hold end", "end"),
            ("note holdend", "end"),
            ("note tail", "end"),
        ]
    return entries


def convert_osu_skin(skin_dir: str, out: str, keys: int = 4, lane=None,
                      name=None):
    """Convert an osu!mania skin folder into an AFN skin pack; return the
    pack dir, or None on refusal/error (mirrors osu_to_afn semantics:
    never overwrite a pack with different content)."""
    warnings = []
    ini_path = os.path.join(skin_dir, "skin.ini")
    if not os.path.isfile(ini_path):
        print(f"ERROR: {ini_path} not found", file=sys.stderr)
        return None
    sections = parse_ini(ini_path)
    mania = pick_mania(sections, keys)
    general = next((kv for n, kv in sections if n.lower() == "general"), {})
    lane = lane or (keys // 2 + keys % 2)  # 1-based base lane
    base = lane - 1

    def lane_path(j, *roles):
        """Resolve osu lane j's sprite for the first matching role suffix."""
        for role in roles:
            ref = mania.get(f"NoteImage{j}{role}", "").strip()
            if ref:
                p = resolve_ref(skin_dir, ref)
                if p:
                    return p
        p = ci_lookup(skin_dir, f"mania-note{min(j + 1, 10)}")
        return p

    def key_path(j, down):
        ref = mania.get(f"KeyImage{j}{'D' if down else ''}", "").strip()
        if ref:
            p = resolve_ref(skin_dir, ref)
            if p:
                return p
        suf = "D" if down else ""
        return ci_lookup(skin_dir, f"mania-key{min(j + 1, 10)}{suf}")

    # Resolve per-lane art (osu lanes 0..keys-1 -> AFN Left/Down/Up/Right).
    art = {}
    for j in range(keys):
        art[j] = {
            "note": lane_path(j, "", "H"),
            "hold": lane_path(j, "H"),
            "piece": lane_path(j, "L"),
            "end": lane_path(j, "T"),
            "receptor": key_path(j, False),
            "press": key_path(j, True),
        }
    if not art[base]["note"]:
        print("ERROR: could not resolve a tap-note image (skin.ini "
              "NoteImage*, mania-note*)", file=sys.stderr)
        return None
    if not art[base]["receptor"]:
        warnings.append("no receptor image found, reusing the tap note image")
        art[base]["receptor"] = art[base]["note"]
    if not art[base]["piece"]:
        warnings.append("no LN body image (NoteImage*L); holds will use the "
                        "tap image as a plain bar")
        art[base]["piece"] = art[base]["note"]
    if not art[base]["end"]:
        warnings.append("no LN end cap (NoteImage*T); hold tails will use "
                        "the body piece")
    for j in range(keys):
        for role in ("note", "receptor"):
            if not art[j][role]:
                art[j][role] = art[base][role]
        for role in ("hold", "piece", "press"):
            if not art[j][role]:
                art[j][role] = art[base][role] or art[base]["note"]
        if not art[j]["end"]:
            art[j]["end"] = art[base]["end"]

    def sprite(j, role):
        key = (j, role)
        if key in sprite_cache:
            return sprite_cache[key]
        p = art[j][role]
        got = load_sprite(p, f"lane {j + 1} {role}", warnings) if p else None
        if got is None and role in ("hold", "piece", "press"):
            got = sprite(j, {"hold": "note", "piece": "note",
                             "press": "receptor"}[role])
        sprite_cache[key] = got
        return got

    sprite_cache = {}
    color_png = {}   # filename -> png bytes
    color_files = {}  # color -> (png filename, xml, w, h, ...)
    manifests = {}
    built = []  # (dirname, color, osu_lane, png, xml, w, h, has_tail)
    for idx, (dirname, color) in enumerate(DIRS):
        j = idx if idx < keys else base
        sprites = [
            ("note", sprite(j, "note")),
            ("hold", sprite(j, "hold")),
            ("piece", sprite(j, "piece")),
            ("receptor", sprite(j, "receptor")),
            ("press", sprite(j, "press")),
        ]
        if art[j]["end"]:
            end = sprite(j, "end")
            if end is not None:
                sprites.append(("end", end))
        sprites = [(n, s) for n, s in sprites if s is not None]
        if not sprites:
            print(f"ERROR: lane {j + 1} has no usable art", file=sys.stderr)
            return None
        aw, ah, atlas, rects = build_atlas(sprites)
        png = png_encode(aw, ah, atlas)
        has_tail = "end" in rects
        frames = {fname: rects[skey]
                  for fname, skey in frame_entries(color, has_tail)}
        built.append((dirname, color, j, png, sparrow_xml(frames),
                      aw, ah, has_tail))
    base_entry = next((b for b in built if b[2] == base), built[0])
    base_png, base_dir = base_entry[3], base_entry[0]
    for dirname, color, _j, png, xml, aw, ah, has_tail in built:
        if dirname == base_dir:
            fname = "sheet.png"
        elif png == base_png:
            fname = "sheet.png"  # identical to base lane: share the file
        else:
            fname = f"sheet_{dirname.lower()}.png"
        color_png.setdefault(fname, png)
        color_files[color] = (fname, xml, aw, ah)
        manifests[dirname] = {
            "color": color,
            "png": fname,
            "xml": f"{color}.xml",
            "w": aw,
            "h": ah,
            "body": fname,
            "tailCap": fname if has_tail else None,
        }

    name = name or general.get("Name") or os.path.basename(
        os.path.normpath(skin_dir))
    slug = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower() or "skin"
    out_dir = os.path.join(out, slug)
    os.makedirs(out_dir, exist_ok=True)

    planned = {}
    for color, (fname, xml, _aw, _ah) in color_files.items():
        planned[fname] = color_png[fname]
        planned[f"{color}.xml"] = xml.encode("utf-8")
    manifest = {
        "format": "afn-skin/1",
        "name": name,
        "source": {"game": "osu", "skinDir": skin_dir, "keys": keys,
                   "lane": lane},
        "dirs": manifests,
    }
    planned["manifest.json"] = json.dumps(
        manifest, ensure_ascii=False, indent=2).encode("utf-8")

    for fname, data in planned.items():
        if fname != "manifest.json" and not isinstance(data, bytes):
            continue
        target = os.path.join(out_dir, fname)
        blob = data if isinstance(data, bytes) else data.encode("utf-8")
        if os.path.isfile(target):
            with open(target, "rb") as f:
                if f.read() == blob:
                    continue
            print(f"ERROR: refusing to overwrite '{fname}' (different "
                  f"content)", file=sys.stderr)
            return None
        with open(target, "wb") as f:
            f.write(blob)
    # stale direction files from an earlier run of this pack
    for entry in os.listdir(out_dir):
        if (entry.endswith((".png", ".xml")) and entry not in planned
                and entry != "manifest.json"):
            os.remove(os.path.join(out_dir, entry))

    print(f"pack:    {out_dir}")
    print(f"name:    {name}")
    for dirname, color in DIRS:
        print(f"{dirname:<8} {color:<8} {manifests[dirname]['png']}")
    for wmsg in warnings:
        print(f"! {wmsg}", file=sys.stderr)
    return out_dir


def main():
    ap = argparse.ArgumentParser(
        description="Convert an osu!mania skin into an AfternightCustomSongs "
                    "skin pack")
    ap.add_argument("skin_dir", help="osu! skin folder (contains skin.ini)")
    ap.add_argument("--out", required=True, help="output Skins directory")
    ap.add_argument("--keys", type=int, default=4,
                    help="key-count section to use (default 4)")
    ap.add_argument("--lane", type=int, default=None,
                    help="1-based base lane when lanes differ "
                         "(default: middle lane)")
    ap.add_argument("--name", default=None,
                    help="display name (default: skin.ini Name)")
    args = ap.parse_args()
    out_dir = convert_osu_skin(args.skin_dir, args.out, keys=args.keys,
                               lane=args.lane, name=args.name)
    if out_dir is None:
        sys.exit(1)


if __name__ == "__main__":
    main()