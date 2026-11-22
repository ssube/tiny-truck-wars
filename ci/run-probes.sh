#!/bin/bash
# Runs every render probe (tests/render/*.tscn) through run-probe.sh, one at a
# time, and fails if any of them does. Each probe's log is kept in
# reports/probe-runs/<name>.log.
#   ci/run-probes.sh                   all probes
#   ci/run-probes.sh demo_probe ecs_probe
#   KIT_PROBE_TIMEOUT=600              seconds allowed per probe
set -uo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
LOGS="$PROJECT_DIR/reports/probe-runs"
mkdir -p "$LOGS"
if [ "$#" -gt 0 ]; then
  PROBES=("$@")
else
  PROBES=()
  for scene in tests/render/*.tscn; do
    PROBES+=("$(basename "$scene" .tscn)")
  done
fi
FAILED=()
for name in "${PROBES[@]}"; do
  start=$SECONDS
  timeout "${KIT_PROBE_TIMEOUT:-600}" ./run-probe.sh "res://tests/render/$name.tscn" > "$LOGS/$name.log" 2>&1
  code=$?
  printf '%-32s exit %3d  %4ds\n' "$name" "$code" "$((SECONDS - start))"
  if [ "$code" -ne 0 ]; then
    FAILED+=("$name")
    echo "---- last lines of $name ----"
    tail -n 40 "$LOGS/$name.log"
    echo "----"
  fi
done
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "Probes failed: ${FAILED[*]} (logs in $LOGS)" >&2
  exit 1
fi
echo "All ${#PROBES[@]} probes passed."
