"""Play Pop Quiz in the terminal, typing instead of talking.

    python3 play_cli.py            # plays clips through the Mac speakers
    python3 play_cli.py --speak    # ...and reads the quizmaster's lines aloud
    python3 play_cli.py --silent   # text only, shows the answer instead

--speak uses the macOS voice from System Settings > Accessibility > Spoken
Content unless --voice is given (list voices with: say -v '?'). Premium and
Enhanced voices, downloadable there, sound much better than the defaults.

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


def speak(text: str, voice: str | None, rate: int | None) -> None:
    cmd = ["say"]
    if voice:
        cmd += ["-v", voice]
    if rate:
        cmd += ["-r", str(rate)]
    subprocess.run([*cmd, text], check=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Play Pop Quiz in the terminal.")
    parser.add_argument("--silent", action="store_true", help="don't play clips")
    parser.add_argument("--speak", action="store_true", help="read lines aloud")
    parser.add_argument("--voice", help="macOS voice name, e.g. Samantha")
    parser.add_argument("--rate", type=int, help="speaking rate, words per minute")
    args = parser.parse_args()
    if args.speak and not shutil.which("say"):
        parser.error("--speak needs the macOS 'say' command")
    if args.voice:
        voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True)
        if not any(line.startswith(args.voice) for line in voices.stdout.splitlines()):
            parser.error(f"no voice named {args.voice!r}; list them with: say -v '?'")
    ffmpeg = shutil.which("ffmpeg")
    audio = not args.silent and ffmpeg and shutil.which("afplay")
    bonus_intro = REPO / BONUS_INTRO_FILE
    tmp = Path(tempfile.mkdtemp(prefix="popquiz-"))

    game = Game(Library(REPO))
    reply = game.start()
    while True:
        print(f"\nQUIZ: {reply.speech}")
        if args.speak:
            speak(reply.speech, args.voice, args.rate)
        if reply.clip:
            if reply.bonus_speech:
                if audio and bonus_intro.exists():
                    play(bonus_intro)
                print(f"\nQUIZ: {reply.bonus_speech}")
                if args.speak:
                    speak(reply.bonus_speech, args.voice, args.rate)
            if audio:
                play(asyncio.run(render_clip(ffmpeg, reply.clip, tmp)))
            else:
                s = reply.clip.song
                print(f"      [clip: {s.title} / {s.artist_display}, peak {s.peak}]")
        if reply.done:
            break
        try:
            said = input("YOU:  ")
        except (EOFError, KeyboardInterrupt):
            print()
            break
        reply = game.handle(said)
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
