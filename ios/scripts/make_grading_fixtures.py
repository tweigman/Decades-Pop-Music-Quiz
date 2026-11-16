"""Record what the Python grader decides, so the Swift port can be checked
against it case for case.

Run from the repo root:  python3 ios/scripts/make_grading_fixtures.py
Writes ios/Packages/PopQuizCore/Tests/PopQuizCoreTests/Fixtures/grading.json
"""

from __future__ import annotations

import csv
import json
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from custom_components.popquiz import grading  # noqa: E402
from custom_components.popquiz.const import CATEGORY_ALIASES  # noqa: E402
from custom_components.popquiz.data import Song  # noqa: E402

OUT = REPO / "ios/Packages/PopQuizCore/Tests/PopQuizCoreTests/Fixtures/grading.json"


def load_songs() -> list[Song]:
    """Names to grade: the Spotify lists, and a sample of the chart lists.

    The app plays the chart lists (altcategories/), whose titles and credits
    are Billboard's wording, so the grader is checked against those too. One
    row in four keeps the fixture a reasonable size.
    """
    songs = []
    for path in sorted((REPO / "categories").glob("*.csv")):
        songs += read(path, every=1)
    for path in sorted((REPO / "altcategories").glob("[a-z]*.csv")):
        songs += read(path, every=4)
    return songs


def read(path: Path, every: int) -> list[Song]:
    songs = []
    with path.open(newline="", encoding="utf-8") as f:
        for n, row in enumerate(csv.DictReader(f)):
            if n % every:
                continue
            artists = tuple(a.strip() for a in row["Artist(s)"].split(";") if a.strip())
            title = row["Clean Title"].strip() or row["Title"].strip()
            if title and artists:
                songs.append(Song(title, artists, None, Path("x"), 30.0))
    return songs


def garble(text: str, rng: random.Random) -> str:
    """A plausible mis-hearing: drop, double or swap a letter or two."""
    chars = list(text)
    for _ in range(rng.randint(1, 2)):
        if len(chars) < 3:
            break
        i = rng.randrange(len(chars) - 1)
        op = rng.choice("dws")
        if op == "d":
            del chars[i]
        elif op == "w":
            chars.insert(i, chars[i])
        else:
            chars[i], chars[i + 1] = chars[i + 1], chars[i]
    return "".join(chars)


def utterances(song: Song, other: Song, rng: random.Random) -> list[str]:
    artist = song.artists[0]
    surname = artist.split()[-1]
    return [
        song.title,
        f"{song.title} by {artist}",
        f"I think it's {artist}, {song.title}",
        artist,
        surname,
        garble(song.title, rng),
        f"{garble(song.title, rng)} by {garble(artist, rng)}",
        f"{song.title} by {other.artists[0]}",
        other.title,
        song.title.split()[0],
        song.title.upper() + "!!!",
    ]


def main() -> None:
    rng = random.Random(42)
    songs = load_songs()
    grades = []
    for song in songs:
        other = rng.choice(songs)
        for said in utterances(song, other, rng):
            t, a = grading.grade(said, song)
            grades.append(
                {"said": said, "title": song.title, "artists": list(song.artists), "got": [t, a]}
            )

    names = [s.title for s in songs] + [a for s in songs for a in s.artists]
    normalize = [{"in": n, "out": grading.normalize(n)} for n in names]

    ratios = []
    for _ in range(3000):
        a, b = grading.normalize(rng.choice(names)), grading.normalize(rng.choice(names))
        if rng.random() < 0.3:
            b = garble(a, rng)
        ratios.append({"a": a, "b": b, "ratio": grading._ratio(a, b)})
    # Long strings exercise difflib's autojunk (only kicks in at 200+ chars).
    for _ in range(50):
        a = " ".join(grading.normalize(rng.choice(names)) for _ in range(20))
        b = " ".join(grading.normalize(rng.choice(names)) for _ in range(20))
        ratios.append({"a": a, "b": b, "ratio": grading._ratio(a, b)})

    commands = [
        "Exit game now.", "exit game", "quit the game", "End Game by Taylor Swift",
        "Skip.", "skip it", "Pass", "Pass the Dutchie", "I pass", "skipping",
        "Repeat!", "repeat that please", "play it again", "say that again", "Replay",
        "", "um", "one more time",
    ]
    command_results = [
        {"said": c, "exit": grading.is_exit(c), "skip": grading.is_skip(c),
         "repeat": grading.is_repeat(c)}
        for c in commands
    ]

    counts = ["Three.", "3 players", "Just me", "lots", "two", "to", "for of us",
              "twelve", "0", "we have 5", "Solo", "won", ""]
    count_results = [{"said": c, "count": grading.parse_player_count(c)} for c in counts]

    aliases = {c: grading.category_aliases(c, extra) for c, extra in CATEGORY_ALIASES.items()}
    cats = ["Eighties.", "the '80s", "Twenty tens", "the 2020s please", "classical",
            "sixties", "70s", "nineteen nineties", "the aughts", "noughties",
            "two thousands", "2000s", "twenty twenty", "the tens", "nineties please",
            "80", "the eighty's", "1960s"]
    category_results = [{"said": c, "category": grading.parse_category(c, aliases)} for c in cats]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "grades": grades,
        "normalize": normalize,
        "ratios": ratios,
        "commands": command_results,
        "counts": count_results,
        "categories": category_results,
    }, ensure_ascii=False))
    print(f"{len(grades)} grades, {len(normalize)} names, {len(ratios)} ratios -> {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
