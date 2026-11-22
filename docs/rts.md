# The RTS shell

Small on purpose: fuel is the only resource, and the ground decides how much of
it a move costs. Every rule here has a test (`tests/unit/test_depots.gd`,
`test_garages.gd`, `test_recovery.gd`, `test_paths.gd`,
`tests/integration/test_skirmish.gd`).

## Getting about (`game/terrain/path_grid.gd`, `game/systems/pilot.gd`)

- **Path grid** (`TtwPathGrid`, on the map's `TtwGround.paths`, kept by
  `TtwPathSystem`): `AStarGrid2D`, one weight per tile from every layer the
  drive reads (material, wear, ruts halfway between following and crossing,
  loose mud, wetness, water, snow, oil, grade). Walls: water at the engine
  intake (`FLOOD_PX`), ground that holds more than a truck's traction, and
  tile centres inside an obstacle grown by `OBSTACLE_GROW` (the widest
  vehicle's radius: every vehicle is a circle, so a route along open tile
  centres clears every obstacle, like a navigation agent's radius). A tile
  costs its resistance squared (`SURFACE_POWER`: pavement 1, grass 1.8, mud
  4.8), so routes keep to roads; any water over `WET_PX` adds `WATER_STEP`,
  so they keep out of fords and puddles when there is a dry way. Ground past
  75% of a truck's traction costs six times more, so routes go round bogs.
  The grid catches up with a changed map over a few seconds (the queue and
  the sweep): call it the fog of war.
- Tiles are weighed again when the terrain queues them (`path_queue`: set
  where `floors_stale` is, and on material and elevation changes), up to
  `QUEUE_BUDGET` a tick, and by a sweep of `SWEEP_BUDGET` a tick over the
  whole map for what changes everywhere (water levels, drying, snow).
  Obstacles tell the grid what they block when bound, when they drift and
  when they are gone (`TtwProp2D.block_paths`).
- **Pilot** (`TtwMoveOrder`, `TtwPilotSystem.order/stop`): plans a route,
  steers for each turn, plans again every 3 s, stops at the target. Treads
  pivot for sharp turns, wheels slow into them. One that runs but gets
  nowhere for 1.5 s backs off, turning, and plans again; after three tries it
  gives the order up ("It cannot get through."). Near its target and pressed
  against a vehicle standing nearer it, it has arrived.
- **Separation** (`TtwSeparationSystem`): overlapping ground vehicles are
  pushed apart each tick; one that cannot move holds its ground.
- Maps move props and neutral structures off their roads, clearance and all
  (`TtwMaps.off_roads`), and nothing may be built in front of a garage's
  door (`TtwPlacement.door_of`).

## Stuck, winch and tow

- **Stuck** (`TtwStuck`): added on the tick resistance passes traction while
  the vehicle tries to drive (not at it). It stops dead and cannot drive or
  turn; it is free once resistance falls under 85% of traction (dried,
  drained, or dragged onto firmer ground).
- **Winch** (`TtwWinch` on a wrecker, `TtwWinching` link): the wrecker brakes
  and drags the load straight at itself, slower where the ground holds it
  harder than the winch's force, burning fuel. The cable comes off when a
  stuck vehicle is free, or when an immobile load (wreck, flooded, dry,
  stalled for good) is within tow length. Out of range is refused with a
  reason.
- **Tow** (`TtwTowing` link): the load follows at rope length, turned to
  face the wrecker; half its resistance is added to the wrecker's
  (`TtwDrive.load`), so towing through mud is slow and can bog both.

## Structures (`prefabs/structure/`, `game/structures/structure_2d.gd`)

Placeholder art is the user's PixelLab garage, depot and helipad. Each is an
obstacle with health and a side (`TtwTeam`; 0 neutral).

| Thing | Rule |
|---|---|
| Fuel depot | Holds fuel and refills. Each other depot of its side within `cluster_tiles` (Area2D overlaps, counted when they begin and end) adds 25% to the rate, capped at twice it. Refuels its side's units within 3 tiles. A neutral depot falls to a side whose units hold it alone for 5 s. Destroyed, it goes up `CHAIN_TICKS` later: a depot crater, burning fuel, and damage to everything in reach, both growing with the fuel inside; a depot the blast destroys follows a fuse later. |
| Garage | Builds a queue of units (`TtwBuildQueue`: what it builds is on the prefab); each takes its fuel from the supplying depot (the side's nearest within 12 tiles, linked) and then its time, faster with a boss near. Says why it waits. Repairs its side's vehicles within 3 tiles for fuel; a flooded engine runs again at half health. Breaks up wrecks towed in for 30% of their fuel cost. |
| Helipad | Placed only with a depot of its side within 8 tiles (refused with the reason); linked to it. Builds helicopters (they start on the pad). Repairs and refuels its side's aircraft landed on it. |
| Win | A side with no garage left loses (`TtwMatch`, `TtwMatchSystem`). |

Costs (`game/rts/production.gd`; units in `docs/units.md`): garage 200,
depot 100, helipad 120. Placement (`TtwPlacement.check`) also wants the
ground clear (open on the path grid) and on the map, an engineer of the side
within 5 tiles, and the fuel in one depot.

## Playing (`game/rts/title.tscn`, then `main.tscn` = `TtwSkirmish`)

- Title (`TtwTitle`, the first scene): a skirmish on any map, the saved game,
  the Mud Lab, quit. The game's menu and the Mud Lab's Esc come back to it.

- Map (`TtwSkirmishMap`): 96×56 tiles, mirrored. Bases west (side 1) and east
  (side 2): a garage, two depots, two tanks, a wrecker and an engineer. A river
  down the middle too deep to drive except at two fords; four neutral depots.
- Commander (`TtwCommander`): left click or drag selects own units (or one
  structure), right click moves (in a block) or, with a wrecker selected and
  a stuck or broken vehicle under the cursor, winches it (tows it if it cannot
  drive and is close); on an enemy, units with guns attack it. X lets go,
  S stops, R has engineers lay road, F uses the special at the cursor (spray,
  drop, smoke), WASD / arrows / screen edge pan,
  wheel zooms. Build buttons place structures with a ghost (green or red, the
  helipad's reach drawn).
- HUD (`TtwHud`): the side's fuel, build buttons, what is selected (a garage's
  or helipad's queue and the buttons for what it builds, a depot's fuel and
  refill, a unit's state and kit), messages, the result.
- Menu (`TtwMenu`, Esc): resume, save, load, a new game on any map, quit;
  the game stands still while it is open. F5 / F9 quick save and load.
  Command line (after `--`): `--map=river|snowfield|dunes`, `--watch` (the
  computer plays both sides), `--load=<path>`.

## Maps (`game/rts/maps.gd`)

Every map is mirrored about its middle, gives both sides the same base (a
garage, two depots, two tanks, a wrecker and an engineer: `TtwMaps.base`)
and has neutral depots to take and a ground route between the bases
(`tests/integration/test_maps.gd`).

| Map | Ground | Weather |
|---|---|---|
| River crossing (`TtwSkirmishMap`) | mud fields, roads to two fords over a river too deep elsewhere | mild, a breeze |
| Snowfield (`TtwSnowfieldMap`) | snow over grass and mud, deep in the hollows; ploughed gravel roads round a long lake; pine woods | −4 °C, snowing, no thaw |
| Dunes (`TtwDunesMap`) | sand; two rock ridges (walls, and they stop shells) open at three gaps; an oasis pond | 32 °C, full sun, a wind that drifts the sand |

## The computer opponent (`TtwAi`, `TtwAiSystem`)

An entity of its own per side it plays (`ai:<team>`); every `think_ticks`
it looks at its side and orders through the commander's own calls:

- **Building:** keeps one unit in each garage's queue: an engineer and a
  wrecker first, then tanks to three, a nurse, a hippy when a wave is near,
  a tanker, a boss when rich, then tanks; gunships from a helipad when it
  has fuel to spare.
- **Expanding:** its engineer builds depots beside the others (up to four:
  they refill faster together) and then a helipad, driving to the site
  first; a site that goes bad is given up for another.
- **Taking depots:** one tank goes to sit on the nearest neutral depot.
- **Recovery:** an idle wrecker winches the nearest stuck or stranded unit.
- **Defence:** enemies within `defend_tiles` of its base are attacked by
  its whole army.
- **Waves:** tanks gather at a rally point a third of the way to the middle;
  with `attack_size` of them the army goes for the nearest enemy garage
  (then any structure). Beaten back to under two, it regroups and the next
  wave is one bigger. The nurse follows the army; the hippy smokes enemies
  that come near it.
- **Fuel:** a unit under a quarter full goes to the nearest depot.

Tests: `tests/integration/test_ai.gd`. `tests/render/ai_probe.tscn` lets it
play both sides for three minutes and prints what each side has.

## Saving and loading (`TtwSave`)

One Variant, ZSTD-compressed (`user://saves/quick.ttwsave`): every terrain
layer, the water (depths, fluxes, slick, what the ground took in, the
books), the fire field, the settling queue; every entity but the session's
own, with its alias, its body's scene and place, each component's plain
script variables and its links by alias (shots, smoke clouds and opponents
are entities too); the map's weather and match; the tick; rubble. The path
grid is worked out again on the first tick. A loaded game captures the same
as the saved one, field for field (`tests/integration/test_save.gd`).
