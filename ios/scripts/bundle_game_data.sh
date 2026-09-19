#!/bin/sh
# Xcode build phase: copy the song data from the repo into the app as GameData/.
# Clips are included only when the BUNDLE_CLIPS build setting is YES; without
# them the app streams each clip from its preview URL.
set -eu

REPO="$SRCROOT/.."
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GameData"
mkdir -p "$DEST/categories" "$DEST/previews" "$DEST/sounds"

rsync -a --delete --include '*.csv' --exclude '*' "$REPO/categories/" "$DEST/categories/"

if [ "${BUNDLE_CLIPS:-NO}" = "YES" ]; then
    if [ ! -f "$REPO/previews/index.csv" ]; then
        echo "error: previews/ is missing. Run python3 download_previews.py, or set BUNDLE_CLIPS = NO."
        exit 1
    fi
    rsync -a --delete --include '*.mp3' --exclude '*' "$REPO/previews/" "$DEST/previews/"
else
    rm -f "$DEST"/previews/*.mp3
fi
# The index holds each clip's length, which streaming needs too.
cp "$REPO/previews/index.csv" "$DEST/previews/index.csv"

if [ -f "$REPO/sounds/bonus_intro.mp3" ]; then
    cp "$REPO/sounds/bonus_intro.mp3" "$DEST/sounds/"
else
    echo "warning: sounds/bonus_intro.mp3 not found; the bonus round will have no intro sound."
fi
