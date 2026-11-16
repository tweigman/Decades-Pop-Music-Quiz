#!/usr/bin/env python3
"""Build altcategories/holiday.csv: the curated holiday list plus chart extras.

    python3 build_alt_holiday.py

The Hot 100 is a poor source of holiday songs on its own (120 ever charted,
most of them streaming-era re-entries), so this starts from the hand-curated
categories/holiday.csv, keeps its Difficulty levels, and adds charted holiday
songs it lacks (peak --max-peak or better).

'Artist(s)' holds the lead artist only -- 'Bing Crosby', not 'Bing Crosby;
Ken Darby Singers; John Scott Trotter & His Orchestra' -- and the original
credit moves to 'Full Artist'. SHORT below overrides the rule where the lead
name alone is the wrong answer.

Preview and timing columns are preserved on rebuild; fill them with
fetch_apple_previews.py --ignore-year and detect_lyrics.py.
"""

import argparse
import csv
import os
import re

import build_alt_categories as B
from add_chart_peaks import artist_tokens, artists_match, norm_title

SRC = os.path.join("categories", "holiday.csv")
OUT = os.path.join(B.OUT_DIR, "holiday.csv")
i = B.FIELDS.index("Artist(s)") + 1
FIELDS = B.FIELDS[:i] + ["Full Artist"] + B.FIELDS[i:]

# Billboard writes one string; cut it at the first supporting credit.
SUPPORT = re.compile(
    r"\s+(?:featuring|feat\.?|with|duet with|and (?:his|her|the)|& (?:his|her|the))\s.*$", re.I)
# Full credit -> short name, where 'first name listed' is not the best answer.
SHORT = {
    "David Seville And The Chipmunks": "The Chipmunks",
    "Daryl Hall & John Oates": "Hall & Oates",
    "Kelly Clarkson & Brett Eldredge": "Kelly Clarkson",
    "Pyotr Ilyich Tchaikovsky; Russian National Orchestra; Mikhail Pletnev": "Tchaikovsky",
    "Michael Buble": "Michael Bublé",
    "Jackson 5": "The Jackson 5",
    "The 4 Seasons": "The Four Seasons",
}
# Chart extras take the year they first charted, which for old recordings
# that only re-entered in the streaming era is decades late.
YEAR = {
    ("Rudolph The Red-Nosed Reindeer", "Gene Autry"): "1949",
    ("Deck The Halls", "Nat King Cole"): "1960",
    ("Christmastime Is Here", "Vince Guaraldi Trio"): "1965",
    ("Santa Claus Is Comin' To Town", "Jackson 5"): "1970",
    ("Have Yourself A Merry Little Christmas", "Michael Buble"): "2011",
}


def short_artist(full):
    if full in SHORT:
        return SHORT[full]
    lead = full.split(";")[0].strip()
    return SUPPORT.sub("", lead).strip() or lead


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--max-peak", type=int, default=60)
    args = ap.parse_args()

    old = {}
    if os.path.exists(OUT):
        with open(OUT, newline="") as f:
            old = {(r["Title"], r["Full Artist"]): r for r in csv.DictReader(f)}

    rows, seen = [], []
    with open(SRC, newline="") as f:
        for r in csv.DictReader(f):
            rows.append({"Title": r["Title"], "Clean Title": r["Clean Title"],
                         "Full Artist": r["Artist(s)"], "Year": r["Year"],
                         "Peak (Hot 100)": r["Peak (Hot 100)"],
                         "Difficulty": r["Difficulty"]})
            seen.append((norm_title(r["Clean Title"]), artist_tokens(r["Artist(s)"])))

    extras = 0
    for s in sorted(B.collect(B.CACHE), key=lambda s: (s["peak"], s["first"])):
        if s["peak"] > args.max_peak or not B.is_holiday(s):
            continue
        t = norm_title(s["title"])
        if any(t == st and artists_match(s["toks"], sa) for st, sa in seen):
            continue
        rows.append({"Title": s["title"], "Clean Title": s["title"],
                     "Full Artist": s["performer"],
                     "Year": YEAR.get((s["title"], s["performer"]), s["first"][:4]),
                     "Peak (Hot 100)": s["peak"], "First Charted": s["first"],
                     "Peak Date": s["peak_week"], "Weeks on Chart": len(s["weeks"])})
        seen.append((t, s["toks"]))
        extras += 1

    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for n, r in enumerate(rows, 1):
            prev = old.get((r["Title"], r["Full Artist"]), {})
            row = {k: prev.get(k, "") for k in B.KEEP if k != "Difficulty"}
            row.update(r)
            row["#"] = n
            row["Artist(s)"] = short_artist(r["Full Artist"])
            w.writerow(row)
    print(f"{len(rows)} songs -> {OUT}  ({len(rows) - extras} curated + {extras} chart extras)")


if __name__ == "__main__":
    main()
