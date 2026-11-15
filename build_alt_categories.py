#!/usr/bin/env python3
"""Build altcategories/*.csv: chart hits per decade, straight from Billboard.

    python3 build_alt_categories.py            # top-20 hits (default)
    python3 build_alt_categories.py --max-peak 10

Unlike categories/, which starts from Spotify playlists, these lists start
from the Hot 100 archive itself: every song that peaked at --max-peak or
better, in the order it first charted. Preview columns are left blank, to be
filled in by a later step.

A song belongs to the decade it FIRST charted in, not the one it peaked in.
Streaming-era re-entries would otherwise put 'Jolene' in the 2020s. The peak
is still its best position ever.

Holiday songs are left out (they recur every December and have their own
category); they are listed in altcategories/_excluded_holiday.csv.
"""

import argparse
import csv
import os
import re
from collections import defaultdict
from datetime import date

from add_chart_peaks import CACHE, artist_tokens, artists_match, load_hot100, norm_title

OUT_DIR = "altcategories"
DECADES = {195: "fifties", 196: "sixties", 197: "seventies", 198: "eighties",
           199: "nineties", 200: "two_thousands", 201: "twenty_tens",
           202: "twenty_twenties"}
FIELDS = ["#", "URL", "Title", "Clean Title", "Artist(s)", "Year",
          "Duration (ms)", "MP3 File", "Preview URL", "Peak (Hot 100)",
          "Difficulty", "First Charted", "Peak Date", "Weeks on Chart"]
HOLIDAY_WORDS = re.compile(
    r"christmas|xmas|santa|rudolph|jingle|sleigh|snowman|mistletoe|noel|"
    r"winter wonderland|holly jolly|let it snow|navidad|silent night|"
    r"drummer boy|auld lang|reindeer|chipmunk song|deck the halls|"
    r"most wonderful time|new year", re.I)


def is_holiday_week(week):
    """True for charts dated late November through mid January."""
    mm, dd = int(week[5:7]), int(week[8:10])
    return mm == 12 or (mm == 1 and dd <= 15) or (mm == 11 and dd >= 25)


def collect(path):
    """One record per song, merging credit variants ('Kanye West' / 'Ye')."""
    exact = {}
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for r in csv.DictReader(f):
            try:
                pos = int(r["current_week"])
            except ValueError:
                continue
            week = r["chart_week"]
            s = exact.setdefault((r["title"], r["performer"]), {
                "title": r["title"], "performer": r["performer"],
                "toks": artist_tokens(r["performer"]), "peak": 101,
                "peak_week": week, "weeks": set()})
            s["weeks"].add(week)
            if pos < s["peak"] or (pos == s["peak"] and week < s["peak_week"]):
                s["peak"], s["peak_week"] = pos, week

    by_title = defaultdict(list)
    for s in sorted(exact.values(), key=lambda s: min(s["weeks"])):
        s["first"], s["last"] = min(s["weeks"]), max(s["weeks"])
        group = by_title[norm_title(s["title"])]
        for old in group:
            if same_recording(old, s):
                # Keep the title and credit as first charted.
                old["toks"] |= s["toks"]
                old["weeks"] |= s["weeks"]
                old["last"] = max(old["last"], s["last"])
                if s["peak"] < old["peak"]:
                    old["peak"], old["peak_week"] = s["peak"], s["peak_week"]
                break
        else:
            group.append(s)
    return [s for group in by_title.values() for s in group]


def same_recording(old, new):
    """Same title already; is it the same record under a changed credit?

    A shared surname is not enough: 'Release Me' is Esther Phillips in 1962
    and Wilson Phillips in 1990. So a loose artist match only counts when the
    two chart runs sit close together; otherwise most names must agree.
    """
    a, b = old["toks"], new["toks"]
    if not artists_match(a, b):
        return False
    if len(a & b) / len(a | b) > 0.5:
        return True
    gap = date.fromisoformat(new["first"]) - date.fromisoformat(old["last"])
    return gap.days <= 400


def is_holiday(s):
    weeks = s["weeks"]
    seasonal = sum(is_holiday_week(w) for w in weeks) / len(weeks)
    years = {w[:4] for w in weeks}
    if HOLIDAY_WORDS.search(s["title"]) and seasonal >= 0.8:
        return True
    return seasonal >= 0.95 and len(years) >= 4


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--max-peak", type=int, default=20)
    args = ap.parse_args()

    load_hot100(CACHE)  # downloads the archive if it is missing
    songs = [s for s in collect(CACHE) if s["peak"] <= args.max_peak]
    os.makedirs(OUT_DIR, exist_ok=True)

    holiday = sorted((s for s in songs if is_holiday(s)), key=lambda s: s["first"])
    with open(os.path.join(OUT_DIR, "_excluded_holiday.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Title", "Artist(s)", "First Charted", "Peak (Hot 100)"])
        for s in holiday:
            w.writerow([s["title"], s["performer"], s["first"], s["peak"]])

    by_decade = defaultdict(list)
    for s in songs:
        if not is_holiday(s):
            by_decade[int(s["first"][:3])].append(s)

    for key, name in DECADES.items():
        rows = sorted(by_decade[key], key=lambda s: (s["first"], s["peak"], s["title"]))
        with open(os.path.join(OUT_DIR, name + ".csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS)
            w.writeheader()
            for i, s in enumerate(rows, 1):
                w.writerow({"#": i, "Title": s["title"], "Clean Title": s["title"],
                            "Artist(s)": s["performer"], "Year": s["first"][:4],
                            "Peak (Hot 100)": s["peak"], "First Charted": s["first"],
                            "Peak Date": s["peak_week"], "Weeks on Chart": len(s["weeks"])})
        tiers = [sum(1 for s in rows if s["peak"] <= n) for n in (1, 5, 10, 20)]
        print(f"{name:>16}: {len(rows):>4} songs   #1s {tiers[0]:>3}   top5 {tiers[1]:>3}   top10 {tiers[2]:>4}   top20 {tiers[3]:>4}")
    print(f"\n{len(holiday)} holiday songs left out -> {OUT_DIR}/_excluded_holiday.csv")


if __name__ == "__main__":
    main()
