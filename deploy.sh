#!/usr/bin/env bash
# Copy Pop Quiz to Home Assistant on the Synology NAS, then restart HA.
#   ./deploy.sh        integration code only (seconds)
#   ./deploy.sh all    code plus categories, previews and sounds (~500 MB)
set -euo pipefail
HOST="${POPQUIZ_HOST:-user@nas-address}"
HA_DIR="${POPQUIZ_HA_DIR:-/volume1/docker/homeassistant}"
cd "$(dirname "$0")"
export COPYFILE_DISABLE=1  # no macOS ._ files in the archive

echo "Copying integration to $HOST:$HA_DIR/custom_components/popquiz"
tar czf - --exclude __pycache__ custom_components/popquiz |
  ssh "$HOST" "mkdir -p '$HA_DIR/custom_components' &&
    rm -rf '$HA_DIR/custom_components/popquiz' && tar xzf - -C '$HA_DIR'"

if [[ "${1:-}" == all ]]; then
  echo "Copying song data to $HOST:$HA_DIR/popquiz"
  mkdir -p sounds
  tar cf - categories previews sounds |
    ssh "$HOST" "mkdir -p '$HA_DIR/popquiz' && tar xf - -C '$HA_DIR/popquiz'"
fi
echo "Done. Restart Home Assistant to load the changes."
