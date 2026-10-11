#!/usr/bin/env python3
r"""Spotify track URL list -> CSV of Song / Artist / Album / URL. Resumable.

    python3 liked_to_csv.py ~/Music/Liked\ Songs.txt ~/Music/Liked\ Songs.csv

Song and artists come from the embed page (fetch_spotify_meta.from_embed); the
album name is not in the embed blob, so it is scraped from the full track page.
Pacing mirrors spotify_to_csv.py. Re-running fills only rows with gaps.
"""
import csv, html as H, os, re, sys, threading, time, urllib.error
from concurrent.futures import ThreadPoolExecutor
from fetch_spotify_meta import from_embed
import urllib.request

FIELDS = ["Song", "Artist", "Album", "URL"]
ALBUM_META = re.compile(r'music:album" content="https://open\.spotify\.com/album/([A-Za-z0-9]+)')
SUFFIX = re.compile(r'(Album|Single|EP|Compilation)\s*•\s*\d{4}$')

def get_plain(url):
    # The full track page only server-renders for non-browser UAs.
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", "replace")

def album_of(tid):
    h = get_plain(f"https://open.spotify.com/track/{tid}")
    m = ALBUM_META.search(h)
    if not m:
        return None
    for a in re.finditer(r'href="/album/' + m.group(1) + r'"[^>]*>(.*?)</a>', h, re.S):
        t = H.unescape(re.sub(r"<[^>]+>", "", a.group(1))).strip()
        t = SUFFIX.sub("", t).strip()
        if t:
            return t
    return None

class Pacer:
    def __init__(s, iv): s.iv, s.lock, s.next = iv, threading.Lock(), 0.0
    def wait(s):
        with s.lock:
            start = max(time.monotonic(), s.next); s.next = start + s.iv
        d = start - time.monotonic()
        if d > 0: time.sleep(d)
    def backoff(s, sec):
        with s.lock: s.next = max(s.next, time.monotonic() + sec)
        print(f"    rate limited — pausing {sec}s", flush=True)

def tid_of(url): return url.rstrip("/").split("/")[-1].split("?")[0]

def call(pacer, fn, *a):
    last = "failed"
    for attempt in range(5):
        pacer.wait()
        try:
            return fn(*a), ""
        except urllib.error.HTTPError as e:
            if e.code == 429:
                pacer.backoff(int(e.headers.get("Retry-After") or 0) or 30 * (attempt + 1)); continue
            last = f"HTTP {e.code}"
        except Exception as e:
            last = f"{type(e).__name__}: {e}"; time.sleep(2 * (attempt + 1))
    return None, last

done_count = 0
def resolve(pacer, row):
    global done_count
    tid, errs = tid_of(row["URL"]), []
    if not row["Song"]:
        got, err = call(pacer, from_embed, tid)
        if got:
            row["Song"] = got["Title"]; row["Artist"] = got["Artist(s)"]
        else: errs.append(err or "no embed data")
    if not row["Album"]:
        alb, err = call(pacer, album_of, tid)
        if alb: row["Album"] = alb
        else: errs.append(err or "no album found")
    done_count += 1
    if done_count % 100 == 0: print(f"  {done_count} done", flush=True)
    return "; ".join(errs)

def main(src, out):
    prev = {}
    if os.path.exists(out):
        with open(out, newline="", encoding="utf-8-sig") as f:
            prev = {r["URL"]: r for r in csv.DictReader(f)}
    seen, rows = set(), []
    for ln in open(src):
        url = ln.strip()
        if not url: continue
        t = tid_of(url)
        if t in seen: continue
        seen.add(t)
        r = {k: "" for k in FIELDS}; r["URL"] = url
        r.update({k: v for k, v in prev.get(url, {}).items() if k in FIELDS and v})
        rows.append(r)
    todo = [r for r in rows if not (r["Song"] and r["Album"])]
    print(f"{len(rows)} tracks, fetching {len(todo)}", flush=True)
    pacer = Pacer(0.35)
    try:
        with ThreadPoolExecutor(4) as pool:
            errs = list(pool.map(lambda r: resolve(pacer, r), todo))
    finally:
        with open(out, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS); w.writeheader(); w.writerows(rows)
    bad = [(r["URL"], e) for r, e in zip(todo, errs) if e]
    print(f"{len(rows) - len(bad)}/{len(rows)} complete -> {out}")
    for u, e in bad: print(" ", u, e)

main(sys.argv[1], sys.argv[2])
