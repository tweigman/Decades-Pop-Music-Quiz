#!/usr/bin/env python3
"""Download the Spotify preview clips listed in the category CSVs.

    python3 download_previews.py                      # every categories/*.csv
    python3 download_previews.py categories/eighties.csv   # just one category

Files land in previews/<track_id>.mp3 and the run is resumable: anything
already on disk and intact is skipped, so re-running after an interruption
only fetches what's missing.

Also writes previews/index.csv with the *measured* length of each clip.
That matters -- the clips are not all 30 seconds. Observed lengths run from
15s to 30s, so any code that picks a random offset must read the real
duration rather than assuming a fixed window.
"""

import csv
import glob
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
OUT_DIR = "previews"
WORKERS = 6
MIN_INTERVAL = 0.12  # p.scdn.co is a plain CDN, so this can be brisker than the API scrape
MIN_BYTES = 20_000  # anything smaller is a truncated or error payload, not audio
ASSUMED_BITRATE = 96_000  # observed on every clip sampled; used only without ffprobe

_slot_lock = threading.Lock()
_next_slot = [0.0]


def pace():
    with _slot_lock:
        start = max(time.monotonic(), _next_slot[0])
        _next_slot[0] = start + MIN_INTERVAL
    delay = start - time.monotonic()
    if delay > 0:
        time.sleep(delay)


def looks_like_mp3(path):
    """Guard against half-written files from an interrupted run."""
    try:
        if os.path.getsize(path) < MIN_BYTES:
            return False
        with open(path, "rb") as f:
            head = f.read(3)
        return head[:3] == b"ID3" or head[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2")
    except OSError:
        return False


HAVE_FFPROBE = shutil.which("ffprobe") is not None


def duration_seconds(path):
    """Measured clip length. Exact via ffprobe, else derived from CBR size."""
    if HAVE_FFPROBE:
        try:
            out = subprocess.run(
                ["ffprobe", "-v", "error", "-show_entries", "format=duration",
                 "-of", "csv=p=0", path],
                capture_output=True, text=True, timeout=30,
            ).stdout.strip()
            if out:
                return round(float(out), 1)
        except (subprocess.SubprocessError, ValueError):
            pass
    return round(os.path.getsize(path) * 8 / ASSUMED_BITRATE, 1)


def fetch(task):
    category, row = task
    track_id = row["URL"].rstrip("/").split("/")[-1].split("?")[0]
    dest = os.path.join(OUT_DIR, f"{track_id}.mp3")

    if looks_like_mp3(dest):
        return category, row, dest, "skipped"

    tmp = dest + ".part"
    for attempt in range(4):
        pace()
        try:
            req = urllib.request.Request(row["Preview URL"], headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f)
            if not looks_like_mp3(tmp):
                raise OSError(f"bad payload ({os.path.getsize(tmp)} bytes)")
            os.replace(tmp, dest)
            return category, row, dest, "ok"
        except Exception as exc:  # noqa: BLE001 - retry anything transient
            last = f"{type(exc).__name__}: {exc}"
            time.sleep(2 * (attempt + 1))
    if os.path.exists(tmp):
        os.remove(tmp)
    return category, row, None, last


def main(paths):
    os.makedirs(OUT_DIR, exist_ok=True)

    tasks, no_preview = [], []
    for p in paths:
        # Category name is the filename stem, so a future categories/holiday.csv
        # needs no code change.
        category = os.path.splitext(os.path.basename(p))[0]
        with open(p, newline="") as f:
            for row in csv.DictReader(f):
                (tasks if row.get("Preview URL") else no_preview).append((category, row))

    print(f"{len(tasks)} clips to fetch across {len(paths)} categories "
          f"({len(no_preview)} tracks have no preview)")
    if not HAVE_FFPROBE:
        print("note: ffprobe not found — clip lengths estimated from file size")

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        results = list(pool.map(fetch, tasks))

    index, failed, counts = [], [], {"ok": 0, "skipped": 0}
    for category, row, dest, status in results:
        if dest is None:
            failed.append((category, row, status))
            continue
        counts[status] += 1
        index.append({
            "Track ID": os.path.basename(dest)[:-4],
            "Category": category,
            "Clean Title": row["Clean Title"],
            "Artist(s)": row["Artist(s)"],
            "File": dest,
            "Bytes": os.path.getsize(dest),
            "Preview (s)": duration_seconds(dest),
        })

    index.sort(key=lambda r: (r["Category"], r["Clean Title"].lower()))
    index_path = os.path.join(OUT_DIR, "index.csv")
    with open(index_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(index[0].keys()))
        w.writeheader()
        w.writerows(index)

    total = sum(r["Bytes"] for r in index)
    lengths = sorted(r["Preview (s)"] for r in index)
    print(f"\ndownloaded {counts['ok']}, already had {counts['skipped']}, failed {len(failed)}")
    print(f"{len(index)} files, {total / 1e6:.0f} MB in {OUT_DIR}/  -> {index_path}")
    if lengths:
        print(f"clip length: min {lengths[0]}s | median {lengths[len(lengths) // 2]}s | max {lengths[-1]}s")
        short = sum(1 for s in lengths if s < 25)
        print(f"{short} clips are under 25s — do not assume a 30s window")
    for category, row, err in failed:
        print(f"  FAILED {category} {row['Clean Title']}: {err}", file=sys.stderr)
    if failed:
        print("  re-run to retry just these", file=sys.stderr)


if __name__ == "__main__":
    args = sys.argv[1:] or sorted(glob.glob(os.path.join("categories", "*.csv")))
    main(args)
