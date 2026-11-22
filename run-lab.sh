#!/bin/bash
# Runs the Mud Lab (the ground sandbox) in a 1920x1080 window on the primary
# monitor, as run-game.sh runs the game; it takes the same options.
#   ./run-lab.sh
#   ./run-lab.sh --fullscreen
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TTW_SCENE=res://tools/mud_lab.tscn exec "$PROJECT_DIR/run-game.sh" "$@"
