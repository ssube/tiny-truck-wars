# Tiny Truck Wars: build plan

## Context

Tiny Truck Wars is a small game on a 2D ECS core over GECS. It is a top-down RTS. Garages, fuel depots and helipads make, fuel and repair tanks, trucks,
helicopters and three special units. **Most of the work goes into the ground:** how mud and
water look, tracks and ground visuals, ground deformation, and particle effects. Vehicles cut
ruts that deepen with traffic and push up mud around them, craters, puddles and flowing water.
All of it is drawn with parallax depth, and it feeds back into how fast vehicles move and how
much fuel they burn. The RTS layer sits on top of that and stays deliberately small.

Decisions made:
- **View**: orthographic top-down with a slight faux tilt (about 20°), pixel-crisp.
- **Play**: RTS against one AI opponent on skirmish maps.
- **Trucks**: one truck chassis with a *kit* chosen at the garage. A **Tanker** carries fuel.
  A **Wrecker** winches and tows stuck vehicles and wrecks. An **Engineer** lays gravel road,
  and only an Engineer can build garages, depots and helipads.
- **Code**: a small ECS core (`kit/`: the session, component slots, the test harness) under
  the game's own code (`game/`).
- **Art**: the user's PixelLab characters for the truck, tank, hippy and helicopter (ids below).
  Also the user's PixelLab objects for the garage, depot and helipad. Later the user also made
  the boss (a black state limousine) and the nurse (a UAZ-452 field ambulance).

## The ground (the core of the game)

### Layers (`game/terrain/`, CPU arrays are the truth, dirty rects go up to textures)

| Layer | Cell | Data | Written by |
|---|---|---|---|
| Surface | 1 tile | material index: mud, grass, pavement, gravel, sand | map; Engineer roads |
| Elevation | 1 tile, bilinear | height | map (static) |
| **Deformation** | ⅛ tile | signed height delta: ruts −, berms and mounds +, craters | treads, wheels, shells, Engineer (flattens) |
| Track direction | ⅛ tile | unit vector, blended per pass | treads and wheels |
| **Loose mud** | ⅛ tile | volume of displaced mud, which also tints the surface | treads and wheels push it; vehicles carry it and smear it onto pavement |
| **Wetness** | ¼ tile | 0..1; dries over time, spreads from water | water, splashes |
| **Water** | 1 tile | depth plus flux in 4 directions (virtual pipes) | shallow-water step, sources and sinks |

- The cell size is set in tiles. The tile size in pixels is chosen once the sprites are
  measured, so that one deformation cell is a few screen pixels.
- **Stamping** happens once per cell a footprint enters, never every tick. A tread or wheel
  footprint is oriented and sinks by weight × softness(surface, wetness, loose mud), up to a
  cap. The volume it moves goes to side berms and a bow wave in front, and a slipping wheel
  throws a spoil spray behind. Ruts are added together, so ten passes make a trench. Grass
  rebounds slowly; mud keeps its shape.
- **Wear** (a cell layer, 0..1): every pass wears the ground. Grass that is worn
  through is **torn up and becomes mud**: it draws as mud and softens like mud, cell
  by cell. Pavement is far more resistant. It barely sinks and wears slowly, first
  to cracks, then (only under sustained heavy traffic) to broken patches that act
  like gravel. Loose mud still smears across it.
- **Water** (as built): a virtual-pipe model on the tile grid, stepped every 2
  ticks over the wet area only. A tile holds a *volume*, and its level comes from
  how its 64 cells lie, so a little water fills only the ruts and a crater's floor.
  Volume is exact apart from sources and sinks, which keep their books. Decided:
  the CPU model stays the truth (gameplay reads it every tick, headless tests have
  no GPU, and conservation stays exact). GPU shaders move only the visual detail
  (foam, turbidity, wake ripples) along the simulated current. If the CPU model gets
  slow on big maps, a C++ port of the same model is measured first.
- *(Original note)* **Water**: the pipe model is stepped every k ticks in row strips. The floor is elevation
  plus deformation, so ruts and craters fill as puddles, and a river current carries along.
  Volume is conserved apart from sources and sinks.
- **Every explosion leaves a crater.** One `stamp_crater(pos, radius, depth)` handles all of
  them, sized by the blast:
  - a tank shell: small
  - a helicopter rocket: small to medium
  - an exploding vehicle: medium, with a burning wreck left in it
  - an exploding building or depot: large, with burning fuel
  The dug volume becomes the rim and thrown clods. Craters fill with water like ruts do, and
  driving through them costs the same as through deep ruts. A helicopter's rotor wash
  ripples water, raises dust from dry ground and flattens grass.

### Rendering (`shaders/terrain.gdshader`, canvas_item, one quad per 16×16-tile chunk)

- Each surface material has its own albedo and height in a texture array and is splatted
  with height-blend transitions, so mud seeps into the gaps in gravel.
- **POM along the fixed tilt direction** runs on
  `material_height + deformation + loose_mud`, with a short linear march and then a binary
  refine. That makes deep ruts and berms read as real relief, with occluded walls. The
  normals for lighting come from finite differences on the same height. One fixed sun gives
  rut shadows from a short self-shadow march.
- **Wet mud**: wetness darkens the albedo and adds a specular sheen. Standing water in ruts
  reflects a sky colour.
- **Big drops** (cliffs, canyons) are drawn as cliff-face edge sprites plus shading, not
  with parallax. POM is kept for relief up to about 1 tile deep.
- **Water pass**: colour by depth, flow-scrolled normals that follow the simulated velocity,
  foam where the water meets the bank or a vehicle, refraction of the deformed floor
  beneath. Wakes behind moving vehicles. Ideas come from the kit's `shaders/fluid.gdshader`.
- **Pixel-crisp**: the terrain renders at native resolution into a SubViewport and is scaled
  up by a whole number. POM offsets snap to whole pixels, so ruts don't swim as the camera pans.
- **Vehicles on the ground**: the sprite shader sinks the lower edge of the hull by the
  sampled rut depth plus water depth, using a clip mask. Mud cakes onto the hull as a
  per-vehicle grime value that builds in mud and washes off in water. A tilt wobble follows
  the deformation gradient.

### Shaders go further (water and deformation are where the effort goes)

- **Tread and tyre imprint**: a tileable tread-pattern texture is laid along the track
  direction layer and faded by how recent and deep the pass is. Every rut shows its chevrons,
  and crossing tracks overwrite each other.
- **Mud material**: a viscous look, with clumpy height noise on berms, wet-edge darkening
  that follows the gradient of wetness, sticky specular highlights on fresh spoil, and dried,
  cracked mud as wetness falls (a crack mask fading in).
- **Mud slump (sim + shader)**: steep berms settle a little each step toward a material's
  angle of repose, so trenches soften over time instead of staying sharp.
- **Turbidity layer** (¼ tile): vehicles and explosions stir sediment into water. Murky
  brown water is advected by the flow and slowly clears, and the colour pass reads it.
- **Water surface**: flow maps driven by the sim velocity, with two-phase scrolling so there
  is no stretching. Foam is advected as its own layer: it gathers in eddies, behind vehicles
  and at banks. Rain ripples are a toggle. Fake reflections of the sky gradient and of nearby
  sprites (mirrored, distorted sample). Refraction of the deformed floor, caustics on rut and
  crater floors under shallow water, and a soft depth edge where puddle meets mud.
- **Wakes**: a ring/V-shaped displacement each vehicle stamps into a ripple layer that
  propagates with a cheap wave equation on the ¼-tile grid.
- **Craters**: scorch albedo that fades, a fresh-dirt rim tint, and still water when flooded.
- **Vehicle interplay**: sink mask, mud caking and wet sheen on hulls, plus a contact
  shadow onto the deformed ground.
- **Distance LOD (render only)**: each terrain chunk picks one of three material variants
  from its distance to the camera's view centre and from the zoom (screen pixels per cell):
  - **Full**: everything above.
  - **Mid**: no POM march or self-shadow; normal-mapped relief, tread imprint, simple water
    (no reflections or caustics; flow normals kept).
  - **Far**: albedo + deformation shading baked from the normals, plus flat water colour
    by depth and turbidity.
  The tiers have hysteresis and a short cross-fade, so the boundaries don't flicker. Chunks
  off-screen aren't drawn, and their texture uploads wait as queued dirty rects until they
  come into view. Particles, fire and smoke are culled or thinned the same way.
- **The simulation never uses LOD.** Stamping, mud, water, wetness, turbidity, slump,
  movement cost, fuel burn and stuck run at full resolution and full rate across the whole
  map, wherever the camera is. The kit's `session.active` (near the camera) is not used for
  any terrain or vehicle system, only for cosmetic ones.
- Every effect can be switched off by a quality option (`options.gd`) so a low-end GPU and
  the web build have a fallback. Each has its cost measured in the Mud Lab.

### Particles (`game/fx/`, kept conservative)

- A small set of **textured** particles (sprite-sheet flipbooks on `CPUParticles2D`,
  pooled, with a per-frame budget): mud clods and spray from slipping wheels, water splashes,
  dust from rotor wash and from dry ground, and explosion debris.
- **Shaders only for fire and smoke**:
  - fire (burning fuel, wrecks, depot fires): noise-scrolled flame with dissolve and a
    heat-haze distortion
  - smoke (exhaust, explosion plumes, the hippy's screen): soft noise billows lit from the
    fixed sun, which drift with the wind
  The hippy's screen is a few large shaded smoke quads, not a particle storm.
- No particle effect stamps the ground. Craters and mounds come from the event that
  caused them.

### Mud Lab (the visual tuning tool, built first)

`tools/mud_lab.tscn` is a sandbox with a test map, a drivable vehicle with switchable weight,
treads or wheels and speed, brushes (deform, wet, water source, crater) and live sliders for
every shader and sim constant. It is how the look gets tuned, and it doubles as a render probe.

## Game rules (kept small)

Fuel is the only resource. Depots hold fuel and refill over time, neutral depots can be
captured, and garages take a unit's fuel cost from a linked depot. So mud costs you economy
as well as time.

| Thing | Rule |
|---|---|
| Garage | Builds units (queue; time + fuel). Repairs ground vehicles within R. |
| Fuel depot | Stock + refill/s; refuels units within R. **Clustering**: each other depot within C tiles raises refill (`refill × (1 + k·neighbours)`, capped). The neighbours are counted from `Area2D` overlaps on enter/exit, never polled. **Explodes** when destroyed. Blast radius and damage scale with the fuel it holds. It damages every building and unit in range, and a depot the blast destroys explodes in turn a few ticks later. The chain reaction plays out in steps you can see, and each blast leaves a large crater, burning fuel and a debris shower. |
| Helipad | Placement is rejected (with a stated reason) unless a depot is within N tiles; linked to it by `session.link`. Repairs and refuels helicopters. |
| Tank | Ground attack; can hit helicopters at reduced accuracy (tunable). **Shots are ballistic**: shells fly an arc through the height field, so elevation can block or shorten a shot (obstacles such as buildings and wrecks come later). Tanks **lead moving targets** by default, aiming where the target will be from its current velocity and the shell's flight time; a per-unit (and global) option turns leading off. |
| Helicopter | Ignores terrain, crosses canyons and rivers, rotor wash. |
| Truck kits | Tanker, Wrecker, Engineer, as above. |
| Boss / Hippy / Nurse | Faster production nearby / smoke cloud that slows ground units / heals tanks and trucks nearby, not helicopters. |
| Win | Destroy every enemy garage. |

Every vehicle has **finite fuel** and **health** (its wear; 0 is disabled, and a
destroyed vehicle explodes and leaves a crater). Grade and current are signed:
**uphill is slower and downhill faster**, and **against the current slower,
with it faster**, both along the heading. **Driving through water wears a
vehicle**: the damage per second grows with the depth over the vehicle's
wading depth (shallow splashing does almost nothing, deep fording a lot),
and water up to a vehicle's engine intake **floods the engine**. Health drops to
1%, the vehicle gets a `Flooded` component and cannot be restarted, and it does
**not** explode. Assumed: a Wrecker can tow it home, and a garage repair clears
the flood.

**Stalling**: driving under strain (in water over the wading depth, climbing a
steep grade, or pushing through deep mud or ruts near the traction limit) fills
a stall meter, faster the more worn the vehicle is. When it is full the engine
stalls (`Stalled`). A stalled engine restarts after a few seconds, unless the
vehicle is **more than 95% worn** (health under 5%): then it cannot be restarted
until it is repaired. The meter is deterministic, not a dice roll, so a stall
can be tested to the tick.

Moving: `speed = base × surface × rut(depth, heading·rut_dir) × mud × water(depth,
current·heading) × slope × smoke`. Fuel burn scales with the inverse of that. Driving *along*
ruts costs less than crossing them. Once resistance passes a vehicle's traction it becomes
`Stuck` (a component), and a Wrecker's winch frees it. Pathing uses `AStarGrid2D` with live
weights, and only dirty cells are re-weighted. "Nearby" checks use `Area2D` radii.

## Code layout

The core keeps the `Kit` prefix (`kit/`: the session, slots, `Kit2D`, the test harness);
the game's own code uses `Ttw`. Third-party addons: `addons/gecs` (the ECS) and
`addons/gdUnit4` (tests only). Game code is in `game/terrain/` (layers, stamping, water,
path weights), `game/fx/`, `game/units/`, `game/structures/`, `game/world/`,
`game/combat/`, `game/systems/`, `game/rts/` (the skirmish, its maps, the AI, saving),
`prefabs/{unit,structure,world}/` and `shaders/`.

## Milestones

Each milestone gets one worktree branch, with one commit per item. Each one is merged and
pushed when green.

0. **Bootstrap**: `git init`, copy and trim the core, then import and get the tests and the
   leak check green. Create the Forgejo repo with `tea` and push, so CI runs. Download the four
   characters with `pixellab_download.py --characters --ids` (truck dbf0e54e…, tank 8835f4c4…,
   hippy ab8f3c41…, helicopter fa77e562…) and the three structure objects with `--ids`
   (garage 013cc06a…, depot ef9e255e…, helipad cf233dc2…). Measure their sizes and facings,
   and set the tile size from them. (The boss and nurse sprites arrived later.) The sprites are 8 directions, so units snap to 8 facings.
1. **Ground renderer + Mud Lab**: layers and textures, the material splat, POM, normals, rut
   shadows, wet sheen, cliff edges and pixel-snapping. Brushes paint the layers by hand.
2. **Deformation**: tread and wheel stamping, berms, bow wave, loose mud carried onto
   pavement, craters, grass rebound. Vehicles sink into the ground, mud cakes onto hulls and
   hulls tilt.
3. **Water**: the pipe sim, puddles in ruts, river current, wetness that spreads and dries,
   and the water pass (depth colour, flow normals, foam, wakes).
4. **Shader depth pass + particles**: tread imprints, turbidity, foam advection, wakes,
   reflections, caustics, slump and cracks. Then the small textured particle set, and the fire
   and smoke shaders.
5. **Mud → mechanics**: speed, fuel, slope, stuck and winch; path weights from the layers.
6. **RTS shell**: selection, orders, camera, structures, fuel economy, production, repair,
   helipad rule.
7. **Units and specials**: combat, helicopters, truck kits, boss, hippy and nurse.
8. **AI + skirmish maps**: win and lose, save and load.

## Verification

- At the end of every milestone, `KIT_TEST_HEADLESS=1 ./run-tests.sh` (unit + integration),
  `./run-leak-check.sh` and every render probe exit 0 on the changed source. After the merge,
  re-import, re-test, push, and confirm Forgejo CI is green.
- **Sim tests** assert requirements, not pixels:
  - Ten passes deepen a mud rut monotonically up to its cap, and pavement stays at 0.
  - The volume a stamp moves equals berm + mound + spray, so mud is conserved.
  - A heavier or wetter pass sinks deeper.
  - Loose mud carried onto pavement falls off with distance.
  - A crater's rim volume matches what it dug.
  - A crater's size goes in the order shell < rocket < vehicle < building.
  - Destroying a vehicle or a building, or a rocket hit, each leaves a crater where it happened.
  - Two identical vehicles on identical ground, one under the camera and one off-screen,
    take the same number of ticks, burn the same fuel, and leave identical deformation,
    mud and water arrays.
  - The LOD tier picked for a chunk follows its distance and the zoom, with hysteresis: it
    holds at the boundary and switches past the band.
  - Water volume is conserved over 600 ticks without sources, and it pools in a rut but not
    on flat pavement.
  - Wetness dries at its set rate.
- **Mechanics tests** budget ticks from distance/speed (`Simulation.physics_ticks`). A tank
  crosses N mud cells in exactly the computed number of ticks, which is more than on pavement.
  Driving along a rut is faster than crossing it. Stuck triggers on the exact traction
  boundary tick. Ranges are checked at R and R+ε.
  Depot tests:
  - Refill grows with each neighbour inside C, does not grow for one at C+ε, and stops at the cap.
  - An empty depot's blast is smaller than a full one's.
  - A depot inside the blast that the damage destroys detonates exactly D ticks later.
  - One that survives does not detonate.
  - A chain of three ends with nothing left to detonate. The helipad is rejected with its reason when
  no depot is in range. A helicopter crosses a river that ground units path around.
- **Visual review**: `run-probe.sh res://tools/mud_lab.tscn` scripts a drive loop (sweeping
  turns, repeated passes, a puddle crossing, a shell impact) and writes PNG and GIF captures to
  `reports/mud_lab/`. CI keeps them as an artifact to look over, not as a snapshot assertion.
  `run-map-pictures.sh` draws each map whole.
- **Performance**: an `ecs_probe`-style probe with 100 vehicles on a 128×128-tile map
  measures the cost of stamping, the water step, path re-weighting, particles and terrain
  shader time. Results are recorded in `docs/ecs.md`. If stamping or water goes over budget in
  GDScript, a GDExtension port is measured before it is kept. Shader cost is measured on the
  real GPU as well as on Mesa in CI.


---

# Round two: world and weather (Milestone 5, done)

Added after the first milestones (approved plan): weather and wind (ported
from the 2D kit's wind and weather), sand that behaves as sand, snow that packs
and melts into mud and water, oil (slippery, flammable, a shader sheen, a slick
that runs downstream), fire as a tile simulation, trees that fall into logs,
destructible buildings with rubble, and pouring and drawing water. Placeholder
art for trees and buildings until the user makes sprites. Units that use pour
and draw (a Water tanker truck kit, a helicopter bucket) come with the units.

The ground simulation's cost was cut from 77 ms to under 7 ms per tick for 100
vehicles on a 128×128 map (a Fable agent; numbers in docs/ecs.md).

Later milestones, renumbered: 6 mud into mechanics (path weights from every
layer, stuck, winch), 7 RTS shell (structures, fuel economy, depot clustering
and chain reactions), 8 units and specials (ballistic tank fire with leading,
helicopters in wind, the truck kits including the Water tanker, the bucket,
boss, hippy, nurse), 9 AI and skirmish maps (snow and desert maps too).

---

# Milestones 6 and 7 (done)

6, mud into mechanics: vehicles get stuck on the tick resistance passes
traction; a wrecker's winch drags them out and its hitch tows wrecks; a path
grid weighs every layer (snow, oil, obstacles included) and a pilot drives the
routes. 7, the RTS shell: garages, depots and helipads with their rules (depot
clusters, chain reactions, capture, the helipad rule, production, repair,
scrap), the fuel economy, a skirmish map, selection, orders, camera, HUD and
the win rule. All in `docs/rts.md`.

Left for later: units do not push each other apart.

---

# Milestone 8 (done)

Units and specials, all in `docs/units.md`: tanks fire ballistic shells
that lead their targets (a ridge or a tall building stops them short) and
hit aircraft at their air accuracy; helicopters fly in the wind (crabbing,
holding station, drifting down out of fuel), make rotor wash, land and are
built at helipads; gunships fire rockets; the truck kits (Wrecker, Tanker,
Engineer, which lays road and must be near anything built, Water tanker)
and the bucket helicopter; the boss, the hippy's smoke and the nurse. Dry
ground now drinks a little water (`TtwWater.SOIL_HOLDS`), so a tanker load
makes mud where it lands instead of a film over the map. Fixed in GECS: a
view missed an entity added to an archetype that already existed.

---

# Milestone 9 (done)

A computer opponent (`TtwAi`: building, expanding, taking depots,
recovering, defending, attacking in waves that grow), three skirmish maps
(the river crossing, a snowfield and dunes), saving and loading the whole
game, and a menu. All in `docs/rts.md`. On the way: a depot that is built
starts empty (building depots made fuel), and a garage draws on another
depot in reach when its own is short.
