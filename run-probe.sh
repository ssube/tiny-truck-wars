#!/bin/bash
# Runs a render probe on a virtual display with no audio output.
#   ./run-probe.sh res://tests/render/demo_probe.tscn
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
# The engine's own exit status, except that an object left alive at exit
# fails the run: the engine only warns about those.
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
set +e
# A probe whose script fails to load never quits: cap it (real seconds).
timeout "${KIT_PROBE_TIMEOUT:-600}" xvfb-run -a -s '-screen 0 1280x720x24' "$ENGINE" --path "$PROJECT_DIR" --audio-driver Dummy --resolution 1280x720 "$@" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}
set -e
# Like run-tests.sh: an engine, script or shader error fails the probe even
# when the probe itself reports success.
if sed -E 's/\x1B\[[0-9;]*m//g' "$LOG" | grep -qE '^[[:space:]]*(ERROR:|SCRIPT ERROR:|SHADER ERROR:)'; then
  echo "PROBE FAILED: the engine reported errors." >&2
  [ "$CODE" -ne 0 ] || CODE=1
fi
if grep -qE 'leaked at exit|still in use at exit' "$LOG"; then
  echo "PROBE FAILED: the engine reported objects left alive at exit (rerun with --verbose to list them)." >&2
  [ "$CODE" -ne 0 ] || CODE=1
fi
exit "$CODE"
