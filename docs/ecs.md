# ECS: rules and traps

How this game uses its ECS (GECS, through `KitSession`): the rules, the
traps, and what was measured.

## Rules

### Where state lives

| The state is… | Put it… |
| --- | --- |
| About one entity | On a component of that entity. Never in a system's dictionary keyed by entity: it has to be cleared by hand and nothing else can see it. |
| A pointer from one entity to another, where either may go | A relationship (`session.link`). GECS drops it when either end is removed. |
| A value that flips often (a drive's throttle, a gun's reload tick) | A field on a component, read in the loop. |
| A kind of thing, or a state that lasts (a tank's gun, stuck, wrecked) | A component a query can ask for. |
| About the whole map (the ground, the weather, the match) | A component on the map's entity (`TtwGame.MAP_ALIAS`). |
| A handle to the body's own child node | A variable on the body script, resolved once in `_ready`. Not a component. |

A tag component for a state that changes every few ticks costs an archetype
move each time. `TtwStuck` is a tag because it is added when a vehicle bogs
down and taken off when it is free; `TtwDrive.stall_meter` is a field because
it changes every tick.

### Asking for entities

```gdscript
for entity in session.view([TtwDepot, KitBody]): ...
```

- The array is shared: read it, never change it. If the loop removes
  entities, loop over `.duplicate()`.
- Never `world.query…execute()` in a system. It builds a query every call;
  `view` keeps one per list of components.

### Links

```gdscript
session.link(wrecker, TtwWinching, load)   # replaces any earlier link
session.linked(wrecker, TtwWinching)        # -> the load, or null
session.linked_to(depot, TtwSuppliedBy)     # -> every garage drawing on it
session.unlink(wrecker, TtwWinching)
```

| Relation | From → to | Kept by |
| --- | --- | --- |
| `TtwSuppliedBy` | garage or helipad → the depot it draws on | `TtwGarageSystem` |
| `TtwWinching` | wrecker → what its cable is on | `TtwWinchSystem` |
| `TtwTowing` | wrecker → what it tows | `TtwTowSystem` |
| `TtwAttacking` | unit → the target it was ordered to attack | `TtwGunSystem` |

- An entity has at most one link of each kind.
- `linked_to` is a kept query: call it every tick.
- `linked` is a lookup on one entity (2 to 4 µs). In a loop over many, ask
  once before it.

### Writing a system

Two shapes are in use; pick by whether the work is per entity or per tick.

```gdscript
# Per entity: GECS hands over the matches. One call per archetype.
func query() -> QueryBuilder:
    return q.with_all([TtwGun, KitBody])

# Per tick: needs every entity at once, or none. Matches the map's entity.
func query() -> QueryBuilder:
    return q.with_all([TtwGround])
func process(_map, _components, _delta) -> void:
    for entity in session.view([TtwVehicle, KitBody]): ...
```

- **Look an entity's parts up once.** A system that visits the same entities
  every tick can keep one row per entity, rebuilt only when
  `world.cache_version` moves (`TtwSeparationSystem` does).
- **Check the body is still there** (`session.body_of`) before using it: an
  entity or its body can go mid-tick.
- **Leave early.** Test the cheap field first, the lookup second.
- **Do not allocate per tick** what does not change: query parameter
  objects, shapes and formatted names belong in constants or members.
- **Remove entities through the session** (`session.remove_entity`,
  `session.retire`), never the world directly: identity, the body's meta and
  kept link queries are cleaned up there.

### Authoring components

- Units and structures author components as slots on their scene; binding
  copies each with `KitSlots.take`. Nothing else may share a component
  between entities. What a kind needs beyond its slots goes in the scene's
  `extra_components` (a tank's gun); what a kit adds when a unit is built is
  made by `TtwKits.parts`.
- `Resource.duplicate()` leaves arrays and dictionaries shared between the
  copies. `KitSlots.copy` copies those too. Use it for any component copy.
- Never write into a slot's resource from code: it belongs to every
  instance of the scene. Change the bound entity's own copy.

## Traps

- **A new `class_name` needs `godot --headless --path . --import`** before
  tests can see it. Without it every script that mentions it fails to parse.
- **Node metadata is saved into scenes.** Bookkeeping kept with `set_meta` on
  a body ends up in its prefab and misleads every instance. Keep it elsewhere.
- **A resource made in `_init` is packed into every scene** that holds the
  node, because it differs from the script's default (null). Instance
  prefabs instead.
- **Assigning an untyped array through a `Variant`** to a typed array
  property fails at run time. Use `.assign([...])`.
- **Do not keep runtime-built resources in a `static var`**: they outlive the
  session and show up as leaks at exit. Instance ids and plain values are
  fine.
- **No links out of the project folder.** The engine walks every folder
  under the project when it mounts a resource pack, following links and
  ignoring `.gdignore`: a link to `/` (a Wine prefix's `z:` drive under
  `builds/`) makes that walk never end. `run-tests.sh` refuses to start
  while such a link is there (`ci/check-links.sh` lists them).
- **`run-tests.sh` fails on any engine `ERROR:` line** even when every
  assertion passes. Read the exit code, not the summary line.
- **`process()` is called once per archetype the query matches.** Work that
  is not about the entities handed over (a loop over `session.view(...)`,
  a service every N ticks) then runs as many times a tick as there are
  archetypes: a depot about to explode is another archetype, and every kit
  makes a truck one. Give such a system the map's entity as its query
  (`[TtwGround]`) or keep the tick it last ran.
- **Packed arrays are shared, not copied, when assigned.** A loader that
  hands a saved array to the terrain and then lets the game write into the
  terrain changes the save too. `duplicate()` what must stay as it was.
- **`Engine.time_scale` scales each physics tick's delta**, it does not run
  more ticks: systems that use `delta` go faster per tick than those that
  count ticks, so the game is a different game. Speed a run up with more
  ticks (`--fixed-fps`, the test runner), never with the time scale.
- **GECS (fixed in `addons/gecs`): an entity added to an archetype that
  already existed did not move `cache_version`**, so a view built earlier
  missed it until some other change. `World._add_entity_to_archetype` now
  bumps it (`test_session.gd` covers it).
- **Loading in the background** (`ResourceLoader.load_threaded_*`), which this
  game does not do: in Godot 4.7.2 a script first compiled on the loader
  thread leaks an engine object at exit for each `preload` it has to read,
  and headless, a texture loaded on the main thread during a background load
  is now and then lost. Compile scripts and load textures on the main thread
  before the request, or after it has arrived.

## Measured here

### The ground at scale (feat/perf)

`./run-probe.sh res://tests/render/perf_probe.tscn`: 100 vehicles driving on a
128×128-tile map with its river, a crater every 30 frames, 300 ticks; µs per
tick from GECS's own timers. One row per commit, each measured on that
commit. Whole-frame times on this machine are noise (software renderer,
other jobs); the per-system rows repeat to within a few percent when it is
quiet and read 30 to 40% high when it is not, so compare rows taken together.

| After | water | drive | tracks | settle | wakes | effects | total | of a tick |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| before | 57648 | 2726 | 10998 | 4937 | 211 | 839 | 77358 | 464% |
| water: floors per changed tile | 3508 | 2250 | 10512 | 4946 | 160 | 720 | 22096 | 133% |
| water: surface once, levels by halving | 1237 | 2236 | 10493 | 4915 | 160 | 717 | 19757 | 119% |
| stamps: a press scans its strip | 1053 | 2262 | 3687 | 5013 | 157 | 716 | 12888 | 77% |
| terrain: tile size read once | 1076 | 1827 | 3242 | 4628 | 153 | 655 | 11580 | 69% |
| tracks: contacts read by index | 1080 | 1831 | 2500 | 4566 | 153 | 646 | 10776 | 65% |
| settle: local names, mark what changed | 1079 | 1880 | 2460 | 1419 | 152 | 643 | 7633 | 46% |
| drive: one cell lookup a tick | 1067 | 1091 | 2466 | 1429 | 150 | 650 | 6854 | 41% |
| effects, wakes: query columns, cadence | 1090 | 1130 | 2509 | 1443 | 60 | 394 | 6626 | 40% |

The same map with no vehicles: drive, tracks, wakes and effects 3 to 4 µs
each; water 650 µs and settle 425 µs, which is the river (below).

What each was:

- **Water floors.** Every changed cell rect was merged into one dirty rect,
  so vehicles spread over the map made the water recompute every tile's
  floors (a million cells) each step. The terrain now keeps a flag per tile
  (`floors_stale`) and the water redoes a flagged tile when it is about to
  read it. This also corrects something: slumps and ruts springing back
  change the relief quietly and used to reach the floors only when an
  unrelated press widened the merged rect over them. Settle now flags those
  tiles, so floors always match the cells when read. The result is
  bit-identical to the old code with every floor refreshed each step.
- **Water step.** `level_of()` ran five times per wet tile (itself and four
  neighbours); each tile's surface is now worked out once per step, in
  doubles. A tile partly under water tried every count of covered cells in
  turn; the running sums are kept beside the sorted cells and the count is
  found by halving.
- **Stamps.** A press tested a square about 17 cells across (289 cells) for
  a strip of about 40. It scans the strip's bounds along x and y, same row
  order, same float32 test per cell.
- **Tile size.** `Kit2D.tile_size()` reads the project settings on every
  call, and every `cell_of` / `tile_of` / `elevation_at` made one. A terrain
  keeps `tile_size_px` and `cell_size_px`.
- **Settle.** About 1600 visits a tick; each reached the layers through the
  terrain, built Vector2i arrays for the slump neighbours and wrote the
  dirty-chunk Dictionary whether or not anything changed.
- **Drive.** `water_depth_at` ran three times per vehicle, the grade made 16
  clamped tile reads through calls, three speeds asked for the tile size.

All of it was checked against a run of the probe's scene on fixed ticks
(300 ticks, craters on set ticks) that hashes every terrain layer, the
water's depths and fluxes, the settling queue and each vehicle's state: every
change after the first leaves every hash as it was.

### Mechanics and the RTS shell (feat/mechanics)

The same probe, a third of the vehicles driving routes: pilot 246 µs a tick
(33 orders, routes planned again every 3 s at about 0.5 ms a route), paths
860 µs (64 queued tiles and 16 swept a tick at about 5 µs a tile, plus the
grid's 90 ms build on the first tick spread over the run), winch and tow 5 to
6 µs idle. Total 8.1 ms (49% of a tick). With 256 queued and 64 swept a tick
paths took 2.3 ms, for routes no better in play, so the budgets were cut.

### Units (feat/units)

The same probe with every unit kind on two sides firing at each other (a
third driving routes, the helicopters flying): flight 111 µs a tick (18
aircraft), guns 327 µs (targets looked for every 10 ticks per gun, shots
flying), ballistics 127 µs, kits 248 µs (pumping and serving), specials
74 µs. Total 8.4 ms (50% of a tick).

### Separation (perf/separation)

The same probe (84 of the 100 units are ground vehicles; some pair touches on
about half the ticks). Separation alone, µs per tick, before and after on the
same quiet machine:

| Scene | before | after |
| --- | ---: | ---: |
| The probe | 505 to 530 | 95 to 105 |
| All 84 sent to one spot (pressed together most ticks) | 532 | 121 to 154 |
| All 84 started in one overlapping block, some out of fuel | 929 | 555 to 580 |
| 400 units (334 vehicles), touching every tick | 2677 | 723 |
| No vehicles | | 6 |

Total for the probe 10.4 ms to about 9.7 ms.

- **Before:** every tick it asked each vehicle for its body and its
  `TtwVehicle`, asked whether it could move (`has_component` and
  `TtwWinchSystem.immobile`: four more lookups and the fuel), and built a
  Dictionary of Arrays for the grid, then made nine Dictionary lookups per
  vehicle with a `Vector2i` each.
- **Rows.** One row per vehicle (entity, body, radius), made again only when
  `world.cache_version` has moved *and* the view no longer equals the rows'
  entities (one array compare, 0.8 µs). The version moved on 77 of 300 ticks
  (shots, orders); the rows were made again on 10. A body that leaves the
  tree while its entity stays is seen in the tick's loop and the rows are
  made without it, every tick until it is back.
- **Cells.** Positions go into a `PackedVector2Array` (pushes are written to
  it and to the body, so the pass never reads a node twice). Each vehicle is
  one number, `(cell row, cell column, index)`, in a `PackedInt64Array`
  sorted by the engine (0.4 µs for 84). The three cells of a row are then one
  run of that array, found with one `bsearch` (0.03 µs): three per vehicle
  for its nine cells, in the old order (row, column, index), with the old
  quirk kept (a vehicle's own cell is where it is now, the others' where
  they were gathered).
- **Holding ground** is asked only of a vehicle that overlaps another, once
  a tick.
- Of the 100 µs left, 43 is reading 84 positions and sorting, the rest the
  pass.

Checked like the ground: the probe's scene on fixed ticks, hashing every
vehicle's position, heading, speed and order each tick and the terrain's
layers at the end, for the four scenes above. Every hash is as it was.

Drive and tracks do not depend on it: with the separation system switched
off they read 1094 to 1211 µs and 2338 to 2443 µs, with it on 1104 to 1245
and 2364 to 2574 in the same sittings. A reading of 0.95 and 2.16 ms against
1.13 and 2.46 is the machine, not the pushes.

### What a packed array costs to reach

200,000 accesses, Godot 4.7.2:

| Access | µs |
| --- | ---: |
| `local[i] = v` | 2018 |
| `terrain.layer[i] = v` | 6747 |
| `local[i]` | 4072 |
| `terrain.layer[i]` | 8433 |

`var deform := terrain.deform` does not copy: the local shares the member's
storage, and a write through it is seen through the member. A loop over
cells takes the layers into locals first. (What does copy is a packed array
inside a container, `container[k][i] = v`.)

A float that must match the old arithmetic exactly is kept in a
`PackedFloat64Array`; a `PackedFloat32Array` rounds it. `a - b - c` is not
`a - (b + c)`: regrouping while inlining moved the water's hashes.

### What did not help

- **A press's x range per row** (the strip's crossing of each row of cell
  centres, instead of its bounds along x): 14.1 µs a press against 14.0. The
  rows cut about a third of the cells from a diagonal press and cost as much
  to work out.
- **Typed copies of the material tables in settle** (`PackedFloat64Array` of
  `REPOSE`, `REBOUND`), and `TtwMaterials.WORN` read in place in the stamps
  instead of calling `effective()`: 2 to 7%, inside the run-to-run spread of
  the timing. Not kept.
- **Separation: a sweep along x before the pass** (sort by x, test each
  vehicle against those within two radii, and skip the pass when no pair
  overlaps). It costs about 25 µs and saves the pass's 55 only on a tick
  where nothing touches: 100 µs either way on the probe, and 20 µs worse
  with the vehicles pressed together. Not kept.
- **Separation: the physics engine.** One `intersect_shape` per vehicle
  against the others' areas (as the obstacle push does for structures) is
  0.73 µs a query, 61 µs for 84, before any pushing: more than the sorted
  cells' whole pass. An `Area2D` on every vehicle costs the physics step
  about 40 µs a tick for 84 that move, and would leave the system idle
  until two touch, but its signals arrive after the step: an overlap made
  this tick by the drive would be parted on the next, which is not what the
  pass does now (two on one spot are parted within the tick). Not done.
- **Not tried: a press's cell test in doubles, summed per row and column.**
  The test is float32 (`Vector2`), and a cell exactly on an edge (a berm
  5 px from an axis-aligned patch) can fall on the other side in doubles, so
  it would change which cells get what.

### What is left, and why

- **Tracks, 2.5 ms.** About 136 presses a tick at 13 to 14 µs: half testing
  some 70 cells, most of the rest writing the 33 that get something. Plus
  about 6 µs per vehicle a tick that no press needs (contacts, depth under
  each, the hull's water and grime). GDScript's floor for this shape.
- **Settle, 1.4 ms.** 1630 visits at about 0.9 µs. 38,912 of the queued
  cells are the river's and never leave: they stay soaked, and its bed is
  sand cut into `deform`, which springs back a little every visit
  (`REBOUND` of sand). That also flags about 255 river tiles a step for the
  water, which is most of its 1.1 ms. If the river bed is not meant to heal,
  cutting it some other way than as a rut would take both down.
- **Water, 1.1 ms.** Redoing a tile's floors exactly is 64 cells in order.
  Keeping a running sum per tile as cells change would be about 30 times
  less work but would not round the same way; not done.
- **Drive, 1.1 ms.** About 10 µs a vehicle, 4 of them `get_component` and
  `has_component`. Its matches' columns cannot be used as in tracks, because
  it adds and removes components (stalled, flooded, wrecked) mid-loop; a row
  per vehicle rebuilt when `world.cache_version` moves would save about 0.3 ms.
- **Chunk uploads** are outside the systems: `chunk_image` is 293 µs per
  chunk (7 layers, a slice and an append per row), up to 8 chunks a frame.
