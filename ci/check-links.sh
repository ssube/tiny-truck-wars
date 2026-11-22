#!/bin/bash
# Fails if a link under the project leads to a folder outside it:
#   ci/check-links.sh [project dir]
# Mounting a resource pack while running from a project folder makes the
# engine walk every folder under it, following links and ignoring
# .gdignore. A link out of the project (a Wine prefix's z: drive is a link
# to /) turns that into a walk of the whole disk, and the mount never
# finishes. See docs/ecs.md, "Traps".
set -euo pipefail
PROJECT=$(cd -- "${1:-$(dirname -- "$0")/..}" && pwd -P)
found=$(find "$PROJECT" -path "$PROJECT/.git" -prune -o -type l -print 2>/dev/null | while IFS= read -r link; do
  target=$(realpath -m -- "$link")
  if [ -d "$target" ]; then
    case "$target/" in
      "$PROJECT"/*) ;;
      *) printf '  %s -> %s\n' "${link#"$PROJECT"/}" "$target" ;;
    esac
  fi
done | head -n 10)
if [ -n "$found" ]; then
  printf 'Links under the project lead to folders outside it; mounting a pack would walk them (remove them):\n%s\n' "$found" >&2
  exit 1
fi
