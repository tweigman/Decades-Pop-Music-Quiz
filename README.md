# PopQuiz

Song data for a "name that tune" quiz. A player picks a category, hears a
5–10 second clip, and names the song and/or the artist. Rounds get harder as
they go.

Each category is a CSV of songs with a locally downloaded audio clip and a
Billboard chart peak that serves as a difficulty proxy — the higher a song
charted, the more likely a player knows it.

## Data

| Category | Songs | Charted | Median peak | #1s |
|---|---|---|---|---|
| `sixties` | 253 | 201 | 4 | 58 |
| `seventies` | 251 | 188 | 6 | 41 |
| `eighties` | 265 | 244 | 3 | 82 |
| `nineties` | 239 | 174 | 7 | 39 |
| `two_thousands` | 232 | 204 | 16 | 5 |
| `twenty_tens` | 150 | 130 | 10 | 17 |
| `twenty_twenties` | 150 | 131 | 4 | 44 |
| `holiday` | 190 | 65 | 26 | 2 |
| **Total** | **1730** | **1337** | | **288** |

`holiday` is the one non-decade category so far. Only 65 of its songs ever
charted, so its difficulty comes mostly from the `Difficulty` column rather
than the peak — see below.

Categories are identified by filename stem, so a non-decade list only needs
to be dropped in as `categories/holiday.csv` — no code change.

### Columns

| Column | Notes |
|---|---|
| `#` | Row number within the category |
| `URL` | Original Spotify track URL |
| `Title` | Exact Spotify track name, cruft and all |
| `Clean Title` | Display title, version/remaster suffixes stripped |
| `Artist(s)` | All credited artists, `; ` separated |
| `Year` | Spotify release year — see caveat below |
| `Duration (ms)` | Full track length |
| `MP3 File` | Filename in `previews/`, blank if no clip exists |
| `Preview URL` | Source URL for the clip |
| `Peak (Hot 100)` | Best-ever Billboard position, blank if unmatched |
| `Difficulty` | Manual override: `easy`, `harder` or `difficult`. Blank = derive from `Peak` |

## Layout

```
categories/   one CSV per quiz category
previews/     1,734 clips + index.csv (gitignored, ~582 MB)
raw/          original URL lists, pre-curation
*.py          data pipeline, plus play_cli.py
custom_components/popquiz/   the Home Assistant integration
sounds/       game sounds (bonus_intro.mp3; gitignored)
tests/, tests_ha/            unit tests; tests inside Home Assistant
```

## Pipeline

Every script is re-runnable and resumable; re-running only fills gaps.

```bash
python3 new_category.py raw/Holiday.txt     # all three steps, in order
```

That is the way to add a category: running the steps by hand risks leaving
one part-built, which makes it silently unplayable. The individual steps are
still there if a single stage needs re-running:

```bash
python3 spotify_to_csv.py raw/Holiday.txt categories/holiday.csv  # metadata
python3 download_previews.py categories/holiday.csv               # audio
python3 add_chart_peaks.py categories/holiday.csv                 # chart peaks
```

Run any of them with no arguments to process every category at once, and
`new_category.py` bare for a health report.

| Script | Role |
|---|---|
| `spotify_to_csv.py` | Entry point. URL list *or* existing CSV → metadata CSV |
| `download_previews.py` | Fetches clips, writes `previews/index.csv` with measured lengths |
| `add_chart_peaks.py` | Joins the Billboard Hot 100 archive |
| `clean_titles.py` | Title cleaning, also runnable standalone |
| `fetch_spotify_meta.py` | Low-level page scrapers (module) |
| `new_category.py` | Runs all three steps; bare, reports every category's state |
| `classify_holiday.py` | The hand difficulty assignments for `holiday` |

No API key, OAuth, or subscription. Metadata comes from Spotify's public
embed pages, which expose a JSON blob with artists, duration and a preview
URL. The Web API is not used: its `audio-features` and `audio-analysis`
endpoints were deprecated for new apps in November 2024 and return `403`.

**Pacing matters.** Requests go through one global schedule (~2.9/sec)
rather than per-worker. Running unthrottled trips Spotify's rate limiter at
roughly 190 requests, after which everything 429s. Throttling is *faster*
overall because no time is lost to backoff — 260 tracks in about 90 seconds.

## Gotchas

**Clips are not all 30 seconds.** Lengths run 14.7s to 29.8s; **299 of 1,734
are under 25s**. Anything picking a random offset must read the per-file
length from `previews/index.csv` rather than assuming a fixed window. The
`twenty_twenties` category is the worst affected.

**`Year` is the Spotify release date, not the chart year.** Compilations and
remasters inflate it — some 1960s recordings carry a 2010s date. Fine for
sorting, unreliable as a quiz answer.

**Chart peak is a poor difficulty proxy outside the decade categories.**
A song with no Hot 100 match counts as *difficult*, which is fine for the
decades but wrong for `holiday`: 125 of its 190 songs never charted, so left
to the peak, *O Holy Night* ranked as hard as anything in the set. That is
what the `Difficulty` column is for — see below.

**A blank `Peak` means "no match found", not "never charted."** 83% matched.
The Hot 100 is US-only, so UK and European hits legitimately have none, and
a few entries appear to be missing from the archive itself. Peaks are
**best-ever across all chart runs**: Bohemian Rhapsody reads `2` (its 1992
re-chart) rather than the `9` it hit in 1976.

**`raw/` is not equivalent to `categories/`.** The raw lists still contain
roughly 60 rows removed during curation — duplicates, live and remaster
variants, and songs that belonged to a different decade. Regenerating a
category from `raw/` resurrects them. **The CSVs are the source of truth.**

**Deduplication rule.** Songs are unique within each category and across the
decade categories, resolved by *earliest* release year, on the basis that
re-releases only ever push a year later.

Cross-category deduplication is decade-specific. `holiday` overlaps the
decades legitimately — *All I Want For Christmas Is You* belongs in both — so
it is deduplicated only against itself, and the same goes for any future
non-decade category.

Note that `spotify_to_csv.py` only catches repeats of the same Spotify *id*.
The same recording issued on two albums has two ids, so title-plus-artist
duplicates still need a look; eleven of them were removed from `holiday`.

## Difficulty

Each song lands in one of three levels — `easy`, `harder`, `difficult` — and
the game draws from them as rounds progress. The level comes from the
`Difficulty` column when it's set, and from the Hot 100 peak otherwise:

| `Peak` | Level |
|---|---|
| 1–5 | `easy` |
| 6–15 | `harder` |
| 16+, or no peak | `difficult` |

Cutoffs live in `const.py` (`EASY_MAX_PEAK`, `HARDER_MAX_PEAK`).

**To override**, put `easy`, `harder` or `difficult` in a row's `Difficulty`
cell. Blank means "derive from peak", so the decade categories can be left
alone entirely. An unrecognised value logs a warning and falls back to the
peak rather than failing the load.

This exists because the chart-peak proxy only works where most songs charted.
`holiday` is the case it was added for. Left to the peak it came out 8 easy /
15 harder / 178 difficult, with *Silent Night* ranked as hard as anything in
the set. `classify_holiday.py` holds the hand assignments — 145 of its 190
rows — and writes the column; it is keyed by Spotify track id, defaults to a
dry run, and re-applying is idempotent. The category now reads **55 easy,
68 harder, 67 difficult**.

Expect to do the same for any future category where most songs never charted.

Check where a category stands with `python3 new_category.py`, which reports
song, clip, peak and easy-pool counts per category.

## Audio clips

`previews/` is gitignored. It holds 582 MB of third-party copyrighted audio
downloaded from Spotify's public preview endpoint — appropriate for private,
local quiz use, but it should not be committed or redistributed. The clips
are ~96 kbps, fine through a speaker and noticeably compressed on headphones.

Regenerate at any time with `python3 download_previews.py`.

## Playing on Home Assistant

`custom_components/popquiz/` is a Home Assistant integration that adds a
**Pop Quiz** conversation agent. Say *"Play Pop Quiz"* to a voice satellite;
anything else is passed to Home Assistant's built-in agent, so device
commands keep working.

Game rules and every tunable number (clip length, peak cutoffs for
easy/harder/difficult, points per round, match strictness) are in
`custom_components/popquiz/const.py`. Players can say **repeat**, **skip**,
or **exit game now** at any point.

The bonus-round build-up sound goes at `sounds/bonus_intro.mp3` (gitignored).
Without it, the bonus round just has no intro sound.

### Install

```bash
./deploy.sh all    # first time: integration + ~500 MB of song data
./deploy.sh        # afterwards: integration code only
```

This copies to the Synology over SSH (you'll be asked for the password).
The song data goes to `<config>/popquiz/`; the integration code goes to
`<config>/custom_components/popquiz/`. Then:

1. Restart Home Assistant.
2. **Settings → Devices & services → Add integration → Pop Quiz.**
3. **Settings → Voice assistants**: in the satellite's pipeline, set the
   conversation agent to **Pop Quiz**. Speech-to-text and text-to-speech stay
   as they are (Whisper, Piper).

### How it works

An Assist reply can only be text, so clips are played separately. After the
satellite finishes speaking a reply, the integration cuts a clip with ffmpeg
and calls `assist_satellite.start_conversation` with it. The satellite plays
the clip, then listens, and the answer comes back to the agent. The bonus
build-up plays as that call's "preannounce" sound. This needs a satellite that
supports *start conversation* (current ESPHome voice firmware does); clips
can't play in the Assist dialog in the web UI or phone app.

| File | Role |
|---|---|
| `game.py` | Game state machine, no Home Assistant dependency |
| `grading.py` | Fuzzy answer matching, commands, player count, category |
| `data.py` | Loads songs; songs with no chart peak count as difficult |
| `clips.py` | Cuts the random-offset clip with ffmpeg |
| `conversation.py` | The Assist agent and clip playback |

### Tests

```bash
python3 -m unittest -v                     # game + grading, plain Python
pytest tests_ha -c tests_ha/pytest.ini     # inside a real HA core; needs
                                           # pytest-homeassistant-custom-component
```

## Playing on iPhone

`ios/` is a native SwiftUI app playing the same game hands-free: it speaks
with AVSpeechSynthesizer, plays the clip, then listens with on-device speech
recognition. A custom language model trained on every title and artist helps
it hear names like "Blue Öyster Cult". Buttons (players, categories, Repeat,
Skip, Type) work too.

```bash
cd ios && ./install.sh                  # build and install on the plugged-in iPhone
BUNDLE_CLIPS=NO ./install.sh            # small build; clips stream instead
cd ios/Packages/PopQuizCore && swift test   # game + grading tests, on the Mac
```

Needs Xcode (sign in under Settings → Accounts) and `brew install xcodegen`;
the Xcode project is generated from `ios/project.yml`. The phone needs
Developer Mode on (Settings → Privacy & Security).

**Clips.** With `BUNDLE_CLIPS=YES` (the default) the MP3s are copied into the
app and Settings offers *On this iPhone* or *Stream*. Without them the app
streams every clip from its `Preview URL`. Either way `previews/index.csv` is
bundled, because it holds the clip lengths.

**Same rules as Home Assistant.** `PopQuizCore` is a line-for-line port of
`game.py`, `grading.py` and `const.py`, and ships `Settings.swift` in place of
`const.py`: **change a rule in both.** Python's `difflib` scoring is ported
exactly, and `GradingParityTests` checks the Swift grader against ~17,000
decisions recorded from Python. After editing `grading.py`, regenerate them:
`python3 ios/scripts/make_grading_fixtures.py`.

**The mic goes silent under screen mirroring.** With Xcode's Device Hub
mirroring the phone's screen, the microphone delivers nothing but zeroes: the
app hears silence while everything else works. Disconnect mirroring before
testing by voice. `Documents/diagnostics.log` in the app container records the
audio route, buffer count and peak level per answer, which is what pinned this
down; copy it off with `xcrun devicectl device copy from`.

**Simulator.** It has no on-device speech models, so the custom vocabulary is
skipped there. Launch with `-demo` (debug builds) and the game plays itself,
answering every question right, which exercises speech, clips and scoring
without a microphone.

## Status

The quiz is built and runs as a Home Assistant voice game (below), or in a
terminal with `python3 play_cli.py` (add `--speak` to hear the quizmaster's
lines read aloud by the Mac).

For a "play the bridge" round, clip position would need full-length audio run
through a structure analyzer such as
[all-in-one](https://github.com/mir-aidj/all-in-one), which labels intro /
verse / chorus / bridge / outro with timestamps. A 15–30s preview cannot
locate a bridge within the parent track.
