#!/bin/bash
# Checks every shader program the game compiles fits 16 texture units, by
# the final GLSL the driver gets (Godot's own code and ours): runs the title,
# each skirmish map with the computer playing both sides, the Mud Lab, and
# the probes that draw every effect (fire, smoke, heat haze, trees, units,
# a truck reflected in the river) under Mesa with MESA_SHADER_CAPTURE_PATH,
# then counts each captured program (tools/shader_units.py). Fails if any
# is over, or if a shader of the game's (shaders/) was never compiled, so
# never counted. What each shader uses: docs/ground.md, "Texture units".
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
capture() {
  # A fresh user data folder: a cached program binary is not compiled, so
  # Mesa would not see it.
  XDG_DATA_HOME="$OUT/data" MESA_SHADER_CAPTURE_PATH="$OUT/capture" \
    timeout 600 "${RUN[@]}" "$ENGINE" --path . --audio-driver Dummy --resolution 1280x720 \
    "$@" >>"$OUT/game.log" 2>&1 || true
}
run() {
  capture --quit-after 600 "$@"
}
run res://game/rts/title.tscn
for map in river snowfield dunes; do
  run res://main.tscn -- --map="$map" --watch
done
run res://tools/mud_lab.tscn
# The probes end themselves once they have drawn what they show.
for probe in fx_probe world_probe units_probe water_probe; do
  capture "res://tests/render/$probe.tscn"
done
python3 tools/shader_units.py "$OUT/capture" --limit "${KIT_SHADER_UNIT_LIMIT:-16}" --shaders shaders | tee "$OUT/units.txt"
