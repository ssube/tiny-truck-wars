#!/bin/bash
# Imports a project's assets: ci/import.sh [project dir] (default: this one).
# The project's custom theme (gui/theme/custom) is loaded as the engine
# starts, and on a fresh checkout its fonts and icons are not imported yet:
# that start logs an ERROR for each of them. The import runs with the setting
# taken out of project.godot, which is put back as it was on any exit.
# (An override.cfg does not help: the editor, which --import runs, does not
# read one.)
# Godot 4.7.2 now and then dies as the editor shuts down after the import
# has finished (about 1 run in 10 on a fresh copy: a worker thread and the
# main thread both freeing memory; SIGSEGV or SIGABRT). A run killed by a
# signal is run again, up to three times; the rerun finds the work done and
# takes seconds. Any other failure is not retried. Uses $KIT_TEST_ENGINE,
# else godot.
set -euo pipefail
PROJECT=$(cd -- "${1:-$(dirname -- "$0")/..}" && pwd)
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
SETTINGS="$PROJECT/project.godot"
KEPT=$(mktemp)
cp -p "$SETTINGS" "$KEPT"
trap 'cp -p "$KEPT" "$SETTINGS"; rm -f "$KEPT"' EXIT
sed -i '/^theme\/custom=/d' "$SETTINGS"
for attempt in 1 2 3; do
  code=0
  "$ENGINE" --headless --path "$PROJECT" --import || code=$?
  if [ "$code" -lt 128 ]; then
    exit "$code"
  fi
  echo "The engine was killed by signal $((code - 128)) (attempt $attempt); importing again." >&2
done
exit "$code"
