#!/usr/bin/env python3
"""Judge one map_churn.gd run: exit-leak reports and steady-state growth.

python3 -I tests/leaks/analyze_leaks.py <log> <scenario> <exit-code> <warmup-rounds>
Prints a diagnosis (leaked classes, resources still in use, growing counters)
and exits 1 when the run is not clean.
"""
from collections import Counter
import json
import re
import sys

# Engine shutdown reports. Any of these means something outlived the game.
EXIT_LEAKS = [
    re.compile(r"ObjectDB instances were leaked at exit"),
    re.compile(r"resources still in use at exit"),
    re.compile(r"RID allocations of type .* were leaked at exit"),
    re.compile(r"Texture with GL ID of \d+: leaked"),
    re.compile(r"Pages in use exist at exit"),
]
ERRORS = re.compile(r"^\s*(ERROR:|SCRIPT ERROR:|SHADER ERROR:|LEAK_DRIVER_ERROR)")
# Counters that must not grow once warm; caches fill during warmup and then hold.
STEADY = ["objects", "resources", "nodes", "orphans", "tweens", "archetypes", "entities"]
# Randomized soundscape voices in flight at sample time make these jitter by a
# few either way, so they fail on a rising floor (the later rounds' minimum above
# the earlier rounds' maximum) rather than on any difference. The rest are exact.
JITTERY = {"objects", "resources", "nodes", "tweens"}
ANSI = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def main(path, scenario, code, warmup):
    text = ANSI.sub("", open(path, errors="replace").read())
    lines = text.splitlines()
    problems = []
    if code != 0:
        problems.append(f"engine exited with {code}")
    problems += [line.strip() for line in lines if ERRORS.match(line)][:20]
    leaks = [line.strip() for line in lines if any(p.search(line) for p in EXIT_LEAKS)]
    problems += leaks
    samples = [json.loads(line.split(" ", 1)[1]) for line in lines if line.startswith("LEAK_SAMPLE ")]
    done = [line for line in lines if line.startswith("LEAK_DONE ")]
    if not done:
        problems.append("driver never finished (no LEAK_DONE)")
    steady = samples[warmup:]
    if samples and len(steady) < 2:
        problems.append(f"need at least {warmup + 2} rounds to judge steady state, got {len(samples)}")
    for key in STEADY:
        # Each cached stream is one resource (and object); the bounded cache is
        # checked against its limit below, so discount it from the totals.
        discount = key in ("objects", "resources")
        values = [row[key] - (row.get("stream_resources", 0) if discount else 0) for row in steady if key in row]
        if len(values) < 2:
            continue
        label = f"{key} (less cached streams)" if discount else key
        if key in JITTERY:
            half = len(values) // 2
            early, late = values[:half], values[-half:]
            if min(late) > max(early):
                problems.append(f"{label} keeps rising after {warmup} warmup rounds: {values}")
        elif max(values) != min(values):
            problems.append(f"{label} not steady after {warmup} warmup rounds: {values}")
    for row in samples:
        if row.get("cached_streams", 0) > row.get("stream_cache_limit", 1 << 30):
            problems.append(f"audio stream cache exceeded its limit: {row['cached_streams']} > {row['stream_cache_limit']}")
            break

    grown = []
    if len(steady) >= 2 and all("collections" in row for row in steady):
        first, last = steady[0]["collections"], steady[-1]["collections"]
        grown = sorted(((last[k] - first.get(k, 0), k) for k in last if last[k] > first.get(k, 0)), reverse=True)
    print(f"[{scenario}] rounds={len(samples)} " + " ".join(
        f"{k}={samples[-1][k]}" for k in STEADY if samples and k in samples[-1]))
    if not problems:
        print(f"[{scenario}] clean")
        return 0
    for problem in problems:
        print(f"[{scenario}] FAIL {problem}")
    for delta, key in grown[:20]:
        print(f"[{scenario}] growing collection: {key} +{delta} over {len(steady) - 1} rounds")
    classes = Counter(m.group(1) for m in re.finditer(r"Leaked instance: (\w+)", text))
    if classes:
        print(f"[{scenario}] leaked classes: " + ", ".join(f"{n}x{c}" for c, n in classes.most_common(15)))
    in_use = re.findall(r"Resource still in use: (\S+) \((\w+)\)", text)
    if in_use:
        non_script = [f"{p} ({t})" for p, t in in_use if t != "GDScript"]
        print(f"[{scenario}] resources still in use: {len(in_use)} ({len(in_use) - len(non_script)} scripts)")
        for entry in non_script[:25]:
            print(f"[{scenario}]   {entry}")
        if len(in_use) - len(non_script) == len(in_use) or len(non_script) < len(in_use) // 2:
            print(f"[{scenario}] hint: most leaked objects are scripts; look for a static var holding a "
                  "runtime-built object (texture, image, instance) in a loaded script.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])))
