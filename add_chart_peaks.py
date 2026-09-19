#!/usr/bin/env python3
"""Add a 'Peak (Hot 100)' column to the category CSVs.

    python3 add_chart_peaks.py                      # every categories/*.csv
    python3 add_chart_peaks.py categories/holiday.csv    # just one category

Source is the public Billboard Hot 100 archive (every weekly chart since
1958). We collapse it to the best peak per song, then join by title+artist.

Matching is the hard part: Spotify writes 'Marvin Gaye; Tammi Terrell' where
Billboard writes 'Marvin Gaye & Tammi Terrell', and titles differ in
punctuation, articles and featured-artist credits. So both sides are
normalised to token sets and matched on overlap rather than equality.

A blank peak means 'no Hot 100 entry found', which is itself meaningful --
the chart is US-only, so UK/European hits legitimately have none.
"""

import csv
import glob
import os
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict

HOT100_URL = "https://raw.githubusercontent.com/utdata/rwd-billboard-data/main/data-out/hot-100-current.csv"
CACHE = "hot-100-current.csv"
CATEGORY_GLOB = os.path.join("categories", "*.csv")
FIELDS = ["#", "URL", "Title", "Clean Title", "Artist(s)", "Year",
          "Duration (ms)", "MP3 File", "Preview URL", "Peak (Hot 100)"]

# Credit joiners and noise that the two sources disagree about.
SPLIT = re.compile(r"\s*(?:;|&|\+|/|,|\bfeat\.?\b|\bfeaturing\b|\bwith\b|\bx\b|\band\b|\bduet\b|\bvs\.?\b)\s*", re.I)
PAREN = re.compile(r"\([^)]*\)|\[[^\]]*\]")
NONWORD = re.compile(r"[^a-z0-9\s]")
# Punctuation that sits *inside* a word. Deleting rather than space-replacing
# keeps 'O.A.R.' -> 'oar', 'Ke$ha' -> 'kesha', '3OH!3' -> '3oh3'. Splitting on
# these instead produced tokens too short to survive filtering, which silently
# dropped every artist written with initials.
INWORD = re.compile(r"[.'’`*!]")
# '$' is a letter substitution, not punctuation: Ke$ha and A$AP mean 's'.
# Deleting it yields 'keha', which matches nothing.
LEET = {"$": "s"}
STOP = {"the", "a", "an", "of", "and", "his", "her", "their", "orchestra", "band", "group"}


def fold(s):
    """Lowercase, strip accents, undo letter substitutions."""
    s = unicodedata.normalize("NFKD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return "".join(LEET.get(c, c) for c in s)


def norm_title(s):
    s = PAREN.sub(" ", fold(s))
    s = re.sub(r"\s+-\s+.*$", "", s)  # trailing '- Single Version' etc.
    s = NONWORD.sub(" ", INWORD.sub("", s))
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"^(the|a|an) ", "", s)


def artist_tokens(s):
    """Significant word tokens across all credited artists."""
    out = set()
    for part in SPLIT.split(fold(s)):
        for tok in NONWORD.sub(" ", INWORD.sub("", part)).split():
            if tok not in STOP and len(tok) > 1:
                out.add(tok)
    return out


def artists_match(a, b):
    if not a or not b:
        return False
    overlap = len(a & b)
    # One credited name in common is enough: Billboard often lists only the
    # lead artist where Spotify lists the full collaboration, and vice versa.
    return overlap / min(len(a), len(b)) >= 0.5 or overlap >= 2


def load_hot100(path):
    if not os.path.exists(path):
        print(f"downloading Hot 100 archive -> {path}")
        urllib.request.urlretrieve(HOT100_URL, path)

    best = defaultdict(lambda: (999, None))  # norm title -> (peak, artist tokens)
    index = defaultdict(list)
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for r in csv.DictReader(f):
            try:
                peak = int(r["peak_pos"])
            except (ValueError, KeyError):
                continue
            t = norm_title(r["title"])
            toks = artist_tokens(r["performer"])
            key = (t, frozenset(toks))
            cur = best[key]
            if peak < cur[0]:
                best[key] = (peak, toks)

    for (t, _), (peak, toks) in best.items():
        index[t].append((peak, toks))
    return index


def lookup(index, title, artists):
    cands = index.get(norm_title(title))
    if not cands:
        return ""
    mine = artist_tokens(artists)
    hits = [peak for peak, toks in cands if artists_match(mine, toks)]
    return min(hits) if hits else ""


def main(paths):
    index = load_hot100(CACHE)
    print(f"{len(index)} distinct charted titles loaded\n")

    grand = [0, 0]
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        rows = list(csv.DictReader(open(path, newline="")))
        for r in rows:
            r["Peak (Hot 100)"] = lookup(index, r["Clean Title"], r["Artist(s)"])
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)

        got = sum(1 for r in rows if r["Peak (Hot 100)"] != "")
        grand[0] += got
        grand[1] += len(rows)
        print(f"{name:>16}: {got:>3}/{len(rows):<3} matched ({100 * got / len(rows):.0f}%)")

    print(f"\nTOTAL: {grand[0]}/{grand[1]} ({100 * grand[0] / grand[1]:.0f}%)")


if __name__ == "__main__":
    main(sys.argv[1:] or sorted(glob.glob(CATEGORY_GLOB)))
