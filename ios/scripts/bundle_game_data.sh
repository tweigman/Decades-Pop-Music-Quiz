#!/bin/sh
# Xcode build phase: copy the song lists from the repo into the app as
# GameData/. Only the lists travel with the app; every clip is streamed from
# its Apple preview URL when it's needed.
set -eu

REPO="$SRCROOT/.."
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GameData"
mkdir -p "$DEST/categories" "$DEST/sounds"
rm -rf "$DEST/previews"

# Files starting with an underscore are the pipeline's working files.
rsync -a --delete --exclude '_*' --include '*.csv' --exclude '*' "$REPO/altcategories/" "$DEST/categories/"

if [ -f "$REPO/sounds/bonus_intro.mp3" ]; then
    cp "$REPO/sounds/bonus_intro.mp3" "$DEST/sounds/"
else
    echo "warning: sounds/bonus_intro.mp3 not found; the bonus round will have no intro sound."
fi
