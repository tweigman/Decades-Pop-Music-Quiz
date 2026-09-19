#!/usr/bin/env python3
"""Track metadata from Spotify's public pages. No API key, no OAuth.

Two sources, in preference order:

  from_embed  the /embed/track/ page ships a __NEXT_DATA__ JSON blob with the
              full artist array, duration and preview URL -- everything we want
  from_og     the regular track page's og: meta tags; a thinner fallback used
              only when the embed blob is missing or changes shape

Both return a dict keyed to match the CSV columns, or None.
This is a module -- see spotify_to_csv.py for the entry point.
"""

import html as htmllib
import json
import re
import urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
NEXT_DATA = re.compile(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', re.S
)
OG = re.compile(r'<meta property="og:(title|description)" content="([^"]*)"')


def get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def from_embed(track_id):
    html = get(f"https://open.spotify.com/embed/track/{track_id}")
    m = NEXT_DATA.search(html)
    if not m:
        return None
    entity = json.loads(m.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
    iso = (entity.get("releaseDate") or {}).get("isoString") or ""
    return {
        "Title": entity.get("name", ""),
        "Artist(s)": "; ".join(a["name"] for a in entity.get("artists", [])),
        "Year": iso[:4],
        "Duration (ms)": entity.get("duration") or "",
        # Spotify picks this clip to be the hook. Length varies: usually ~30s,
        # occasionally as short as 15s. Absent for roughly 1% of tracks.
        "Preview URL": (entity.get("audioPreview") or {}).get("url") or "",
    }


def from_og(track_id):
    """og:description is 'Artist · Title · Song · Year'. No duration or preview."""
    html = get(f"https://open.spotify.com/track/{track_id}")
    tags = {k: htmllib.unescape(v) for k, v in OG.findall(html)}
    parts = [p.strip() for p in tags.get("description", "").split("·")]
    year = parts[-1] if parts and re.fullmatch(r"\d{4}", parts[-1]) else ""
    return {
        "Title": tags.get("title", ""),
        "Artist(s)": parts[0] if parts else "",
        "Year": year,
        "Duration (ms)": "",
        "Preview URL": "",
    }
