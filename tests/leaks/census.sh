#!/bin/bash
# Diagnose steady growth: which object classes does the game own more of after
# more map churn? Runs map_churn.gd in census mode at two round counts and
# diffs the engine's per-class exit dump.
#   tests/leaks/census.sh [low-rounds] [high-rounds]
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$PROJECT_DIR"
ENGINE=${KIT_TEST_ENGINE:-${GODOT:-godot}}
LOW=${1:-4}
HIGH=${2:-12}
RUN_DIR=$(mktemp -d "${KIT_TEST_RUN_ROOT:-$PROJECT_DIR/reports/leak-runs}/census.XXXXXXXX")
export LC_ALL=C XDG_CONFIG_HOME="$RUN_DIR/config" XDG_DATA_HOME="$RUN_DIR/data" XDG_CACHE_HOME="$RUN_DIR/cache"
PHYSICS_HZ=$(sed -nE 's/^common\/physics_ticks_per_second=([0-9]+)$/\1/p' project.godot)
for rounds in "$LOW" "$HIGH"; do
  LEAK_CENSUS=1 LEAK_ROUNDS=$rounds LEAK_MAPS=${KIT_LEAK_MAPS:-} "$ENGINE" --headless --path "$PROJECT_DIR" --verbose \
    --audio-driver Dummy --fixed-fps "${PHYSICS_HZ:-60}" -s res://tests/leaks/map_churn.gd > "$RUN_DIR/census-$rounds.log" 2>&1 || true
done
python3 -I - "$RUN_DIR/census-$LOW.log" "$RUN_DIR/census-$HIGH.log" "$LOW" "$HIGH" <<'EOF'
import re, sys
from collections import Counter
def census(path):
    text = re.sub(r"\x1B\[[0-?]*[ -/]*[@-~]", "", open(path, errors="replace").read())
    return Counter(re.findall(r"Leaked instance: (\w+)", text))
low, high = census(sys.argv[1]), census(sys.argv[2])
extra = int(sys.argv[4]) - int(sys.argv[3])
rows = sorted(((high[c] - low[c], c) for c in set(low) | set(high) if high[c] != low[c]), reverse=True)
print(f"Classes owned by the game that grew over {extra} extra rounds:")
for delta, name in rows:
    print(f"  {name:32} {low[name]:6} -> {high[name]:6}  ({delta / extra:+.2f}/round)")
if not rows:
    print("  none")
def paths(path):
    text = re.sub(r"\x1B\[[0-?]*[ -/]*[@-~]", "", open(path, errors="replace").read())
    return set(re.findall(r"Resource still in use: (\S+) \((\w+)\)", text))
only_high = sorted(paths(sys.argv[2]) - paths(sys.argv[1]))
print(f"Resources held only after the longer run ({len(only_high)}):")
for path, kind in only_high[:60]:
    print(f"  {path} ({kind})")
EOF
echo "Logs: $RUN_DIR"
