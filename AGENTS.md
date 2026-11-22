# Repository working guidelines

Tiny Truck Wars is a small top-down RTS on a small ECS core (`kit/`: the
session, ECS helpers, the test harness) over GECS. Most of the work goes into the
ground: mud, ruts, craters and water that are simulated on the CPU, drawn with
parallax depth, and slow vehicles down and make them burn more fuel. The plan is
`docs/plan.md`.

## Let the current request control execution

When the user corrects scope or method, replace the affected plan, queued work,
tests and acceptance. Test the changed source; never present an older-source run
as validation of new edits. Use only applicable review and delivery requirements.
Direct execution is the default; delegation requires authorization.

## Keep test timing event-exact

Do not poll process or physics frames to discover readiness or completion, and do
not use an arbitrary frame count as a readiness proxy. Subscribe before triggering
an operation (`tests/support/ui.gd` `observe`), resume from its completion signal,
and use a bounded timeout only to fail a missing event. Preserve request identity
and expose rejection reasons.

Advance gameplay only with `Simulation.physics_ticks(tree, count, timeout, on_tick)`
(`tests/support/simulation.gd`). Compute each tick budget from what it covers
(distance / speed, a shot's flight time, a reload). Frame-exact gameplay tests drive
and assert explicit ticks and input-window boundaries, including the valid tick and
the adjacent invalid ticks. Renderer evidence may await `frame_post_draw`; it must
not substitute tick counts for a draw. Teardown is `queue_free()` with no await.

## Keep tests on simulated time

`run-tests.sh` passes `--fixed-fps` equal to `physics/common/physics_ticks_per_second`:
each engine frame advances exactly one physics tick with no wall-clock sync, so a
600-tick test takes well under a second instead of 10 s. A full run is ~14 s; a
GdUnit case costs ~20 ms. Slowness almost always means something is waiting on the
wall clock, not that GdUnit or GDScript is slow. To keep it that way:

- Run every GdUnit suite through `run-tests.sh`. A new launcher or CI job must pass
  the same `--fixed-fps`; without it physics falls back to real time (~10x slower).
- Timeouts (`create_timer`, `observe(...).wait`, `physics_ticks`) count simulated
  seconds. Don't widen one to "fix" slowness; under fixed fps it costs no wall time
  until it fails.
- Game and test code must not depend on wall time: no `Time.get_ticks_*`,
  `Time.get_unix_time_*`, `OS.delay_*` or `OS.get_ticks_*` in gameplay logic or
  completion checks, and no busy-waits. Derive time from `session.tick` /
  `Engine.physics_ticks_per_second`. Cosmetic-only uses (a UI pulse) are fine.
- Work that finishes in real time off the main loop (`ResourceLoader.load_threaded_*`,
  `Thread`, `WorkerThreadPool`, HTTP, subprocesses) must signal completion and be
  awaited as an event. Its simulated-time timeout must cover the real duration;
  uncapped frames burn through it much faster than wall time passes.
- Keep tick budgets computed from what they cover (see above); a padded budget is
  cheap in wall time but hides regressions.
- Render probes (`tests/render/*.tscn` via `run-probe.sh`) are not GdUnit suites and
  run in real time with real draws; keep gameplay assertions out of them.
- Before speeding up the runner (parallel shards, a persistent engine, native code),
  measure: sort per-case `time` in the run's `gdunit/report_1/results.xml`. Case
  times that are exact multiples of 1/60 s mean wall-clock ticks, not runner cost. A
  persistent engine that hot-reloads scripts is off-limits: preloaded consts, static
  vars and the `class_name` cache survive a reload, so it would test stale source.

## No snapshot tests

Test observable behavior and meaningful structural properties, not historical
output: no asserting file bytes/hashes, captured scene inventories or rendered
images merely because a previous version produced them. Every assertion should
express a current requirement and the defect it catches.

## Running tests

```sh
KIT_TEST_HEADLESS=1 ./run-tests.sh res://tests/unit          # gameplay/unit suites
KIT_TEST_HEADLESS=1 ./run-tests.sh res://tests/integration
KIT_TEST_HEADLESS=1 KIT_TEST_METHOD=test_x ./run-tests.sh res://tests/unit/test_y.gd
./run-probe.sh res://tests/render/boot_probe.tscn            # real renderer probe (xvfb)
ci/run-probes.sh                                             # every probe
./run-leak-check.sh                                          # exit leaks + map-churn growth
```

CI (`.forgejo/workflows/ci.yml`) runs the unit and integration suites, the leak
check and every render probe on each push, inside the image built from
`ci/Containerfile` (tagged with a hash of the file). On GitHub,
`.github/workflows/` runs the suites on each push and builds the release
exports from a `v*` tag. The probes' pictures (`reports/render/`) are kept as an artifact for
looking a change over.

A run is only clean if the wrapper exits 0: it rejects any engine `ERROR:`,
`SCRIPT ERROR:` or `SHADER ERROR:` line even when every assertion passed.
After adding new assets or a `class_name`, run `ci/import.sh` first.

Every shader fits 16 texture units by ANGLE's count: Godot's own 2D code
names 4 textures before ours. `tests/unit/test_shaders.gd` and
`ci/shader-units.sh` check it. What each shader uses, and how to add a
texture without a new unit, is in `docs/ground.md`, "Texture units".

`run-leak-check.sh` runs the real game path (start, a simulated second on a map,
free, several rounds) and fails on any engine exit-leak report or growth after
warmup. Don't keep runtime-built resources (images, textures) in a `static var`.

## Use the ECS the way the kit does

The rules and traps are in `docs/ecs.md`. In short:

- State about one entity goes on a component of that entity, never in a
  system's dictionary. A pointer between two entities is a relationship
  (`session.link`). A value that flips often is a field; a kind of thing or a
  lasting state is a component a query can ask for.
- Ask for entities with `session.view([...])`. Never build a query in a system,
  and never change the array it returns.
- Adding or removing a component or link moves the entity between archetypes:
  do it when something changes, not every tick.
- Remove entities through `session.remove_entity` / `session.retire`.
- Every entity on a map is an instance of a scene under `prefabs/`.
- A change meant to save time is measured before and after, and kept only if it
  shows. Record what did not work in `docs/ecs.md`.

## The ground

- The terrain layers (`game/terrain/`) are plain packed arrays on the CPU and
  are the truth: gameplay and tests read them, and only changed rectangles are
  uploaded to textures for the shaders.
- **The simulation never uses LOD.** Stamping, mud, water, wetness and movement
  cost run at full resolution and full rate over the whole map wherever the
  camera is. Only drawing gets cheaper with distance from the camera.
- Mud and water are conserved: a stamp moves volume, it does not make or
  destroy it (sources and sinks excepted). Tests check the sums.
- Distances are authored in tiles (`Kit2D`); the tile is 16 px.

## Structure

- `kit/` the core: `session.gd`, `slots.gd`, `kit2d.gd`, `testing/`.
- `game/` the game: `terrain/`, `fx/`, `units/`, `structures/`, `world/`,
  `combat/`, `systems/`, `rts/` (the skirmish, its maps, the AI, saving).
- `shaders/`, `prefabs/{unit,structure,world}/`, `tools/` (the Mud Lab).
- `tests/{unit,integration,render,leaks,support}`.
- Sprites come from PixelLab (`tools/pixellab_download.py` into the ignored
  `import_dump/`); art for anything missing is written up as prompts in
  `docs/art-prompts.md` for the user to generate.
