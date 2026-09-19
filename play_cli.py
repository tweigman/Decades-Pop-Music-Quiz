"""Play Pop Quiz in the terminal, typing instead of talking.

    python3 play_cli.py            # plays clips through the Mac speakers
    python3 play_cli.py --silent   # text only, shows the answer instead

Uses the same game engine as the Home Assistant integration.
"""

import argparse
import asyncio
import shutil
import subprocess
import tempfile
from pathlib import Path

from custom_components.popquiz.clips import render_clip
from custom_components.popquiz.const import BONUS_INTRO_FILE
from custom_components.popquiz.data import Library
from custom_components.popquiz.game import Game

REPO = Path(__file__).resolve().parent


def play(path: Path) -> None:
    subprocess.run(["afplay", str(path)], check=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--silent", action="store_true")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    audio = not args.silent and ffmpeg and shutil.which("afplay")
    bonus_intro = REPO / BONUS_INTRO_FILE
    tmp = Path(tempfile.mkdtemp(prefix="popquiz-"))

    game = Game(Library(REPO))
    reply = game.start()
    while True:
        print(f"\nQUIZ: {reply.speech}")
        if reply.clip:
            if reply.bonus_intro and audio and bonus_intro.exists():
                play(bonus_intro)
            if audio:
                play(asyncio.run(render_clip(ffmpeg, reply.clip, tmp)))
            else:
                s = reply.clip.song
                print(f"      [clip: {s.title} / {s.artist_display}, peak {s.peak}]")
        if reply.done:
            break
        reply = game.handle(input("YOU:  "))
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
