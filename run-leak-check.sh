#!/bin/bash
# Resource-leak gate on the real game path (no test-runner exit cleanup).
#   ./run-leak-check.sh                 headless: idle start/quit, then map churn
#   KIT_LEAK_RENDERER=1 ./run-leak-check.sh   same, on a real GL renderer (xvfb)
#   KIT_LEAK_ROUNDS=8 KIT_LEAK_WARMUP=4 KIT_LEAK_MAPS=river,snowfield,dunes
# Fails on any engine exit-leak report (ObjectDB instances, resources still in
# use, RID/GL allocations) and on any growth in objects, resources, nodes,
# orphans or ECS archetypes across the rounds after warmup. On failure it
# prints the leaked classes and resource paths to start the diagnosis.
# Runs on simulated time (--fixed-fps = physics tick rate), like run-tests.sh.
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  printf 'Test engine is not executable: %s\n' "$ENGINE" >&2
  exit 127
fi
RUN_ROOT=${KIT_TEST_RUN_ROOT:-"$PROJECT_DIR/reports/leak-runs"}
mkdir -p "$RUN_ROOT"
RUN_DIR=$(mktemp -d "$RUN_ROOT/run.XXXXXXXX")
chmod 700 "$RUN_DIR"
export LC_ALL=C
export XDG_CONFIG_HOME="$RUN_DIR/config" XDG_DATA_HOME="$RUN_DIR/data" XDG_CACHE_HOME="$RUN_DIR/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
PHYSICS_HZ=$(sed -nE 's/^common\/physics_ticks_per_second=([0-9]+)$/\1/p' project.godot)
PHYSICS_HZ=${PHYSICS_HZ:-60}
export KIT_TEST_FIXED_FPS="$PHYSICS_HZ"
printf 'KIT_LEAK_RUN_DIR=%s\n' "$RUN_DIR"

ARGS=(--path "$PROJECT_DIR" --verbose --audio-driver Dummy --fixed-fps "$PHYSICS_HZ" -s res://tests/leaks/map_churn.gd)
if [ "${KIT_LEAK_RENDERER:-0}" = 1 ]; then
  BASE=(xvfb-run -a -s '-screen 0 1280x720x24' "$ENGINE" --resolution 1280x720)
else
  BASE=("$ENGINE" --headless)
fi

STATUS=0
run_scenario() {
  local name=$1 rounds=$2
  local log="$RUN_DIR/$name.log"
  set +e
  # A driver that fails to compile or errors mid-run never quits: cap the run
  # (real seconds; a clean run takes a few).
  LEAK_ROUNDS=$rounds LEAK_MAPS=${KIT_LEAK_MAPS:-} timeout "${KIT_LEAK_TIMEOUT:-120}" "${BASE[@]}" "${ARGS[@]}" > "$log" 2>&1
  local code=$?
  set -e
  if ! python3 -I "$PROJECT_DIR/tests/leaks/analyze_leaks.py" "$log" "$name" "$code" "${KIT_LEAK_WARMUP:-4}"; then
    STATUS=1
  fi
}

run_scenario idle 0
run_scenario churn "${KIT_LEAK_ROUNDS:-8}"
if [ "$STATUS" -eq 0 ]; then
  echo 'Leak check clean.'
else
  echo "Leak check failed; logs in $RUN_DIR" >&2
fi
exit "$STATUS"
