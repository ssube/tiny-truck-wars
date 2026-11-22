#!/bin/bash
# Runs the game (its title screen) in a 1920x1080 window on the
# primary monitor: its corner is found with xrandr; without xrandr (or a
# primary) it opens on screen 0.
#   ./run-game.sh                       the title screen: a map, the Mud Lab or a saved game
#   ./run-game.sh --fullscreen          fullscreen on the primary monitor
#   ./run-game.sh -- --map=dunes        game arguments after -- (--map=river|snowfield|dunes,
#                                       --watch, --load=<path>)
#   GODOT=/path/to/godot ./run-game.sh  another engine (default: godot on the PATH)
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE=${GODOT:-godot}
WIDTH=1920
HEIGHT=1080

if ! command -v "$ENGINE" >/dev/null 2>&1; then
  printf 'Godot is not executable: %s (set GODOT)\n' "$ENGINE" >&2
  exit 127
fi

ENGINE_ARGS=()
GAME_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --fullscreen) ENGINE_ARGS+=(--fullscreen) ;;
    --) shift; GAME_ARGS=("$@"); break ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# The primary output's geometry, e.g. "2560x1440+1920+0".
PLACE=(--screen 0)
if command -v xrandr >/dev/null 2>&1; then
  geometry=$(xrandr --query 2>/dev/null | awk '/ connected primary/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { print $i; exit } }' || true)
  if [ -n "$geometry" ]; then
    x=$(printf '%s' "$geometry" | cut -d+ -f2)
    y=$(printf '%s' "$geometry" | cut -d+ -f3)
    PLACE=(--position "$x,$y")
  fi
fi

cd "$PROJECT_DIR"
if [ ! -d .godot ]; then
  "$ENGINE" --headless --path . --import >/dev/null 2>&1 || true
fi
exec "$ENGINE" --path . "${PLACE[@]}" --resolution "${WIDTH}x${HEIGHT}" "${ENGINE_ARGS[@]}" -- "${GAME_ARGS[@]}"
