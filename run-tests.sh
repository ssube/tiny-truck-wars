#!/bin/bash
# Runs GdUnit suites in an isolated user-data directory and rejects any run whose
# log contains engine/script/shader errors, even if every assertion passed.
#   ./run-tests.sh [res://tests/<dir or suite.gd>] [extra GdUnit args]
#   KIT_TEST_HEADLESS=1   headless (gameplay/unit suites)
#   KIT_TEST_DISPLAY=:1   real X11 display (render probes); default is xvfb-run
#   KIT_TEST_METHOD=test_x  exact single method (requires one res://...gd suite)
# Every mode runs with the Dummy audio driver: tests never make sound.
# Every mode runs on simulated time (--fixed-fps = physics tick rate): each engine
# frame advances exactly one physics tick with no wall-clock sync, so a test that
# simulates 10 s finishes as fast as the CPU allows. Timeouts are simulated seconds.
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"
RUN_ROOT=${KIT_TEST_RUN_ROOT:-"$PROJECT_DIR/reports/test-runs"}
mkdir -p "$RUN_ROOT"
RUN_DIR=$(mktemp -d "$RUN_ROOT/run.XXXXXXXX")
chmod 700 "$RUN_DIR"
export LC_ALL=C
export XDG_CONFIG_HOME="$RUN_DIR/config"
export XDG_DATA_HOME="$RUN_DIR/data"
export XDG_CACHE_HOME="$RUN_DIR/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
LOG="$RUN_DIR/engine.log"
printf 'KIT_TEST_RUN_DIR=%s\n' "$RUN_DIR"
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  printf 'Test engine is not executable: %s\n' "$ENGINE" >&2
  exit 127
fi
"$PROJECT_DIR/ci/check-links.sh" "$PROJECT_DIR"
SUITE=${1:-res://tests}
if [ "$#" -gt 0 ]; then shift; fi
export KIT_TEST_SOURCE="$SUITE"
export KIT_TEST_REVISION=$(git rev-parse HEAD 2>/dev/null || printf unknown)
export KIT_TEST_SOURCE_DIRTY=0
if [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
  export KIT_TEST_SOURCE_DIRTY=1
fi
if [ -n "${KIT_TEST_METHOD:-}" ]; then
  if [[ "$SUITE" != res://*.gd ]] || [[ "$SUITE" == *'/../'* ]] || [[ "$KIT_TEST_METHOD" != test_* ]] || [ "$#" -ne 0 ]; then
    echo 'Exact method selection requires one explicit res://source.gd and no additional GdUnit options.' >&2
    exit 2
  fi
fi
PHYSICS_HZ=$(sed -nE 's/^common\/physics_ticks_per_second=([0-9]+)$/\1/p' project.godot)
PHYSICS_HZ=${PHYSICS_HZ:-60}
export KIT_TEST_FIXED_FPS="$PHYSICS_HZ"
TELEMETRY="$PROJECT_DIR/kit/testing/resource_report.py"
trap 'status=$?; python3 -I "$TELEMETRY" --finalize "$status" "$RUN_DIR" || true' EXIT
REPORT_RESOURCE="res://${RUN_DIR#"$PROJECT_DIR/"}/gdunit"
REPORT_DIR="$RUN_DIR/gdunit"
if [[ "$RUN_DIR" != "$PROJECT_DIR/"* ]]; then
  REPORT_DIR="$XDG_DATA_HOME/TinyTruckWars/gdunit"
  REPORT_RESOURCE="user://gdunit"
fi
ARGS=(--path "$PROJECT_DIR" --audio-driver Dummy --disable-render-loop --fixed-fps "$KIT_TEST_FIXED_FPS" -s res://kit/testing/resource_bootstrap.gd -a "$SUITE" -c -rd "$REPORT_RESOURCE" "$@")
if [ "${KIT_TEST_HEADLESS:-0}" = 1 ] && [ -n "${KIT_TEST_DISPLAY:-}" ]; then
  echo 'KIT_TEST_DISPLAY conflicts with KIT_TEST_HEADLESS=1.' >&2
  exit 2
fi
if [ "${KIT_TEST_HEADLESS:-0}" = 1 ]; then
  export KIT_TEST_DISPLAY_MODE=headless
  CMD=("$ENGINE" --headless "${ARGS[@]}" --ignoreHeadlessMode)
elif [ -n "${KIT_TEST_DISPLAY:-}" ]; then
  export KIT_TEST_DISPLAY_MODE=native-x11
  export DISPLAY="$KIT_TEST_DISPLAY"
  CMD=("$ENGINE" --display-driver x11 "${ARGS[@]}")
else
  export KIT_TEST_DISPLAY_MODE=xvfb
  CMD=(xvfb-run -a -s '-screen 0 1280x720x24' "$ENGINE" "${ARGS[@]}")
fi
set +e
python3 -I "$TELEMETRY" "$RUN_DIR" "${CMD[@]}" 2>&1 | tee "$LOG"
STATUSES=("${PIPESTATUS[@]}")
set -e
LC_ALL=C sed -E 's/\x1B\[[0-?]*[ -/]*[@-~]//g' "$LOG" > "$RUN_DIR/engine-plain.log"
if grep -Eq '^[[:space:]]*(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$RUN_DIR/engine-plain.log"; then
  echo 'Godot reported errors; the test run is not clean.' >&2
  exit 1
fi
if [ "${STATUSES[1]}" -ne 0 ]; then
  echo 'Could not retain the complete test log; the test run is not verified.' >&2
  exit "${STATUSES[1]}"
fi
if [ "${STATUSES[0]}" -eq 0 ] && [ -z "$(find "$REPORT_DIR" -name results.xml -type f -size +0c -print -quit 2>/dev/null)" ]; then
  echo 'No GdUnit XML report was retained; the test run is not verified.' >&2
  exit 1
fi
exit "${STATUSES[0]}"
