#!/usr/bin/env python3
"""Spotify track URLs -> CSV of title / clean title / artist(s) / year.

    python3 spotify_to_csv.py 70s.txt 70s_tracks.csv

Uses public page metadata only: no API key, no OAuth, no subscription.

Pacing is the part that matters. An unthrottled run with 8 workers trips
Spotify's rate limiter at roughly 190 requests and then every subsequent
request 429s. So requests are spread across a global schedule (not per
worker), and a 429 from any worker pauses all of them. A full 260-track list
comes in under two minutes and, in practice, without tripping the limiter.

Re-running is cheap and safe: pass an existing CSV as the output and rows
that already have data are kept, so only the gaps get fetched.
"""

import csv
import os
import sys
import threading
import time
import urllib.error
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

from clean_titles import clean
from fetch_spotify_meta import from_embed, from_og

WORKERS = 4
MIN_INTERVAL = 0.35  # seconds between request starts, across all workers
MAX_ATTEMPTS = 5
FIELDS = [
    "#", "URL", "Title", "Clean Title", "Artist(s)", "Year",
    "Duration (ms)", "Preview URL",
]
# A row counts as done when these are filled. Preview URL is deliberately not
# required -- a small share of tracks genuinely have none, and demanding it
# would re-fetch those rows on every run.
REQUIRED = ["Title", "Artist(s)", "Year", "Duration (ms)"]


class Pacer:
    """Global request throttle with a shared 429 backoff.

    Workers reserve a slot on one timeline, so total throughput stays at
    1/MIN_INTERVAL regardless of worker count. A 429 pushes the timeline
    forward for everyone, which is what keeps a rate-limit stumble from
    cascading into 70 consecutive failures.
    """

    def __init__(self, min_interval):
        self.min_interval = min_interval
        self.lock = threading.Lock()
        self.next_slot = 0.0

    def wait(self):
        with self.lock:
            start = max(time.monotonic(), self.next_slot)
            self.next_slot = start + self.min_interval
        delay = start - time.monotonic()
        if delay > 0:
            time.sleep(delay)

    def backoff(self, seconds):
        with self.lock:
            self.next_slot = max(self.next_slot, time.monotonic() + seconds)
        print(f"    rate limited — pausing {seconds}s", flush=True)


def resolve(pacer, row):
    """Fill one row in place. Returns an error string, or '' on success."""
    track_id = row["URL"].rstrip("/").split("/")[-1].split("?")[0]
    last = "no metadata found"

    for attempt in range(MAX_ATTEMPTS):
        pacer.wait()
        try:
            got = from_embed(track_id) or from_og(track_id)
            if got and got["Title"]:
                row.update(got)
                row["Clean Title"] = clean(got["Title"])
                return ""
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                retry_after = int(exc.headers.get("Retry-After") or 0)
                pacer.backoff(retry_after or 30 * (attempt + 1))
                continue
            last = f"HTTP {exc.code}"
        except Exception as exc:  # noqa: BLE001 - retry anything transient
            last = f"{type(exc).__name__}: {exc}"
            time.sleep(2 * (attempt + 1))

    return last


def load(urls_path, csv_path):
    """Seed rows from the URL list, reusing any already-resolved CSV rows."""
    done = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="") as f:
            done = {
                r["URL"]: r
                for r in csv.DictReader(f)
                if all(r.get(k) for k in REQUIRED)
            }

    # Source may be a raw URL list, or an already-curated CSV. Passing the CSV
    # as both input and output refreshes it in place without resurrecting rows
    # that were deliberately removed from it.
    if urls_path.lower().endswith(".csv"):
        with open(urls_path, newline="") as f:
            urls = [r["URL"] for r in csv.DictReader(f)]
    else:
        with open(urls_path) as f:
            urls = [
                ln.strip().split()[0]
                for ln in f
                if ln.strip() and not ln.startswith("#")
            ]

    rows = []
    for i, url in enumerate(urls, 1):
        prev = done.get(url)
        row = {k: "" for k in FIELDS}
        row["#"], row["URL"] = i, url
        if prev:
            row.update({k: prev.get(k, "") for k in FIELDS[2:]})
        rows.append(row)
    return rows


def report(rows):
    """Flag the things worth a human look: collisions and cross-decade strays."""
    dupes = [t for t, c in Counter(r["Clean Title"].lower() for r in rows if r["Title"]).items() if c > 1]
    if dupes:
        print(f"\n{len(dupes)} title(s) appear more than once — pick one of each:")
        for t in dupes:
            for r in (r for r in rows if r["Clean Title"].lower() == t):
                print(f"  #{r['#']:>3}  {r['Clean Title']:<34} — {r['Artist(s)'][:30]:<30} ({r['Year']})")
            print()

    print("Year spread (Spotify release date, NOT necessarily chart year):")
    for dec, n in sorted(Counter(r["Year"][:3] + "0s" for r in rows if r["Year"]).items()):
        print(f"  {dec}  {n:>3}")


def main(urls_path, csv_path):
    rows = load(urls_path, csv_path)
    todo = [r for r in rows if not r["Title"]]
    print(f"{len(rows)} urls, {len(rows) - len(todo)} already resolved, fetching {len(todo)}")

    pacer = Pacer(MIN_INTERVAL)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        errors = list(pool.map(lambda r: resolve(pacer, r), todo))

    for n, r in enumerate(rows, 1):
        r["#"] = n
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    failed = [(r, e) for r, e in zip(todo, errors) if e]
    print(f"\n{len(rows) - len(failed)}/{len(rows)} resolved -> {csv_path}")
    for r, e in failed:
        print(f"  UNRESOLVED #{r['#']}: {r['URL']} ({e})", file=sys.stderr)
    if failed:
        print("  re-run the same command to retry just these", file=sys.stderr)

    report(rows)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
