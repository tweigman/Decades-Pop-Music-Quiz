"""Understanding what the player said: answers, commands, numbers, categories.

Everything works on text from speech-to-text, so matching is forgiving:
case, punctuation, accents, digits-vs-words and small misspellings are
ignored. Names are matched against word-aligned windows of the utterance, so
"imagine by john lennon" matches both "Imagine" and "John Lennon", but
"imagination" does not match "Imagine".
"""

from __future__ import annotations

import re
import unicodedata
from difflib import SequenceMatcher

from .const import (
    ARTIST_MATCH_THRESHOLD,
    CATEGORY_MATCH_THRESHOLD,
    SHORT_NAME_LENGTH,
    TITLE_MATCH_THRESHOLD,
)
from .data import Song

_DIGIT_WORDS = (
    "zero one two three four five six seven eight nine ten eleven twelve "
    "thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"
).split()

_PLAYER_COUNT_WORDS = {
    **{w: n for n, w in enumerate(_DIGIT_WORDS)},
    "won": 1,
    "to": 2,
    "too": 2,
    "for": 4,
    "solo": 1,
    "me": 1,
}

_EXIT = ["exit game now", "exit game", "exit the game", "quit game", "stop game"]
_SKIP = ["skip", "skip it", "skip this one", "skip please", "pass", "i pass"]
_REPEAT = [
    "repeat",
    "repeat it",
    "repeat that",
    "repeat please",
    "play it again",
    "say that again",
]


def normalize(text: str) -> str:
    """Lowercase, strip accents and punctuation, spell out small numbers."""
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower().replace("’", "'").replace("&", " and ")
    # P!nk -> pink, Ke$ha -> kesha
    text = re.sub(r"(?<=\w)!(?=\w)", "i", text)
    text = re.sub(r"(?<=\w)\$(?=\w)", "s", text)
    text = text.replace("'", "")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    words = [
        _DIGIT_WORDS[int(w)] if w.isdigit() and int(w) < len(_DIGIT_WORDS) else w
        for w in text.split()
    ]
    return " ".join(words)


def _ratio(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio() * 100


def _variants(name: str) -> set[str]:
    """Acceptable ways to say a name: with/without (parentheses), leading 'the'."""
    out = {normalize(name), normalize(re.sub(r"\([^)]*\)", " ", name))}
    out |= {v[4:] for v in out if v.startswith("the ") and len(v) > 4}
    return {v for v in out if v}


def _best_window_score(target: str, said: str) -> float:
    """Best match of target against any run of words in said."""
    words = said.split()
    if not words:
        return 0.0
    if len(target.replace(" ", "")) <= SHORT_NAME_LENGTH:
        return 100.0 if f" {target} " in f" {said} " else 0.0
    n = len(target.split())
    best = 0.0
    for size in range(max(1, n - 1), n + 2):
        for i in range(max(1, len(words) - size + 1)):
            window = " ".join(words[i : i + size])
            best = max(best, _ratio(target, window))
            # Whisper sometimes splits or joins words ("pop quiz"/"popquiz")
            best = max(best, _ratio(target.replace(" ", ""), window.replace(" ", "")))
    return best


_GENERIC_SURNAMES = {"brothers", "sisters", "family", "singers", "orchestra", "group"}


def _matches(variants: set[str], said: str, threshold: float) -> bool:
    return any(_best_window_score(v, said) >= threshold for v in variants)


def _artist_matches(name: str, said: str) -> bool:
    """Full name, or a surname alone for two-word names ("Lennon", "Leppard").

    A lone surname is short, so it must match more closely than a full name.
    """
    variants = _variants(name)
    if _matches(variants, said, ARTIST_MATCH_THRESHOLD):
        return True
    surnames = {
        words[1]
        for words in (v.split() for v in variants)
        if len(words) == 2 and len(words[1]) >= 5 and words[1] not in _GENERIC_SURNAMES
    }
    return _matches(surnames, said, max(ARTIST_MATCH_THRESHOLD, 90))


def grade(said: str, song: Song) -> tuple[bool, bool]:
    """Return (got_title, got_artist). Any credited artist counts."""
    said = normalize(said)
    got_title = _matches(_variants(song.title), said, TITLE_MATCH_THRESHOLD)
    got_artist = any(_artist_matches(a, said) for a in song.artists)
    return got_title, got_artist


def _is_one_of(said: str, phrases: list[str], threshold: float = 85) -> bool:
    said = normalize(said)
    squashed = said.replace(" ", "")
    return any(
        _ratio(said, p) >= threshold or squashed == p.replace(" ", "")
        for p in phrases
    )


def is_exit(said: str) -> bool:
    return _is_one_of(said, _EXIT)


def is_skip(said: str) -> bool:
    return _is_one_of(said, _SKIP)


def is_repeat(said: str) -> bool:
    return _is_one_of(said, _REPEAT)


def is_start(said: str) -> bool:
    """'Play Pop Quiz', tolerating 'popquiz', 'pop quizz', trailing 'game'."""
    squashed = normalize(said).replace(" ", "").removesuffix("game")
    return any(
        _ratio(squashed, p) >= 85
        for p in ("playpopquiz", "startpopquiz", "letsplaypopquiz")
    )


def parse_player_count(said: str) -> int | None:
    for word in normalize(said).split():
        if word in _PLAYER_COUNT_WORDS:
            return _PLAYER_COUNT_WORDS[word]
        if word.isdigit():
            return int(word)
    return None


def category_aliases(category: str, extra: list[str]) -> set[str]:
    return {normalize(category.replace("_", " "))} | {normalize(a) for a in extra}


def parse_category(said: str, aliases: dict[str, set[str]]) -> str | None:
    """Pick the category whose aliases best match what was said."""
    said = normalize(said)
    best, best_score = None, 0.0
    for category, names in aliases.items():
        for name in names:
            score = _best_window_score(name, said)
            if score > best_score:
                best, best_score = category, score
    return best if best_score >= CATEGORY_MATCH_THRESHOLD else None
