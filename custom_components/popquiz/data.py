"""Load the song library from the category CSVs and the preview index."""

from __future__ import annotations

import csv
import logging
from dataclasses import dataclass
from pathlib import Path

from .const import (
    CATEGORIES_DIR,
    CATEGORY_ALIASES,
    DIFFICULT,
    EASY,
    EASY_MAX_PEAK,
    HARDER,
    HARDER_MAX_PEAK,
    PREVIEWS_INDEX,
)

_LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class Song:
    title: str
    artists: tuple[str, ...]
    peak: int | None  # None when the song never matched a Hot 100 entry
    path: Path
    length: float  # seconds of audio in the preview file

    @property
    def artist_display(self) -> str:
        return " and ".join(self.artists)


def difficulty(peak: int | None) -> str:
    if peak is None:
        return DIFFICULT
    if peak <= EASY_MAX_PEAK:
        return EASY
    if peak <= HARDER_MAX_PEAK:
        return HARDER
    return DIFFICULT


class Library:
    """All playable songs, grouped by category (CSV file name)."""

    def __init__(self, data_dir: Path | str) -> None:
        data_dir = Path(data_dir)
        lengths = _load_lengths(data_dir / PREVIEWS_INDEX)
        self.categories: dict[str, list[Song]] = {}
        # Known categories in CATEGORY_ALIASES order (chronological), then the rest.
        order = list(CATEGORY_ALIASES)
        paths = sorted(
            (data_dir / CATEGORIES_DIR).glob("*.csv"),
            key=lambda p: (order.index(p.stem) if p.stem in order else len(order), p.stem),
        )
        self.skipped: dict[str, str] = {}
        for csv_path in paths:
            songs = _load_category(csv_path, data_dir / "previews", lengths)
            if songs:
                self.categories[csv_path.stem] = songs
            else:
                # A category part-way through the pipeline (metadata written but
                # clips not downloaded yet) has no playable songs. Dropping it is
                # right -- doing so silently is not, so say why.
                self.skipped[csv_path.stem] = (
                    "no playable songs: run download_previews.py "
                    f"on {csv_path.as_posix()}"
                )
                _LOGGER.warning("Pop Quiz: skipping %s — %s",
                                csv_path.stem, self.skipped[csv_path.stem])

    def songs(self, category: str, level: str) -> list[Song]:
        return [s for s in self.categories[category] if difficulty(s.peak) == level]


def _load_lengths(index_path: Path) -> dict[str, float]:
    with index_path.open(newline="", encoding="utf-8") as f:
        return {
            Path(row["File"]).name: float(row["Preview (s)"])
            for row in csv.DictReader(f)
            if row.get("Preview (s)")
        }


def _load_category(
    csv_path: Path, previews_dir: Path, lengths: dict[str, float]
) -> list[Song]:
    songs = []
    with csv_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            mp3 = row.get("MP3 File", "").strip()
            peak = row.get("Peak (Hot 100)", "").strip()
            path = previews_dir / mp3
            if not mp3 or mp3 not in lengths or not path.is_file():
                continue
            songs.append(
                Song(
                    title=row["Clean Title"].strip() or row["Title"].strip(),
                    artists=tuple(
                        a.strip() for a in row["Artist(s)"].split(";") if a.strip()
                    ),
                    peak=int(float(peak)) if peak else None,
                    path=path,
                    length=lengths[mp3],
                )
            )
    return songs
