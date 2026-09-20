#!/usr/bin/env python3
"""Add a category end to end, or report where every category stands.

    python3 new_category.py raw/Holiday.txt          # -> categories/holiday.csv
    python3 new_category.py raw/Holiday.txt xmas     # explicit category name
    python3 new_category.py                          # status of all categories

Runs the three pipeline steps in order -- metadata, clips, chart peaks --
because a category that gets only part way through is invisible at play time:
the game skips any category with no downloadable clips. Doing it in one
command is what stops that happening.

Each step is individually resumable, so re-running after an interruption
picks up where it left off.
"""

import csv
import glob
import os
import subprocess
import sys

CATEGORIES = "categories"
STEPS = [
    ("metadata", "spotify_to_csv.py"),
    ("clips", "download_previews.py"),
    ("chart peaks", "add_chart_peaks.py"),
]
MIN_EASY = 18  # game needs this many easy songs to run a round; see const.py
EASY_MAX_PEAK = 10


def category_name(urls_path, explicit=None):
    """Category names are lowercase with underscores: 'Holiday.txt' -> 'holiday'."""
    if explicit:
        stem = explicit
    else:
        stem = os.path.splitext(os.path.basename(urls_path))[0]
    return stem.strip().lower().replace(" ", "_").replace("-", "_")


def status(paths=None):
    paths = paths or sorted(glob.glob(os.path.join(CATEGORIES, "*.csv")))
    print(f"{'category':>18} {'songs':>6} {'clips':>6} {'peaks':>6} {'easy':>5}  state")
    for p in paths:
        with open(p, newline="") as f:
            rows = list(csv.DictReader(f))
        clips = [r for r in rows if r.get("MP3 File") and
                 os.path.isfile(os.path.join("previews", r["MP3 File"]))]
        peaks = [r for r in rows if r.get("Peak (Hot 100)")]
        # Mirror data.py: the Difficulty override wins, peak is the fallback.
        easy = [r for r in rows if (r.get("Difficulty") or "").strip().lower() == "easy"
                or (not (r.get("Difficulty") or "").strip()
                    and r.get("Peak (Hot 100)")
                    and int(float(r["Peak (Hot 100)"])) <= EASY_MAX_PEAK)]

        if not clips:
            state = "NOT PLAYABLE — run download_previews.py"
        elif len(clips) < len(rows):
            state = f"{len(rows) - len(clips)} song(s) missing a clip"
        elif len(easy) < MIN_EASY:
            state = f"playable, but only {len(easy)} easy songs (want {MIN_EASY}+)"
        else:
            state = "ok"
        name = os.path.splitext(os.path.basename(p))[0]
        print(f"{name:>18} {len(rows):>6} {len(clips):>6} {len(peaks):>6} {len(easy):>5}  {state}")


def main(argv):
    if not argv:
        status()
        return 0

    urls_path = argv[0]
    if not os.path.exists(urls_path):
        print(f"no such url list: {urls_path}", file=sys.stderr)
        return 1

    name = category_name(urls_path, argv[1] if len(argv) > 1 else None)
    dest = os.path.join(CATEGORIES, f"{name}.csv")
    print(f"{urls_path} -> {dest}\n")

    for label, script in STEPS:
        print(f"=== {label} ===", flush=True)
        # spotify_to_csv takes an output path; the other two read the CSV.
        args = [sys.executable, script, urls_path, dest] if script == STEPS[0][1] \
            else [sys.executable, script, dest]
        result = subprocess.run(args)
        if result.returncode != 0:
            print(f"\n{label} failed — fix, then re-run this command "
                  f"(finished steps are skipped)", file=sys.stderr)
            return result.returncode
        print()

    status([dest])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
