#!/usr/bin/env python3
"""Find where the singing is in each preview clip.

    .venv-audio/bin/python detect_lyrics.py                      # every alt category
    .venv-audio/bin/python detect_lyrics.py altcategories/eighties.csv
    .venv-audio/bin/python detect_lyrics.py --limit 20           # first 20 unanalysed clips per file
    .venv-audio/bin/python detect_lyrics.py --merge              # copy results into the category CSVs

Each clip is downloaded to a temp file, split into vocals and accompaniment
with Demucs, measured, and deleted: only the timings are kept. A vocal frame
is one where the isolated vocal stem is both audible and a real share of the
mix. Frames are then smoothed into segments.

Results go to altcategories/_lyrics.csv, keyed by preview URL, so this can
run while other scripts are rewriting the category CSVs. --merge then adds:

    Preview (s)        measured clip length
    Lyrics Start (s)   start of the first vocal stretch lasting MIN_RUN seconds
                       or more; blank if there is none
    Vocal Segments     every vocal stretch, e.g. '4.2-11.8;14.0-30.0'
    Vocal %            share of the clip with vocals (0 = instrumental)

This detects singing, not words: a long 'ooh' counts as vocals.

Needs its own environment (torch + demucs), kept out of the main scripts:
    uv venv --python 3.12 .venv-audio
    uv pip install --python .venv-audio/bin/python torch torchaudio demucs numpy
(torch 2.5 cannot run this model on the Mac GPU and is ~6x slower; 2.15 can.)
"""

import argparse
import csv
import glob
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

OUT = os.path.join("altcategories", "_lyrics.csv")
GLOB = os.path.join("altcategories", "[a-z]*.csv")
OUT_FIELDS = ["Preview URL", "Preview (s)", "Lyrics Start (s)", "Vocal Segments", "Vocal %"]
NEW_COLUMNS = OUT_FIELDS[1:]

HOP = 0.05          # seconds per analysis frame
MIN_DB = -38.0      # vocal stem must be at least this loud (dBFS) ...
MIN_SHARE = 0.30    # ... and at least this fraction of the mix's amplitude
SMOOTH = 0.35       # seconds of smoothing applied before thresholding
MAX_GAP = 1.2       # bridge silences shorter than this (breaths, line breaks)
MIN_SEG = 1.0       # drop vocal blips shorter than this
MIN_RUN = 3.0       # 'the lyrics start' needs vocals to carry on this long


def load_model():
    import torch
    from demucs.pretrained import get_model
    model = get_model("htdemucs")
    model.eval()
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    return model, device


def decode(path, rate):
    """Any audio file -> float32 stereo tensor (2, n) at the model's rate."""
    import numpy as np
    import torch
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2",
         "-ar", str(rate), "-"], capture_output=True, check=True).stdout
    return torch.from_numpy(np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.copy())


def vocal_segments(model, device, wav):
    """[(start, end), ...] in seconds, plus the clip length."""
    import numpy as np
    import torch
    from demucs.apply import apply_model

    ref = wav.mean(0)
    mean, std = ref.mean(), ref.std() + 1e-8
    with torch.no_grad():
        try:
            out = apply_model(model, ((wav - mean) / std)[None], device=device, shifts=0)[0]
        except RuntimeError:
            out = apply_model(model, ((wav - mean) / std)[None], device="cpu", shifts=0)[0]
    vocals = (out[model.sources.index("vocals")] * std + mean).cpu().numpy().mean(0)
    mix = wav.numpy().mean(0)

    hop = int(model.samplerate * HOP)
    n = len(mix) // hop
    def rms(x):
        return np.sqrt((x[:n * hop].reshape(n, hop) ** 2).mean(1) + 1e-12)
    k = max(1, int(SMOOTH / HOP))
    kernel = np.ones(k) / k
    v = np.convolve(rms(vocals), kernel, mode="same")
    m = np.convolve(rms(mix), kernel, mode="same")
    active = (20 * np.log10(v) > MIN_DB) & (v > MIN_SHARE * m)

    segs, start = [], None
    for i, on in enumerate(list(active) + [False]):
        if on and start is None:
            start = i
        elif not on and start is not None:
            segs.append([start * HOP, i * HOP])
            start = None
    merged = []
    for s in segs:
        if merged and s[0] - merged[-1][1] <= MAX_GAP:
            merged[-1][1] = s[1]
        else:
            merged.append(s)
    return [(a, b) for a, b in merged if b - a >= MIN_SEG], n * HOP


def analyse(model, device, url):
    with tempfile.NamedTemporaryFile(suffix=".m4a") as tmp:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            tmp.write(resp.read())
        tmp.flush()
        wav = decode(tmp.name, model.samplerate)
    segs, length = vocal_segments(model, device, wav)
    start = next((a for a, b in segs if b - a >= MIN_RUN), None)
    return {"Preview URL": url,
            "Preview (s)": f"{length:.1f}",
            "Lyrics Start (s)": "" if start is None else f"{start:.1f}",
            "Vocal Segments": ";".join(f"{a:.1f}-{b:.1f}" for a, b in segs),
            "Vocal %": f"{100 * sum(b - a for a, b in segs) / length:.0f}" if length else ""}


def load_results():
    if not os.path.exists(OUT):
        return {}
    with open(OUT, newline="") as f:
        return {r["Preview URL"]: r for r in csv.DictReader(f)}


def run(paths, limit):
    done = load_results()
    model, device = load_model()
    print(f"model loaded, running on {device}", flush=True)
    new_file = not os.path.exists(OUT)
    with open(OUT, "a", newline="") as out:
        w = csv.DictWriter(out, fieldnames=OUT_FIELDS)
        if new_file:
            w.writeheader()
        for path in paths:
            with open(path, newline="") as f:
                todo = [r for r in csv.DictReader(f)
                        if r.get("Preview URL") and r["Preview URL"] not in done]
            if limit:
                todo = todo[:limit]
            print(f"{os.path.basename(path)}: {len(todo)} clips to analyse", flush=True)
            t0 = time.time()
            for i, r in enumerate(todo, 1):
                try:
                    res = analyse(model, device, r["Preview URL"])
                except Exception as e:  # one bad clip must not end an overnight run
                    print(f"   skipped {r['Title']}: {e}", flush=True)
                    continue
                done[res["Preview URL"]] = res
                w.writerow(res)
                out.flush()
                if i % 10 == 0 or i == len(todo):
                    print(f"   {i}/{len(todo)}  ({(time.time() - t0) / i:.1f}s per clip)", flush=True)


def merge(paths):
    from build_alt_categories import FIELDS
    done = load_results()
    for path in paths:
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        # Keep the file's own columns (holiday has 'Full Artist').
        fields = reader.fieldnames + [c for c in FIELDS if c not in reader.fieldnames]
        hit = 0
        for r in rows:
            res = done.get(r.get("Preview URL", ""))
            for col in NEW_COLUMNS:
                r[col] = res[col] if res else r.get(col, "")
            hit += bool(res)
        tmp = path + ".tmp"
        with open(tmp, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
        os.replace(tmp, path)
        print(f"{os.path.basename(path)}: {hit}/{len(rows)} rows have timings")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--limit", type=int, help="stop after this many clips per file")
    ap.add_argument("--merge", action="store_true",
                    help="copy results from _lyrics.csv into the category CSVs")
    args = ap.parse_args()
    paths = args.paths or sorted(glob.glob(GLOB))
    if args.merge:
        merge(paths)
    else:
        run(paths, args.limit)


if __name__ == "__main__":
    main()
