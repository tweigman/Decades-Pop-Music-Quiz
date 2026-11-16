#!/usr/bin/env python3
"""Fill altcategories/*.csv with 30-second previews from Apple.

    python3 fetch_apple_previews.py                         # every alt category
    python3 fetch_apple_previews.py altcategories/eighties.csv
    python3 fetch_apple_previews.py --limit 40              # first 40 unfilled rows per file
    python3 fetch_apple_previews.py --retry                 # redo 'none' and 'check' rows
    python3 fetch_apple_previews.py --ignore-year altcategories/holiday.csv

Uses the iTunes Search API: no key, but rate-limited to roughly 20 searches
a minute, so a full run takes hours. It is resumable: progress is saved every
few rows and rows that already have a Match value are skipped.

For each song it fills URL, Duration (ms) and Preview URL, and records what
Apple called the track so a wrong match is easy to spot:

    Match = ok      title and artist agree, original-looking recording
    Match = check   best candidate is doubtful (live, re-recording, loose title
                    or artist)
    Match = none    nothing usable found
"""

import argparse
import csv
import difflib
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from add_chart_peaks import PAREN, SPLIT, artist_tokens, artists_match, fold, norm_title
from build_alt_categories import FIELDS

API = "https://itunes.apple.com/search"
GLOB = os.path.join("altcategories", "[a-z]*.csv")
# Words in Apple's track or album name that mean "not the hit single".
BAD = re.compile(r"\b(live|karaoke|tribute|re-?record(?:ed|ing)?|remix|instrumental|"
                 r"acoustic|demo|made famous|cover|rehearsal|session|medley|"
                 r"in the style of|originally performed|backing track|"
                 r"sped up|slowed|mix)\b", re.I)
NUM = {"part": "pt", "ii": "2", "iii": "3", "two": "2", "one": "1", "i": "1"}

delay = 1.5  # seconds between searches; raised automatically if Apple objects
ignore_year = False  # holiday standards: the row's year says little about the recording


def words(s):
    """Title as comparable words, parentheticals kept: 'Pt. 2' == '(Part II)'."""
    s = re.sub(r"[^a-z0-9\s]", " ", re.sub(r"[.'’`*!]", "", fold(s)))
    return [NUM.get(w, w) for w in s.split() if w not in ("the", "a", "an")]


def title_score(want, got):
    """0..1 similarity, trying the titles with and without parentheticals."""
    best = 0.0
    for a in {" ".join(words(want)), norm_title(want)}:
        # Apple files medleys whole: 'LoveStoned / I Think She Knows'.
        for b in {" ".join(words(got)), norm_title(got), norm_title(got.split(" / ")[0])}:
            if a and b:
                best = max(best, difflib.SequenceMatcher(None, a, b).ratio())
    return best


def same_artist(want, got):
    """Stricter than artists_match, which accepts one shared first name.

    'Greg Guidry' is not 'Greg Koch'. Most of the shorter credit must agree,
    or the names must be near-identical spellings ('Rick' / 'Ricky Nelson').
    """
    a, b = artist_tokens(want), artist_tokens(got)
    if a and b and len(a & b) / min(len(a), len(b)) >= 0.67:
        return True
    return difflib.SequenceMatcher(None, fold(want), fold(got)).ratio() >= 0.75


def search(term):
    global delay
    url = API + "?" + urllib.parse.urlencode(
        {"term": term, "entity": "song", "country": "US", "limit": 25})
    for attempt in range(6):
        time.sleep(delay)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp).get("results", [])
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                delay = min(delay + 0.8, 4.0)
                print(f"   rate limited; pausing 60s, spacing now {delay:.1f}s", flush=True)
                time.sleep(60)
            else:
                time.sleep(10)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            time.sleep(10)
    return None  # gave up; leave the row for the next run


def pick(row, results):
    """Best candidate as (score, flags, result), or None."""
    want_title = (row.get("Clean Title") or row["Title"]).split("/")[0]
    want_art = artist_tokens(row["Artist(s)"])
    year = int(row["Year"] or 0)
    best = None
    for r in results:
        if not r.get("previewUrl") or r.get("kind") != "song":
            continue
        if not artists_match(want_art, artist_tokens(r.get("artistName", ""))):
            continue
        ts = title_score(want_title, r.get("trackName", ""))
        if ts < 0.6:
            continue
        label = r.get("trackName", "") + " " + r.get("collectionName", "")
        bad = bool(BAD.search(label)) and not BAD.search(row["Title"])
        try:
            gap = abs(int(r.get("releaseDate", "")[:4]) - year)
        except ValueError:
            gap = 99
        if ignore_year:
            gap = 0
        sure = same_artist(row["Artist(s)"], r.get("artistName", ""))
        score = (ts - (0.5 if bad else 0) - (0 if sure else 0.4)
                 + (0.1 if gap <= 2 else 0.05 if gap <= 5 else 0))
        if best is None or score > best[0]:
            best = (score, ts, bad or not sure, gap, r)
    return best


def lookup(row):
    """Fill one row in place. Returns False if the search itself failed."""
    name = row.get("Clean Title") or row["Title"]
    title = PAREN.sub(" ", name.split("/")[0]).strip() or name
    lead = SPLIT.split(row["Artist(s)"])[0].strip()
    best = None
    for term in (f"{title} {lead}", f"{name} {row['Artist(s)']}", title):
        results = search(term)
        if results is None:
            return False
        cand = pick(row, results)
        if cand and (best is None or cand[0] > best[0]):
            best = cand
        if best and best[1] >= 0.85 and not best[2]:
            break
    if not best:
        row["Match"] = "none"
        return True
    _, ts, bad, gap, r = best
    row["URL"] = r.get("trackViewUrl", "")
    row["Duration (ms)"] = r.get("trackTimeMillis", "")
    row["Preview URL"] = r["previewUrl"]
    row["Apple Title"] = r.get("trackName", "")
    row["Apple Artist"] = r.get("artistName", "")
    row["Match"] = "ok" if ts >= 0.85 and not bad and gap <= 5 else "check"
    return True


def save(path, rows, fields=FIELDS):
    tmp = path + ".tmp"
    with open(tmp, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--limit", type=int, help="stop after this many lookups per file")
    ap.add_argument("--retry", action="store_true", help="redo 'none' and 'check' rows")
    ap.add_argument("--ignore-year", action="store_true",
                    help="don't flag a match because its release year differs")
    args = ap.parse_args()
    global ignore_year
    ignore_year = args.ignore_year

    for path in args.paths or sorted(glob.glob(GLOB)):
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        # Keep the file's own columns (holiday has 'Full Artist').
        fields = reader.fieldnames + [c for c in FIELDS if c not in reader.fieldnames]
        todo = [r for r in rows if not r.get("Match")
                or (args.retry and r["Match"] in ("none", "check"))]
        if args.limit:
            todo = todo[:args.limit]
        print(f"{os.path.basename(path)}: {len(todo)} to look up", flush=True)
        for i, r in enumerate(todo, 1):
            if not lookup(r):
                print("   search failed repeatedly; stopping. Re-run to resume.")
                save(path, rows, fields)
                sys.exit(1)
            if i % 20 == 0 or i == len(todo):
                save(path, rows, fields)
                print(f"   {i}/{len(todo)}", flush=True)
        tally = {k: sum(1 for r in rows if r.get("Match") == k) for k in ("ok", "check", "none")}
        print(f"   ok {tally['ok']}  check {tally['check']}  none {tally['none']}  "
              f"pending {sum(1 for r in rows if not r.get('Match'))}", flush=True)


if __name__ == "__main__":
    main()
