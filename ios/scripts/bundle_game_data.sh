#!/bin/sh
# Xcode build phase: copy the song lists from the repo into the app as
# GameData/. Only the lists travel with the app; every clip is streamed from
# its Apple preview URL when it's needed.
set -eu

REPO="$SRCROOT/.."
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GameData"
rm -rf "$DEST"
mkdir -p "$DEST/categories" "$DEST/sounds"

# Each list goes in trimmed to what the game reads: playable rows only, and
# none of the chart history (dates, weeks on chart) the game doesn't use.
# Files starting with an underscore are the pipeline's working files.
/usr/bin/python3 - "$REPO/altcategories" "$DEST/categories" <<'EOF'
import csv, pathlib, sys

src, dest = map(pathlib.Path, sys.argv[1:])
keep = ["#", "URL", "Title", "Clean Title", "Artist(s)", "Apple Artist", "Preview URL",
        "Peak (Hot 100)", "Difficulty", "Match", "Preview (s)", "Lyrics Start (s)",
        "Vocal Segments", "Vocal %"]
for path in sorted(src.glob("[!_]*.csv")):
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        columns = [c for c in keep if c in reader.fieldnames]
        rows = [r for r in reader if r.get("Match", "ok").strip() == "ok" and r.get("Preview URL", "").strip()]
    with (dest / path.name).open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
EOF

# The bonus-round sound is licensed (Envato Elements) for use in this app
# only, so it's stored scrambled, not as a file that could be copied out and
# played. GameData.swift unscrambles it with the same key.
if [ -f "$REPO/sounds/bonus_intro.mp3" ]; then
    /usr/bin/python3 -c '
import sys
data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(bytes(b ^ 0xA7 for b in data))
' "$REPO/sounds/bonus_intro.mp3" "$DEST/sounds/bonus.bin"
else
    echo "warning: sounds/bonus_intro.mp3 not found; the bonus round will have no intro sound."
fi
