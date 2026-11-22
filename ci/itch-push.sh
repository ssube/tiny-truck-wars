#!/bin/bash
# Pushes the packed builds (ci/package.sh) to itch.io with butler: the
# channels linux, windows and web (mark the web one "playable in the
# browser" on the page) of $ITCH_TARGET (default ssube/tiny-truck-wars),
# tagged with project.godot's version. The page must exist on itch.io first;
# butler needs `butler login` once, or $BUTLER_API_KEY.
#   ci/package.sh && ci/itch-push.sh
#   ITCH_TARGET=someone/some-game ci/itch-push.sh
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
TARGET=${ITCH_TARGET:-ssube/tiny-truck-wars}
VERSION=$(sed -nE 's/^config\/version="(.*)"$/\1/p' project.godot)
for platform in linux windows web; do
  test -d "dist/$platform/tiny-truck-wars-$VERSION-$platform" || { echo "No dist/$platform: run ci/package.sh first." >&2; exit 1; }
  butler push "dist/$platform/tiny-truck-wars-$VERSION-$platform" "$TARGET:$platform" --userversion "$VERSION"
done
butler status "$TARGET"
