#!/bin/bash
# Checks every shader program the game compiles fits 16 texture units, by
# the final GLSL the driver gets (Godot's own code and ours): runs the title,
# each skirmish map with the computer playing both sides, and the Mud Lab
# under Mesa with MESA_SHADER_CAPTURE_PATH, then counts each captured
# program (tools/shader_units.py). Fails if any is over.
#   ci/shader-units.sh                 (needs Mesa; uses xvfb-run if no DISPLAY)
#   KIT_SHADER_UNIT_LIMIT=16
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
OUT="$PROJECT_DIR/reports/shader-units"
rm -rf "$OUT"
mkdir -p "$OUT/capture" "$OUT/data"
RUN=()
if [ -z "${DISPLAY:-}" ]; then
  RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
fi
run() {
  # A fresh user data folder: a cached program binary is not compiled, so
  # Mesa would not see it.
  XDG_DATA_HOME="$OUT/data" MESA_SHADER_CAPTURE_PATH="$OUT/capture" \
    "${RUN[@]}" "$ENGINE" --path . --audio-driver Dummy --resolution 1280x720 \
    --quit-after 600 "$@" >>"$OUT/game.log" 2>&1 || true
}
run res://game/rts/title.tscn
for map in river snowfield dunes; do
  run res://main.tscn -- --map="$map" --watch
done
run res://tools/mud_lab.tscn
python3 tools/shader_units.py "$OUT/capture" --limit "${KIT_SHADER_UNIT_LIMIT:-16}" | tee "$OUT/units.txt"
