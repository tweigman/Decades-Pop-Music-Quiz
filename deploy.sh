#!/usr/bin/env bash
# Copy Pop Quiz to Home Assistant on the Synology NAS, then restart HA.
#   ./deploy.sh        integration code only (seconds)
#   ./deploy.sh all    code plus categories, previews and sounds (~500 MB)
set -euo pipefail
cd "$(dirname "$0")"
# Where Home Assistant lives is kept out of the repository, in deploy.env
# (gitignored), e.g.
#   POPQUIZ_HOST=user@nas-address
#   POPQUIZ_HA_DIR=/volume1/docker/homeassistant
if [[ -f deploy.env ]]; then source deploy.env; fi
HOST="${POPQUIZ_HOST:?Set POPQUIZ_HOST (user@host) in deploy.env or the environment}"
HA_DIR="${POPQUIZ_HA_DIR:-/volume1/docker/homeassistant}"
# Leave out macOS metadata (._ files, xattrs) that Linux tar warns about.
export COPYFILE_DISABLE=1

# Files are overwritten in place rather than the folder being deleted first:
# Home Assistant runs as root and leaves a root-owned __pycache__ behind,
# which this SSH user can't delete.
echo "Copying integration to $HOST:$HA_DIR/custom_components/popquiz"
tar czf - --no-xattrs --no-mac-metadata --exclude __pycache__ custom_components/popquiz |
  ssh "$HOST" "mkdir -p '$HA_DIR/custom_components' && tar xzf - -C '$HA_DIR'"

if [[ "${1:-}" == all ]]; then
  echo "Copying song data to $HOST:$HA_DIR/popquiz"
  mkdir -p sounds
  tar cf - --no-xattrs --no-mac-metadata categories previews sounds |
    ssh "$HOST" "mkdir -p '$HA_DIR/popquiz' && tar xf - -C '$HA_DIR/popquiz'"
fi
echo "Done. Restart Home Assistant to load the changes."
