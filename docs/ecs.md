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
- **A gun's scan is staggered by its entity's object id**
  (`TtwGunSystem`: `(tick + entity.get_instance_id()) % SCAN_TICKS`), and
  object ids depend on every object made before it. A change that makes
  one more node per unit (a shadow, a buffer) moves when guns look for
  targets: the game is still the same from run to run, but a different
  one, and its hashes cannot be compared with the old code's. To check a
  change that should not touch the simulation, hash both with the stagger
  taken from `hash(entity.alias)`.
- **Headless, a texture cannot be read back after an update.** After
  `ImageTexture.update`, `get_image()` there did not return the new image
  for any layer that had changed: what the view uploaded cannot be checked
  that way in a test. Test what was marked for upload instead
  (`test_terrain_view.gd`).
- **A probe that names `TtwSkirmish` as a type and quits without making
  one leaves 33 scripts alive at exit** (`run-probe.sh` fails on that).
  `fps_probe` holds its skirmish as a `TtwGame`.
- **Render probes count frames, and a frame is as long as the machine
  makes it.** Their pictures were set up at about four ticks a frame
  (llvmpipe); a faster renderer shows earlier moments of the game. Each
  probe's `_frames` also waits four ticks for each frame asked for.
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

### Tracks in winter (perf/tracks)

`KIT_PERF_WINTER=1 ./run-probe.sh res://tests/render/perf_probe.tscn`: the
same scene (`tests/support/perf_scene.gd`) with snow on every tile and 40
oil spills, so every press also packs snow and most smear oil. Tracks, µs
per tick, three runs before and two after in one sitting:

| Scene | before | after |
| --- | ---: | ---: |
| Winter | 3019 to 3047 | 2663 to 2681 |
| Mud | 2300 to 2452 | 2450 to 2540 (the machine; the press is unchanged, below) |

The snow press and the oil smear tested every cell of a square around the
patch and read the cell size from the project settings each call. They now
test only the cells of their strip (`TtwStamps.strip_cells`, the bounds the
mud press already used), and the snow depth is read inline. A mud press
through the shared bounds costs what it did (16.9 µs either way in one
process, 20,000 presses each).

What a mud press costs, measured on copies of it in one process (20,000
presses of 2 to 4 px at random headings, the probe's sizes): 1.4 µs to set
up (bounds, four arrays), 1.2 µs to visit about 74 cells doing nothing,
7.7 µs to test them and append the 36 that get something, and about 4 µs to
write the footprint, spread the rest, queue the settling and mark the
chunks (`mark_cells` 0.6 to 1.0 of it; its signal 0.06).

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

### Frames (perf/fps)

`tests/render/fps_probe.tscn` splits a frame into the simulation's ticks, the
scripts' `_process`, the canvas `_draw` callbacks, the renderer and the rest,
with the renderer's own CPU and GPU clocks for each viewport. Three scenes at
1280×720, zoom 3: the stress scene of the perf probe (100 units on 128×128
tiles), the river skirmish with the computer on both sides after a minute of
play (14 units; the minute is played once headless and kept as a save:
`KIT_FPS_SAVE`), and the same map with nobody playing.

```sh
./run-probe.sh res://tests/render/fps_probe.tscn                       # llvmpipe
DISPLAY=:0 godot --path . --audio-driver Dummy --resolution 1280x720 \
    --disable-vsync res://tests/render/fps_probe.tscn                  # the GPU
```

Where a frame went before, on a Radeon 780M with vsync off (ms per frame):

| Scene | fps | ticks | `_process` | `_draw` | renderer | GPU | ticks a frame |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| stress | 45.5 | 12.3 (9.3 a tick) | 5.8 (3.1 chunk uploads) | 2.3 | 1.4 | 12.9 | 1.32 |
| skirmish | 195 | 1.0 (3.3 a tick) | 0.9 | 0.4 | 2.6 | 4.3 | 0.31 |
| idle | 274 | 0.5 (2.1 a tick) | 0.3 | 0.3 | 2.4 | 3.2 | 0.22 |

The skirmish was bound by the GPU (its renderer column is mostly the swap
waiting for it): the terrain shader, run for every screen pixel. The stress
scene was bound by the CPU, and little more than half of that was the
simulation: a frame took 22 ms, so 1.3 ticks had to run in each, and every
millisecond outside the ticks cost about 2.3 in the frame
(`frame = rest / (1 - 0.06 × tick ms)`). At a tick of 16.7 ms that has no
answer: the engine runs its limit of 8 ticks a frame and then the game slows
down (seen here with another job on the machine: 7 fps, 91% of game speed).

Frames per second after each change, each measured on that commit (the
stress scene moves 10% between runs, the others 5%):

| After | stress | skirmish | idle |
| --- | ---: | ---: | ---: |
| before | 45 to 47 | 195 to 200 | 274 to 282 |
| terrain: shaded once per world pixel | 35 to 38 | 708 | 1154 |
| units: drawn again only when they look different | 43.5 | 732 | 1178 |
| terrain: a chunk uploads only the layers that changed | 44.9 | 835 | 1231 |
| fx: bits out of view not drawn, moved less often | 94 to 117 | 863 to 947 | 1185 to 1298 |

On llvmpipe (`run-probe.sh`), before and after all of it: stress 6.5 to 21.4
fps (86% to 100% of game speed), skirmish 16.2 to 65.0, idle 17.3 to 68.8.
The perf probe as it was first run on the Radeon (vsync on): 41.9 to 55.8 fps.

What each was:

- **The ground, per world pixel.** The terrain shader takes one sample per
  world pixel (`floor(local_px) + 0.5`), and at zoom 3 ran for each of the
  nine screen pixels showing it. `TtwTerrainView` draws its chunks into a
  `SubViewport` of one texel per world pixel over what the camera shows and
  puts that on screen enlarged, nearest texel: GPU time 12.9 to 2.5 ms a
  frame in the stress scene, 4.3 to 0.7 in the skirmish. Zoomed out past one
  screen pixel per world pixel the buffer is the screen, texel for pixel.
  At whole zooms the picture is the same pixel for pixel. On its own this
  left the stress scene slower (35 to 38 fps): that frame was never waiting
  for the GPU, and the CPU's side of it read about 2 ms more on that commit
  (ticks 9.3 to 10.0 ms, chunk uploads 3.1 to 3.5, the renderer 1.1 to 1.4),
  which at 1.3 to 1.7 ticks a frame is paid more than twice over. Why the
  ticks read slower there was not found: headless on fixed ticks they cost
  the same before and after (9.7 ms).
- **Units.** A vehicle's shadow was a `_draw` callback run every frame; it is
  a `Polygon2D` turned with the heading. Material parameters are set when
  they change. `_draw` callbacks 2.3 to 1.6 ms in the stress scene.
- **Chunk layers.** A changed chunk uploaded all nine layer textures, at
  about 65 µs each (about 40 to cut the rows out, the rest to hand them
  over). A mark now carries the layers written
  (`TtwTerrain.mark_cells(rect, layers)`): a press writes five, a settling
  visit most often one. Layer textures uploaded per frame 47 to 28 in the
  stress scene (3.1 to 2.0 ms), 6.3 to 0.2 in the skirmish, whose changes
  are nearly all the river banks' `deform`.
- **Thrown bits.** `TtwDebris` drew every bit on the map each frame, each
  its own draw call (three sheets and untextured shadows, interleaved, so
  nothing batched), and moved every one: about 2.5 ms of `_process`, 1.2 of
  `_draw` and 1.0 in the renderer in the stress scene, where 100 vehicles
  keep hundreds alive and few are in view. Bits outside the view (and a
  margin) are now skipped by the draw and move every fourth frame by four
  frames' time; all three sheets and the shadows come from one texture.
  715 draw calls to 40.

Where a frame goes now (Radeon, ms per frame): stress 8.5 = ticks 4.9 (half
a tick a frame, 9.7 each) + `_process` 2.2 (uploads 0.9, vehicles 0.9) +
`_draw` 0.5 + renderer 0.7, GPU 2.1; skirmish 1.2 = ticks 0.2 + `_process`
0.2 + `_draw` 0.1 + renderer 0.5, GPU 0.7.

Checked like the ground: every per-tick hash of the stress scene on fixed
ticks (terrain layers, water, settling and path queues, every unit) is as it
was, once the gun scan's stagger is pinned (see Traps).

**Whole screen pixels.** The project stretched its 1280×720 layout by any
factor (1.5 at 1920×1080), so at zoom 3 a world pixel was 4.5 screen pixels
and the buffer's texels came out 4 and 5 pixels wide by turns. The stretch
is now by whole factors (`window/stretch/scale_mode="integer"`), and the
`TtwDisplay` autoload (`game/display.gd`) sets the layout's size to the
window's over that factor: the engine's integer mode alone leaves what the
rounding frees as black bars (a 1280×720 picture in the middle of a
1920×1080 window). So 1080p is factor 1 with a 1920×1080 view (it sees 2.25
times the ground it did, and the HUD, title and menu are two thirds the
size), 1440p is factor 2 with a 1280×720 view, 4K factor 3. Measured at
1920×1080 on llvmpipe: every run of equal ground pixels is 3 wide or a
multiple (before: 4 and 5 mixed); at 2560×1440, 6. A skirmish clamps its
camera to the map as it starts and on zooming out, as panning did: the
wider view at 1080p started hanging 128 px over the map's edge.

**The same stretch of world on every screen.** At factor 1 a 1920×1080 view
at zoom 3 shows 640×360 world px where 1280×720 shows 427×240. A game now
starts at the whole zoom that shows the nearest to the layout's zoom 3
(`TtwZoom.start`: 5 at 1080p, 384×216 world px, which is nearer 240 high
than zoom 4's 270; 3 at 1440p and 4K, enlarged 2 and 3 times), and the
wheel's ends are the whole zooms nearest the layout's 1 and 5 (2 and 8 at
1080p; the Mud Lab's 0.5 and 8 become 1 and 12): `TtwZoom.levels_for`, given
to the wheel's `TtwZoom` for the window as it is at each notch. Probes and
tests that set a zoom keep it.

Frames per second in a 1920×1080 window on the Radeon, vsync off, each at
the zoom a game starts with there:

| | stress | skirmish | idle |
| --- | ---: | ---: | ---: |
| before (stretched 1.5, zoom 3; GPU 13.8, 9.6 and 7.3 ms a frame) | 46.5 | 57.8 | 118.6 |
| now (factor 1, zoom 5; GPU 2.0, 0.7 and 0.5 ms a frame) | 85 to 96 | 832 to 838 | 1048 to 1114 |

(1280×720, now: 106 to 125, 906 to 914, 1270 to 1301.)

### Frames by release

The frame probe run on each release's own checkout, on the Radeon at
1280×720, vsync off, zoom 3: three runs each, eleven of the stress scene at
0.2.0 and 0.2.4 (taken in turns, so the machine's drift falls on both).
Frames per second, least / median / most:

| Release | stress | skirmish | idle |
| --- | ---: | ---: | ---: |
| 0.2.0 | 79 / 103 / 135 | 1088 / 1096 / 1110 | 1287 / 1290 / 1299 |
| 0.2.1 (fire drawn upright) | 96 / 97 / 125 | 1089 / 1094 / 1115 | 1261 / 1281 / 1297 |
| 0.2.2 (water maps uploaded once a change) | 85 / 94 / 107 | 1115 / 1122 / 1152 | 1283 / 1292 / 1308 |
| 0.2.3 (chunk layers in two arrays) | 80 / 86 / 107 | 1156 / 1167 / 1167 | 1372 / 1381 / 1384 |
| 0.2.4 | 75 / 94 / 132 | 1128 / 1158 / 1193 | 1370 / 1372 / 1380 |

- The skirmish and the idle map are about 6% faster. The packed layers cut
  the GPU's frame from 0.52 to 0.48 ms; the water flag halved the ground's
  refresh on the idle map (0.04 to 0.02 ms).
- The stress scene's median is about 8% lower, inside its spread. A tick
  costs 9.49 to 9.89 ms (pushing by weight and firing at the ground, the 4%
  measured when they went in); the scene is held by the CPU, where a tick's
  millisecond costs more than one in the frame. Uploads cost the same per
  chunk (0.42 and 0.41 ms) and its GPU frame fell from 2.18 to 2.05 ms.
- Ticks a frame swing from run to run in the stress scene, so its range
  says more than any one run.

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
- **Settling: a mark for each new layer a tile's visits change.** The first
  cut of the layer marks called `mark_tile_quiet` again whenever a visit to
  the same tile changed a layer not yet marked: settle 1990 to 2210 µs.
  One mark per run of visits to a tile, with the layers gathered, is 2060
  (the marks are about 200 µs of settle either way).
- **A buffer with alpha for the ground.** Drawn through a render target
  with a transparent background, one pixel in ten came out one level off
  the picture drawn straight to the window; through an opaque one, none.
  (The engine appears to give an opaque target more bits per colour.) The
  buffer is opaque and the sprite showing it is cut to the map instead.
- **Driver threading** (`mesa_glthread`, `GALLIUM_THREAD=0`): 100 to 107 fps
  on the stress scene either way. Inside the spread.
- **Not done: skipping a vehicle's `_process` out of view.** 100 vehicles
  cost 0.9 ms a frame, in view or not. A `VisibleOnScreenEnabler2D` is
  the engine's way, but it hears of the screen from the renderer, a frame
  late (not tried: a unit just built would have to be shown right on its
  first frame some other way). A test against the view's rect in each
  `_process` would do it, for a tenth of the stress scene's frame and
  nothing a skirmish can show.
- **Not done: cheaper rows for a chunk's image.** 40 µs a layer is 144
  slices and appends. One slice of the whole band and `Image.get_region`
  would copy the map's full width three times (590 KB a layer on a
  128-tile map); not measured, and `ImageTexture` has no update of part of
  a texture.
- **A press writing its footprint as the scan finds it** (one loop, the
  tile's row worked out once per row) instead of collecting the footprint
  and looping again: 15.15 µs a press against 15.28, 0.5%.
- **A press's cell test from per-column offsets** (each column's centre
  less the patch's worked out once, the row's once per row), in float32 as
  before or with the dot products in doubles: 10.6 and 10.5 µs for the scan
  against 10.4. The interpreter's cost per cell is in the visit and the
  branches, not the arithmetic.
- **A press's four cell lists kept between presses** (`static var`,
  emptied each press) instead of made new: about 3% of a press, some 60 µs
  a tick in the probe, inside its spread. Not kept.
- **Tracks: the per-vehicle work trimmed** (wrecks left out by the query
  instead of `has_component`, contacts written into one kept array, the
  cell and tile under the hull as integers): 2.98 µs a vehicle against
  3.14 without a press, plus 0.15 for the `has_component`; about 25 µs a
  tick for 84 vehicles. Not kept.
- **Skipping `cells_changed` when nothing listens**: the emit is 0.06 µs.
  Not done.
- **Not tried: a press's cell test in doubles, summed per row and column.**
  The test is float32 (`Vector2`), and a cell exactly on an edge (a berm
  5 px from an axis-aligned patch) can fall on the other side in doubles, so
  it would change which cells get what.

### What is left, and why

- **Tracks, 2.4 ms on mud, 2.7 in winter.** About 136 presses a tick at
  14 to 15 µs, two thirds of it testing some 74 cells and appending the 36
  that get something (perf/tracks, above), plus about 3 µs per vehicle a
  tick that no press needs. Every way tried of doing the same work in
  fewer GDScript steps came to under 5% of a press. What is left is doing
  less: fewer presses (one per wheel line instead of one per wheel), fewer
  cells (a narrower spray), or the press in native code. Each would change
  what the ground gets, or the build.
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
- **Chunk uploads** are outside the systems: about 65 µs a layer texture
  (`chunk_image` about 40, a slice and an append per row), for the layers
  that changed, up to 8 chunks a frame: 0.9 ms a frame in the stress scene.
- **The frame outside the ticks**, stress scene: vehicles' `_process` 0.9 ms
  (9 µs each, in view or not), and 2 ms of GPU for the terrain buffer's
  105,000 world pixels (the shader itself: march, shadow, splat). Neither
  bounds the frame now; the ticks do.
- **Ticks per frame.** Above 16.7 ms a tick the engine runs up to 8 a frame
  (`physics/common/max_physics_steps_per_frame`) and the frame rate falls
  to single figures before the game slows. A lower limit would trade game
  speed for frame rate on a machine that slow: a choice about the game,
  not made here.
