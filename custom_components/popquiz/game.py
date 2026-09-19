"""The Pop Quiz game: a state machine driven by what the player says.

This module has no Home Assistant dependency, so it can be played and tested
from a terminal (see play_cli.py). Each call returns a Reply describing what
to say and whether to play a clip or keep listening; the caller does the I/O.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass

from . import grading, phrases
from .const import (
    ANNOUNCE_SCORES_BEFORE_BONUS,
    BONUS_ROUND,
    CATEGORY_ALIASES,
    CLIP_SECONDS,
    DIFFICULT,
    EASY,
    HARDER,
    MAX_PLAYERS,
    MIN_PLAYERS,
    ROUNDS,
)
from .data import Library, Song


@dataclass(frozen=True)
class Clip:
    song: Song
    offset: float  # seconds into the preview file
    duration: float


@dataclass(frozen=True)
class Reply:
    speech: str
    listen: bool = False  # keep listening right after speaking
    clip: Clip | None = None  # after speaking, play this, then listen
    bonus_intro: bool = False  # play the bonus build-up sound before the clip
    done: bool = False  # the game is over


_PLAYERS, _CATEGORY, _ANSWER, _OVER = "players", "category", "answer", "over"

# When a difficulty runs out of songs, borrow from the nearest one.
_FALLBACK = {
    EASY: [EASY, HARDER, DIFFICULT],
    HARDER: [HARDER, EASY, DIFFICULT],
    DIFFICULT: [DIFFICULT, HARDER, EASY],
}


class Game:
    def __init__(
        self,
        library: Library,
        rng: random.Random | None = None,
        announce_scores_before_bonus: bool = ANNOUNCE_SCORES_BEFORE_BONUS,
    ) -> None:
        self._library = library
        self._announce_scores = announce_scores_before_bonus
        self._rng = rng or random.Random()
        self._aliases = {
            c: grading.category_aliases(c, CATEGORY_ALIASES.get(c, []))
            for c in library.categories
        }
        self._state = _PLAYERS
        self._prompt = ""  # the last question asked, for "repeat"
        self.players = 0
        self.category = ""
        self.scores: list[int] = []
        self.round = 0  # 0-based
        self.turn = 0  # 0-based player index
        self._clip: Clip | None = None
        self._used: set[str] = set()
        self.last_activity = time.monotonic()

    # -- entry points -------------------------------------------------------

    def start(self) -> Reply:
        self._prompt = phrases.ASK_PLAYERS
        return Reply(phrases.WELCOME + phrases.ASK_PLAYERS, listen=True)

    def handle(self, said: str) -> Reply:
        self.last_activity = time.monotonic()
        if grading.is_exit(said):
            self._state = _OVER
            return Reply("Game over. Thanks for playing Pop Quiz!", done=True)
        if self._state == _PLAYERS:
            return self._on_players(said)
        if self._state == _CATEGORY:
            return self._on_category(said)
        if self._state == _ANSWER:
            return self._on_answer(said)
        return Reply("The game is over.", done=True)

    # -- setup --------------------------------------------------------------

    def _on_players(self, said: str) -> Reply:
        if grading.is_repeat(said):
            return Reply(self._prompt, listen=True)
        count = grading.parse_player_count(said)
        if count is None or not MIN_PLAYERS <= count <= MAX_PLAYERS:
            return Reply(
                f"Please say a number from {MIN_PLAYERS} to {MAX_PLAYERS}. "
                "How many players?",
                listen=True,
            )
        self.players = count
        self.scores = [0] * count
        self._state = _CATEGORY
        self._prompt = self._category_prompt()
        who = "One player." if count == 1 else f"{count} players."
        return Reply(f"{who} {self._prompt}", listen=True)

    def _category_prompt(self) -> str:
        names = [c.replace("_", " ") for c in self._library.categories]
        listed = ", ".join(names[:-1]) + f", or {names[-1]}" if len(names) > 1 else names[0]
        return f"Pick a category: {listed}."

    def _on_category(self, said: str) -> Reply:
        if grading.is_repeat(said):
            return Reply(self._prompt, listen=True)
        category = grading.parse_category(said, self._aliases)
        if category is None:
            return Reply(f"Sorry, I didn't catch that. {self._prompt}", listen=True)
        self.category = category
        self._state = _ANSWER
        return self._ask(f"{category.replace('_', ' ').capitalize()} it is!")

    # -- play ---------------------------------------------------------------

    def _on_answer(self, said: str) -> Reply:
        assert self._clip is not None
        if grading.is_repeat(said):
            return Reply("Here it is again.", clip=self._clip)
        song = self._clip.song
        reveal = f"That was {song.title}, by {song.artist_display}."
        if grading.is_skip(said):
            return self._advance(f"Skipped. {reveal}")
        if not grading.normalize(said):
            return Reply(
                "I didn't catch that. Say your answer, repeat, or skip.", listen=True
            )
        got_title, got_artist = grading.grade(said, song)
        points = ROUNDS[self.round][1] * (got_title + got_artist)
        self.scores[self.turn] += points
        if got_title and got_artist:
            verdict = f"You got both! {points} points."
        elif got_title:
            verdict = f"You got the song! {points} points."
        elif got_artist:
            verdict = f"You got the artist! {points} points."
        else:
            verdict = "Sorry, no points."
        return self._advance(f"{verdict} {reveal}")

    def _advance(self, feedback: str) -> Reply:
        self.turn += 1
        if self.turn == self.players:
            self.turn = 0
            self.round += 1
        if self.round == len(ROUNDS):
            return self._finish(feedback)
        return self._ask(feedback)

    def _ask(self, lead: str) -> Reply:
        """Announce the next turn and pick its clip."""
        round_no = self.round + 1
        level, points = ROUNDS[self.round]
        parts = [lead]
        new_round = self.turn == 0
        bonus = new_round and round_no == BONUS_ROUND
        if bonus:
            if self._announce_scores and self.players > 1:
                parts.append(f"Scores so far: {self._score_list()}.")
            parts.append(
                f"It's the bonus round! Every answer is worth {points} points, "
                f"{points * 2} if you get both."
            )
        elif new_round and round_no > 1 and points != ROUNDS[self.round - 1][1]:
            parts.append(
                f"Round {round_no}. The points go up: {points} per answer, "
                f"{points * 2} for both."
            )
        elif new_round:
            parts.append(f"Round {round_no}.")
        if bonus:
            parts.append("Player 1, get ready." if self.players > 1 else "Get ready.")
        elif self.players > 1:
            parts.append(f"Player {self.turn + 1}, here's your song.")
        else:
            parts.append("Here's your song.")
        self._clip = self._pick_clip(level)
        return Reply(" ".join(parts), clip=self._clip, bonus_intro=bonus)

    def _pick_clip(self, level: str) -> Clip:
        for lvl in _FALLBACK[level]:
            pool = [
                s
                for s in self._library.songs(self.category, lvl)
                if str(s.path) not in self._used
            ]
            if pool:
                break
        else:
            # Every song in the category has been played; allow repeats.
            self._used.clear()
            pool = self._library.categories[self.category]
        song = self._rng.choice(pool)
        self._used.add(str(song.path))
        duration = min(CLIP_SECONDS, song.length)
        offset = self._rng.uniform(0, song.length - duration)
        return Clip(song, round(offset, 2), duration)

    # -- ending -------------------------------------------------------------

    def _score_list(self) -> str:
        return ", ".join(f"Player {i + 1}, {s}" for i, s in enumerate(self.scores))

    def _finish(self, feedback: str) -> Reply:
        self._state = _OVER
        parts = [feedback, "That's the game!"]
        top = max(self.scores)
        if self.players == 1:
            parts.append(f"You scored {top} points.")
        else:
            parts.append(f"Final scores: {self._score_list()}.")
        if top == 0:
            parts.append("Better luck next game!")
            return Reply(" ".join(parts), done=True)
        winners = [f"Player {i + 1}" for i, s in enumerate(self.scores) if s == top]
        if len(winners) > 1:
            parts.append(
                f"It's a tie between {', '.join(winners[:-1])} and {winners[-1]}, "
                f"with {top} points each!"
            )
        elif self.players > 1:
            parts.append(f"{winners[0]} wins with {top} points!")
        parts.append(self._rng.choice(phrases.CELEBRATIONS))
        return Reply(" ".join(parts), done=True)
