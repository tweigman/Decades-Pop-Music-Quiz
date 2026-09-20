"""Tests for the game engine and answer matching. Run: python3 -m unittest -v"""

import random
import unittest
from pathlib import Path

from custom_components.popquiz import grading
from custom_components.popquiz.const import CLIP_SECONDS, ROUNDS
from custom_components.popquiz.data import Library, Song
from custom_components.popquiz.game import Game

REPO = Path(__file__).resolve().parent.parent


def song(title, *artists, peak=1, length=30.0):
    return Song(title, artists, peak, Path(f"/x/{title}.mp3"), length)


class GradingTest(unittest.TestCase):
    def test_both_parts_any_order(self):
        s = song("Imagine", "John Lennon")
        for said in (
            "Imagine, by John Lennon.",
            "John Lennon, Imagine",
            "I think it's Imagine by Lennon",
            "imagine john lenin",
        ):
            self.assertEqual(grading.grade(said, s), (True, True), said)

    def test_one_part(self):
        s = song("Imagine", "John Lennon")
        self.assertEqual(grading.grade("Imagine by the Beatles", s), (True, False))
        self.assertEqual(grading.grade("It's John Lennon", s), (False, True))
        self.assertEqual(grading.grade("Imagination", s), (False, False))

    def test_any_credited_artist(self):
        s = song("Under Pressure", "Queen", "David Bowie")
        self.assertEqual(grading.grade("david bowie", s), (False, True))
        self.assertEqual(grading.grade("Under Pressure, Queen", s), (True, True))

    def test_parentheses_and_leading_the(self):
        s = song("(Don't Fear) The Reaper", "Blue Öyster Cult")
        self.assertEqual(grading.grade("Don't fear the reaper", s)[0], True)
        self.assertEqual(grading.grade("the reaper by blue oyster cult", s), (True, True))
        self.assertTrue(grading.grade("Beatles", song("Help!", "The Beatles"))[1])

    def test_short_names_need_exact_match(self):
        s = song("Hey", "U2")
        self.assertEqual(grading.grade("U2", s), (False, True))
        self.assertEqual(grading.grade("hey you too", s), (True, False))
        self.assertEqual(grading.grade("they", s), (False, False))

    def test_numbers_and_symbols(self):
        self.assertTrue(grading.grade("seven rings", song("7 rings", "Ariana Grande"))[0])
        self.assertTrue(grading.grade("pink", song("So What", "P!nk"))[1])

    def test_commands(self):
        self.assertTrue(grading.is_exit("Exit game now."))
        self.assertTrue(grading.is_skip("Skip."))
        self.assertTrue(grading.is_repeat("Repeat!"))
        self.assertTrue(grading.is_repeat("play it again"))
        self.assertFalse(grading.is_skip("Pass the Dutchie"))
        self.assertFalse(grading.is_exit("End Game by Taylor Swift"))

    def test_start_phrase(self):
        for said in ("Play Pop Quiz.", "play popquiz", "Play pop quiz game", "play pop quizz"):
            self.assertTrue(grading.is_start(said), said)
        self.assertFalse(grading.is_start("Play music"))
        self.assertFalse(grading.is_start("Turn on tall lamp"))

    def test_player_count(self):
        self.assertEqual(grading.parse_player_count("Three."), 3)
        self.assertEqual(grading.parse_player_count("3 players"), 3)
        self.assertEqual(grading.parse_player_count("Just me"), 1)
        self.assertIsNone(grading.parse_player_count("lots"))

    def test_category(self):
        aliases = {
            "eighties": grading.category_aliases("eighties", ["80s", "1980s"]),
            "twenty_tens": grading.category_aliases("twenty_tens", ["2010s"]),
            "twenty_twenties": grading.category_aliases("twenty_twenties", ["2020s"]),
        }
        for said, want in [
            ("Eighties.", "eighties"),
            ("the '80s", "eighties"),
            ("Twenty tens", "twenty_tens"),
            ("the 2020s please", "twenty_twenties"),
            ("classical", None),
        ]:
            self.assertEqual(grading.parse_category(said, aliases), want, said)


class FakeLibrary(Library):
    def __init__(self):
        self.categories = {
            "eighties": [song(f"Easy {i}", "Artist", peak=2) for i in range(20)]
            + [song(f"Harder {i}", "Artist", peak=10) for i in range(10)]
            + [song(f"Hard {i}", "Artist", peak=50, length=4.0) for i in range(5)]
            + [song(f"Unranked {i}", "Artist", peak=None, length=4.0) for i in range(5)],
            "nineties": [song("Other", "Artist")],
        }


class GameTest(unittest.TestCase):
    def new_game(self, players, **options):
        game = Game(FakeLibrary(), random.Random(1), **options)
        self.assertIn("How many players", game.start().speech)
        game.handle(str(players))
        reply = game.handle("eighties")
        self.assertIn("Eighties it is", reply.speech)
        return game, reply

    def test_full_two_player_game(self):
        game, reply = self.new_game(2)
        seen_levels, seen_titles = [], set()
        for rnd in range(len(ROUNDS)):
            for player in range(2):
                clip = reply.clip
                self.assertIsNotNone(clip)
                self.assertLessEqual(clip.offset + clip.duration, clip.song.length)
                self.assertNotIn(clip.song.title, seen_titles)
                seen_titles.add(clip.song.title)
                seen_levels.append(clip.song.title.split()[0].replace("Unranked", "Hard"))
                is_bonus = rnd == 4 and player == 0
                self.assertEqual(bool(reply.bonus_speech), is_bonus)
                if is_bonus:
                    # Feedback on the last answer comes before the bonus sound,
                    # the bonus announcement after it.
                    self.assertIn("That was", reply.speech)
                    self.assertNotIn("bonus round", reply.speech)
                    self.assertIn("It's the bonus round", reply.bonus_speech)
                    self.assertIn("Player 1, get ready", reply.bonus_speech)
                    self.assertNotIn("Scores so far", reply.speech)
                # Player 1 names both, player 2 names the artist only.
                said = f"{clip.song.title} by Artist" if player == 0 else "Artist"
                reply = game.handle(said)
        self.assertEqual(seen_levels, ["Easy"] * 6 + ["Harder"] * 2 + ["Hard"] * 2)
        self.assertEqual(game.scores, [180, 90])
        self.assertTrue(reply.done)
        self.assertIn("Player 1 wins with 180 points", reply.speech)

    def test_scores_before_bonus_when_enabled(self):
        game, reply = self.new_game(2, announce_scores_before_bonus=True)
        for _ in range(8):
            reply = game.handle("skip")
        self.assertIn("Scores so far: Player 1, 0, Player 2, 0.", reply.speech)
        self.assertIn("bonus round", reply.bonus_speech)

    def test_short_clip_fits(self):
        game, reply = self.new_game(1)
        for _ in range(4):
            reply = game.handle("skip")
        self.assertEqual(reply.clip.duration, min(CLIP_SECONDS, 4.0))
        self.assertLessEqual(reply.clip.offset + reply.clip.duration, 4.0)

    def test_repeat_skip_and_exit(self):
        game, reply = self.new_game(1)
        first = reply.clip
        again = game.handle("repeat")
        self.assertEqual(again.clip, first)
        self.assertEqual(game.round, 0)
        skipped = game.handle("skip")
        self.assertIn("Skipped", skipped.speech)
        self.assertEqual(game.scores, [0])
        self.assertEqual(game.round, 1)
        bye = game.handle("exit game now")
        self.assertTrue(bye.done)

    def test_tie(self):
        game, reply = self.new_game(2)
        for _ in range(10):
            reply = game.handle(reply.clip.song.title)
        self.assertIn("tie between Player 1 and Player 2", reply.speech)

    def test_bad_player_count_reprompts(self):
        game = Game(FakeLibrary())
        game.start()
        self.assertIn("from 1 to 6", game.handle("nine").speech)
        self.assertIn("Pick a category", game.handle("two").speech)


@unittest.skipUnless((REPO / "previews/index.csv").exists(), "previews not downloaded")
class RealLibraryTest(unittest.TestCase):
    def test_loads_every_category(self):
        """Every complete category loads; half-built ones are skipped loudly.

        Categories get added over time, so a CSV whose clips aren't downloaded
        yet must not fail the suite -- but it must still be accounted for, so
        a category that vanishes for any *other* reason is caught.
        """
        lib = Library(REPO)
        stems = {p.stem for p in (REPO / "categories").glob("*.csv")}
        self.assertEqual(set(lib.categories) | set(lib.skipped), stems)
        for name in lib.skipped:
            self.assertNotIn(name, lib.categories)

        for name, songs in lib.categories.items():
            for s in songs:
                self.assertTrue(s.path.is_file())

    def test_every_category_can_fill_every_level(self):
        """A loaded category must be able to supply a song at each level.

        Depth is a data-quality question, not a correctness one -- the game
        falls back to repeats when a level's pool runs dry, and a category
        whose songs mostly never charted (holiday) is legitimately thin at
        the easy end. `new_category.py` reports depth; this guards only that
        no level is empty.
        """
        lib = Library(REPO)
        for name in lib.categories:
            for level in ("easy", "harder", "difficult"):
                self.assertTrue(lib.songs(name, level), f"{name}/{level}")


if __name__ == "__main__":
    unittest.main()
