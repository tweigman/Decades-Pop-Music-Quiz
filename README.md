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
| **Total** | **1540** | **1272** | | **286** |

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

## Layout

```
categories/   one CSV per quiz category
previews/     1,533 clips + index.csv (gitignored, ~516 MB)
raw/          original URL lists, pre-curation
*.py          data pipeline, plus play_cli.py
custom_components/popquiz/   the Home Assistant integration
sounds/       game sounds (bonus_intro.mp3; gitignored)
tests/, tests_ha/            unit tests; tests inside Home Assistant
```

## Pipeline

Every script is re-runnable and resumable; re-running only fills gaps.

```bash
python3 spotify_to_csv.py raw/holiday.txt categories/holiday.csv  # metadata
python3 download_previews.py categories/holiday.csv               # audio
python3 add_chart_peaks.py categories/holiday.csv                 # chart peaks
```

Run with no arguments to process every category at once.

| Script | Role |
|---|---|
| `spotify_to_csv.py` | Entry point. URL list *or* existing CSV → metadata CSV |
| `download_previews.py` | Fetches clips, writes `previews/index.csv` with measured lengths |
| `add_chart_peaks.py` | Joins the Billboard Hot 100 archive |
| `clean_titles.py` | Title cleaning, also runnable standalone |
| `fetch_spotify_meta.py` | Low-level page scrapers (module) |

No API key, OAuth, or subscription. Metadata comes from Spotify's public
embed pages, which expose a JSON blob with artists, duration and a preview
URL. The Web API is not used: its `audio-features` and `audio-analysis`
endpoints were deprecated for new apps in November 2024 and return `403`.

**Pacing matters.** Requests go through one global schedule (~2.9/sec)
rather than per-worker. Running unthrottled trips Spotify's rate limiter at
roughly 190 requests, after which everything 429s. Throttling is *faster*
overall because no time is lost to backoff — 260 tracks in about 90 seconds.

## Gotchas

**Clips are not all 30 seconds.** Lengths run 14.7s to 29.8s; **249 of 1,533
are under 25s**. Anything picking a random offset must read the per-file
length from `previews/index.csv` rather than assuming a fixed window. The
`twenty_twenties` category is the worst affected.

**`Year` is the Spotify release date, not the chart year.** Compilations and
remasters inflate it — some 1960s recordings carry a 2010s date. Fine for
sorting, unreliable as a quiz answer.

**A blank `Peak` means "no match found", not "never charted."** 83% matched.
The Hot 100 is US-only, so UK and European hits legitimately have none, and
a few entries appear to be missing from the archive itself. Peaks are
**best-ever across all chart runs**: Bohemian Rhapsody reads `2` (its 1992
re-chart) rather than the `9` it hit in 1976.

**`raw/` is not equivalent to `categories/`.** The raw lists still contain
roughly 60 rows removed during curation — duplicates, live and remaster
variants, and songs that belonged to a different decade. Regenerating a
category from `raw/` resurrects them. **The CSVs are the source of truth.**

**Deduplication rule.** Songs are unique within and across categories,
resolved by *earliest* release year across all entries, on the basis that
re-releases only ever push a year later. This is decade-specific logic — a
future `holiday` category will legitimately overlap the decade ones and
should not be deduplicated against them.

## Audio clips

`previews/` is gitignored. It holds 516 MB of third-party copyrighted audio
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

## Status

The quiz is built and runs as a Home Assistant voice game (below), or in a
terminal with `python3 play_cli.py`.

For a "play the bridge" round, clip position would need full-length audio run
through a structure analyzer such as
[all-in-one](https://github.com/mir-aidj/all-in-one), which labels intro /
verse / chorus / bridge / outro with timestamps. A 15–30s preview cannot
locate a bridge within the parent track.
