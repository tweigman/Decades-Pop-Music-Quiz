"""Cut a clip out of a preview file with ffmpeg."""

from __future__ import annotations

import asyncio
import time
import uuid
from pathlib import Path

from .game import Clip

_MAX_AGE_SECONDS = 3600


async def render_clip(ffmpeg: str, clip: Clip, out_dir: Path) -> Path:
    """Write the clip to a new MP3 in out_dir, with short fades. Returns its path."""
    # File-system work runs in a thread: Home Assistant forbids blocking I/O
    # in its event loop.
    await asyncio.to_thread(_prepare_dir, out_dir)
    out = out_dir / f"{uuid.uuid4().hex}.mp3"
    fade = min(0.4, clip.duration / 4)
    proc = await asyncio.create_subprocess_exec(
        ffmpeg,
        "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{clip.offset:.2f}",
        "-t", f"{clip.duration:.2f}",
        "-i", str(clip.song.path),
        "-af", f"afade=t=in:d=0.1,afade=t=out:st={clip.duration - fade:.2f}:d={fade:.2f}",
        "-ac", "1", "-b:a", "128k",
        str(out),
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )  # fmt: skip
    _, err = await proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {err.decode(errors='replace').strip()}")
    return out


def _prepare_dir(out_dir: Path) -> None:
    """Create the clip folder and delete clips older than an hour."""
    out_dir.mkdir(parents=True, exist_ok=True)
    cutoff = time.time() - _MAX_AGE_SECONDS
    for old in out_dir.glob("*.mp3"):
        if old.stat().st_mtime < cutoff:
            old.unlink(missing_ok=True)
