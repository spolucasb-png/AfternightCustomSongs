#!/usr/bin/env python3
"""Batch port: song folders (SM/Etterna) or .osz archives -> staged workspace.

scan  = convert to a throwaway dir, print/emit one CSV row per difficulty
stage = convert straight into <ws>/Charts and copy audio + cover per stem

Usage:
  python converters/batch_port.py scan  --source <dir> [--report out.csv]
  python converters/batch_port.py stage --source <dir> --workspace <ws>
        [--only picks.txt] [--max-diffs 6] [--attached]
  python converters/batch_port.py scan  --osz <file.osz> [--report out.csv]
  python converters/batch_port.py stage --osz <file.osz> --workspace <ws>

--source <dir>: every direct subdirectory holding .sm/.ssc is one song
(--attached: the <dir> itself holds the .sm/.ssc files).
--only <txt>: one source name per line (folder name or .osz path); stage
scans and stages just those.

Audio: SM #MUSIC (folder-resolved, case-insensitive) else the largest
.mp3/.ogg/.wav in the song dir; osz AudioFilename entry else largest.
Cover: song-dir image preferring bg/back/jacket/cover/banner names, else
largest >= 8 KB; osz [Events] background, else largest non-storyboard image.
Emitted per staged difficulty: <stem>.chart.json -> Charts, audio and cover
copied as <stem><ext> -> Audio / Covers (one copy per stem, like the player
expects; a song's diffs each carry their own copy of the same files).
No-overwrite semantics are inherited from the converters: a colliding id
with different bytes is refused and reported, never rewritten.
"""
import argparse
import contextlib
import csv
import io
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import eterna_to_afn  # noqa: E402
import osu_to_afn  # noqa: E402

IMG_EXTS = (".png", ".jpg", ".jpeg", ".bmp")
AUD_EXTS = (".mp3", ".ogg", ".wav")
COVER_NAME_HINTS = ("bg", "back", "jacket", "cover", "banner")
MIN_COVER_BYTES = 8 * 1024
DIFF_ORDER = {"beginner": 0, "easy": 1, "medium": 2, "normal": 3, "hard": 4,
              "challenge": 5, "expert": 6, "insane": 7, "edit": 8}


def pick_cover(files):
    imgs = [p for p in files if p.suffix.lower() in IMG_EXTS]
    if not imgs:
        return None

    def key(p):
        name = p.stem.lower()
        hinted = any(h in name for h in COVER_NAME_HINTS)
        try:
            size = p.stat().st_size
        except OSError:
            size = 0
        return (hinted, size)

    imgs.sort(key=key, reverse=True)
    for p in imgs:
        if p.stat().st_size >= MIN_COVER_BYTES:
            return p
    return imgs[0]


def pick_audio_dir(song_dir, music_tag=None):
    if music_tag:
        cand = song_dir / music_tag
        if cand.is_file():
            return cand
        for f in song_dir.iterdir():
            if f.is_file() and f.name.lower() == music_tag.lower():
                return f
    auds = [p for p in song_dir.iterdir()
            if p.is_file() and p.suffix.lower() in AUD_EXTS]
    auds.sort(key=lambda p: p.stat().st_size, reverse=True)
    return auds[0] if auds else None


def sm_diffs(sm_path):
    """Difficulty names in file order (for per-diff conversion calls)."""
    text = sm_path.read_text(encoding="utf-8", errors="replace")
    tags = eterna_to_afn.parse_sm(text)
    out = []
    for tag, value in tags:
        if tag != "NOTES":
            continue
        parsed = eterna_to_afn.parse_notes_block(value)
        if parsed is None:
            continue
        stepstype, diff, meter, _ = parsed
        if stepstype != "dance-single":
            continue
        label = (diff or "Unknown")
        out.append((label, meter or ""))
    # hardest first so --max-diffs keeps the meat
    out.sort(key=lambda t: (DIFF_ORDER.get(t[0].lower(), 99),
                            -float(t[1]) if t[1].replace(".", "").isdigit()
                            else 0))
    return out


def sm_music_tag(sm_path):
    text = sm_path.read_text(encoding="utf-8", errors="replace")
    for tag, value in eterna_to_afn.parse_sm(text):
        if tag == "MUSIC" and value.strip():
            return value.strip().strip('"')
    return None


def wrapper_stats(w):
    rows = w["song"]["notes"][0]["sectionNotes"]
    holds = sum(1 for r in rows if len(r) > 2 and r[2] > 0)
    return {
        "title": w["song"].get("title", w["song"]["song"]),
        "artist": w["song"].get("artist", ""),
        "diff": w["song"].get("difficulty", ""),
        "keys": w["song"]["keyCount"],
        "notes": len(rows),
        "holds": holds,
        "sv": len(w["sliderVelocities"]),
        "bpm_changes": len(w["bpmChanges"]),
    }


def stage_song_folder(song_dir, ws, report, max_diffs, do_stage):
    """Convert one song folder. Returns list of staged stems."""
    sms = sorted([p for p in song_dir.iterdir()
                  if p.is_file() and p.suffix.lower() in (".sm", ".ssc")])
    stems = []
    for sm in sms:
        diffs = sm_diffs(sm)
        if not diffs:
            report.append({"source": song_dir.name, "sm": sm.name,
                           "error": "no dance-single diffs"})
            continue
        music = sm_music_tag(sm)
        audio = pick_audio_dir(song_dir, music)
        cover = pick_cover([p for p in song_dir.iterdir() if p.is_file()])
        chosen = diffs[:max_diffs] if max_diffs else diffs
        out_dir = Path(ws) / "Charts" if do_stage else Path(
            tempfile.mkdtemp(prefix="afnscan_"))
        try:
            for diff_name, meter in chosen:
                out_dir.mkdir(parents=True, exist_ok=True)
                if do_stage:
                    wrappers = eterna_to_afn.convert_file(
                        sm, out_dir, difficulty=diff_name)
                else:
                    with contextlib.redirect_stdout(io.StringIO()), \
                            contextlib.redirect_stderr(io.StringIO()):
                        wrappers = eterna_to_afn.convert_file(
                            sm, out_dir, difficulty=diff_name)
                if not wrappers:
                    report.append({"source": song_dir.name, "sm": sm.name,
                                   "diff": f"{diff_name} {meter}",
                                   "error": "refused or empty"})
                    continue
                for w in wrappers:
                    stem = w["song"]["song"]
                    row = {"source": song_dir.name, "sm": sm.name, **wrapper_stats(w)}
                    if do_stage:
                        stage_files(Path(ws), stem, audio, cover)
                        row["staged"] = stem
                        stems.append(stem)
                    report.append(row)
        finally:
            if not do_stage:
                shutil.rmtree(out_dir, ignore_errors=True)
    return stems


def stage_files(ws, stem, audio, cover):
    if audio is not None:
        dest = Path(ws) / "Audio" / (stem + audio.suffix.lower())
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(audio, dest)
    if cover is not None:
        dest = Path(ws) / "Covers" / (stem + cover.suffix.lower())
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(cover, dest)


def osz_entries(zf):
    osus = [n for n in zf.namelist() if n.lower().endswith(".osu")]
    imgs = [n for n in zf.namelist()
            if Path(n).suffix.lower() in IMG_EXTS and not n.startswith("SB/")]
    auds = [n for n in zf.namelist() if Path(n).suffix.lower() in AUD_EXTS]
    return osus, imgs, auds


def osz_pick_cover(zf, imgs):
    for n in zf.namelist():
        if n.lower().endswith(".osu"):
            text = zf.read(n).decode("utf-8", "replace")
            m = re.search(r'0,0,"([^"]+)"', text)
            if m:
                target = m.group(1)
                for img in imgs:
                    if Path(img).name == target:
                        return img
    if not imgs:
        return None
    return max(imgs, key=lambda n: zf.getinfo(n).file_size)


def osz_pick_audio(zf, osu_name, auds):
    text = zf.read(osu_name).decode("utf-8", "replace")
    m = re.search(r"^AudioFilename:\s*(.+)$", text, re.M)
    if m:
        target = m.group(1).strip()
        for a in auds:
            if Path(a).name.lower() == target.lower():
                return a
    if not auds:
        return None
    return max(auds, key=lambda n: zf.getinfo(n).file_size)


def stage_osz(osz_path, ws, report, do_stage):
    stems = []
    with zipfile.ZipFile(osz_path) as zf:
        osus, imgs, auds = osz_entries(zf)
        cover_name = osz_pick_cover(zf, imgs)
        cover_bytes = zf.read(cover_name) if cover_name else None
        cover_ext = Path(cover_name).suffix.lower() if cover_name else ""
        tmp = Path(tempfile.mkdtemp(prefix="afnosz_"))
        try:
            for i, osu in enumerate(osus, 1):
                local = tmp / f"{i}.osu"
                local.write_bytes(zf.read(osu))
                out_dir = Path(ws) / "Charts" if do_stage else tmp / "out"
                out_dir.mkdir(parents=True, exist_ok=True)
                if do_stage:
                    w = osu_to_afn.convert_file(local, out_dir)
                else:
                    with contextlib.redirect_stdout(io.StringIO()), \
                            contextlib.redirect_stderr(io.StringIO()):
                        w = osu_to_afn.convert_file(local, out_dir)
                if not w:
                    report.append({"source": osz_path.name, "sm": osu,
                                   "error": "refused or empty"})
                    continue
                stem = w["song"]["song"]
                row = {"source": osz_path.name, "sm": osu, **wrapper_stats(w)}
                if do_stage:
                    audio_name = osz_pick_audio(zf, osu, auds)
                    if audio_name:
                        dest = (Path(ws) / "Audio" /
                                (stem + Path(audio_name).suffix.lower()))
                        dest.write_bytes(zf.read(audio_name))
                    if cover_bytes:
                        dest = Path(ws) / "Covers" / (stem + cover_ext)
                        dest.write_bytes(cover_bytes)
                    row["staged"] = stem
                    stems.append(stem)
                report.append(row)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return stems


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=("scan", "stage"))
    ap.add_argument("--source", type=Path, default=None)
    ap.add_argument("--osz", type=Path, action="append", default=None)
    ap.add_argument("--workspace", type=Path, default=None)
    ap.add_argument("--report", type=Path, default=None)
    ap.add_argument("--only", type=Path, default=None)
    ap.add_argument("--max-diffs", type=int, default=6)
    ap.add_argument("--attached", action="store_true")
    args = ap.parse_args()

    do_stage = args.mode == "stage"
    if do_stage and not args.workspace:
        print("ERROR: stage needs --workspace", file=sys.stderr)
        return 1
    if not args.source and not args.osz:
        print("ERROR: pass --source and/or --osz", file=sys.stderr)
        return 1

    only = None
    if args.only:
        only = {ln.strip() for ln in args.only.read_text(encoding="utf-8")
                .splitlines() if ln.strip()}

    report = []
    stems = []

    if args.source:
        source = args.source
        if args.attached:
            dirs = [source]
        else:
            dirs = sorted([d for d in source.iterdir()
                           if d.is_dir() and any(
                               p.suffix.lower() in (".sm", ".ssc")
                               for p in d.iterdir() if p.is_file())])
        if only is not None:
            dirs = [d for d in dirs if d.name in only]
        print(f"source: {source} -> {len(dirs)} song folder(s)")
        for d in dirs:
            got = stage_song_folder(d, args.workspace, report,
                                    args.max_diffs, do_stage)
            stems.extend(got)
            tag = f"[{d.name}]"
            rows = [r for r in report if r.get("source") == d.name
                    and "error" not in r]
            if not rows:
                errs = [r.get("error") for r in report
                        if r.get("source") == d.name]
                print(f"  {tag} SKIP ({errs[0] if errs else '?'})")
            else:
                print(f"  {tag} {len(rows)} diff(s)"
                      + (f", staged {len(got)}" if do_stage else ""))

    for osz in (args.osz or []):
        if only is not None and osz.name not in only:
            continue
        print(f"osz: {osz.name}")
        stems.extend(stage_osz(osz, args.workspace, report, do_stage))

    csv_buf = io.StringIO()
    cols = ["source", "sm", "title", "artist", "diff", "keys", "notes",
            "holds", "sv", "bpm_changes", "staged", "error"]
    writer = csv.DictWriter(csv_buf, fieldnames=cols, extrasaction="ignore")
    writer.writeheader()
    for row in report:
        writer.writerow(row)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(csv_buf.getvalue(), encoding="utf-8")
        print(f"report: {args.report} ({len(report)} rows)")

    ok = [r for r in report if "error" not in r and "staged" not in r]
    errs = [r for r in report if "error" in r]
    if do_stage:
        print(f"Done: {len(stems)} chart(s) staged, {len(errs)} error(s)")
    else:
        print(f"Done: {len(ok)} convertible diff(s), {len(errs)} error(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
