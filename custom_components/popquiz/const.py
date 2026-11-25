"""Pop Quiz settings. Edit these, then restart Home Assistant."""

DOMAIN = "popquiz"

# Length of each song clip, in seconds. The start point is random but always
# leaves room for the full clip to play.
CLIP_SECONDS = 8.0

# Difficulty comes from the song's best Billboard Hot 100 peak:
#   1 .. EASY_MAX_PEAK               -> easy
#   EASY_MAX_PEAK+1 .. HARDER_MAX_PEAK -> harder
#   above HARDER_MAX_PEAK            -> difficult
# Songs with no chart peak (no US Hot 100 match) count as difficult.
EASY_MAX_PEAK = 5
HARDER_MAX_PEAK = 15

EASY = "easy"
HARDER = "harder"
DIFFICULT = "difficult"

# One entry per round: (difficulty, points per correct answer).
# Naming both the song and the artist earns double.
ROUNDS = [
    (EASY, 10),
    (EASY, 10),
    (EASY, 10),
    (HARDER, 20),
    (DIFFICULT, 40),
]

# The round (1-based) announced as the bonus round, with the intro sound.
BONUS_ROUND = 5

# Read out everyone's scores before the bonus round (multiplayer games only).
ANNOUNCE_SCORES_BEFORE_BONUS = False

MIN_PLAYERS = 1
MAX_PLAYERS = 6

# How closely an answer must match, 0-100. Lower is more forgiving.
TITLE_MATCH_THRESHOLD = 80
ARTIST_MATCH_THRESHOLD = 80
# Names this short (in letters) must be said exactly, since fuzzy matching
# on very short strings produces false positives.
SHORT_NAME_LENGTH = 4
# How closely a spoken category name must match.
CATEGORY_MATCH_THRESHOLD = 75

# A game with no activity for this long is abandoned.
GAME_IDLE_TIMEOUT_MIN = 10

# Paths relative to the data directory (<config>/popquiz on Home Assistant).
CATEGORIES_DIR = "categories"
PREVIEWS_INDEX = "previews/index.csv"
BONUS_INTRO_FILE = "sounds/bonus_intro.mp3"

# Extra things a player might say for a category, beyond its file name.
# Keys are category file names (without .csv).
CATEGORY_ALIASES = {
    "sixties": ["60s", "1960s"],
    "seventies": ["70s", "1970s"],
    "eighties": ["80s", "1980s"],
    "nineties": ["90s", "1990s"],
    "two_thousands": ["2000s", "two thousand", "the aughts", "noughties"],
    "twenty_tens": ["2010s", "twenty ten", "the tens"],
    "twenty_twenties": ["2020s", "twenty twenty"],
    "holiday": ["holidays", "christmas", "xmas", "christmas music", "holiday music"],
}

# The holiday category is seasonal: it is offered only between these two dates
# (month, day), inclusive, which wrap around the new year. Everything else is
# available all year.
HOLIDAY_CATEGORY = "holiday"
HOLIDAY_FROM = (11, 20)
HOLIDAY_UNTIL = (1, 6)

# Offer the holiday category whatever the date. The iPhone app has this as the
# "extended playlists" setting; here it is a straight edit.
ALWAYS_SHOW_HOLIDAY = False

# Seconds to wait after the satellite finishes speaking before playing a
# clip. Raise this if the end of the spoken text gets cut off.
POST_SPEECH_DELAY = 0.3
