# Units and specials

Every unit is a chassis (a prefab under `prefabs/unit/`) with a kit fitted
when it is built (`TtwProduction.UNITS`: `unit` and `kit`; `TtwKits.parts`).
A kind with sprites of its own names them as `art` (`assets/units/<art>/`,
the wrecker's and the tanker's); `TtwUnits.dress` gives them to its body when it is spawned
and when a save is loaded. It carries `TtwUnit` (the kind it was built as) and `TtwTeam`, and is spawned
through `TtwUnits.spawn` by the game, the garages and the tests alike. Every
rule here has a test (`tests/unit/test_combat.gd`, `test_helicopters.gd`,
`test_kits.gd`, `test_specials.gd`).

| Kind | Built at | Chassis + kit | Fuel / s |
|---|---|---|---|
| Tank | garage | tank, cannon (on the prefab) | 120 / 12 |
| Wrecker | garage | truck + winch and hitch | 60 / 8 |
| Tanker | garage | truck + fuel cargo | 50 / 8 |
| Engineer | garage | truck + road kit; builds structures | 70 / 9 |
| Water tanker | garage | truck + water tank and spray | 50 / 8 |
| Hippy | garage | hippy van + smoke | 40 / 6 |
| Boss | garage | limousine; garages near it build faster | 150 / 15 |
| Nurse | garage | field ambulance; heals | 70 / 9 |
| Gunship | helipad | helicopter + rockets | 140 / 14 |
| Bucket helicopter | helipad | helicopter + water bucket | 110 / 12 |

## Shooting (`TtwGunSystem`, `TtwBallisticsSystem`, `game/combat/`)

- **Targets.** An ordered target (`TtwAttacking`, right click on an enemy;
  Ctrl+right click on anything with health, a tree or a house too) or an
  ordered spot on the ground (`TtwFireAt`, Ctrl+right click where nothing
  is) comes first: out of range the unit closes in (a `TtwMoveOrder` with
  `chase`), in range it stops and fires, and the order ends when the target
  is gone (a spot is fired on until another order). Otherwise every `SCAN_TICKS` (staggered per unit) a gun takes the
  nearest enemy in range, units before structures, aircraft only if it can
  reach them, nothing inside smoke past `SMOKE_SIGHT_TILES`.
- **Ballistic shells.** A shot is an entity of its own with a `TtwShell` and
  no body. Its path is fixed when fired: a straight line over the ground at a
  height running from the muzzle to the end plus an arc (`arc` × distance).
  Each tick the path since the last is walked in steps of `STEP_PX`; the shot
  bursts where it first meets the ground (elevation, relief or water: a ridge
  stops it short) or an obstacle taller than it is over the ground there
  (`TtwObstacle.height_px`, a tree's height): a garage near the target takes
  a shell coming down, a helipad (2 px) does not.
- **Leading.** Aim at where the target will be when the shot lands: its
  velocity times the shot's flight time, found by four rounds of "how long to
  there". On by default per gun (`TtwGun.lead`) and for the session
  (`TtwGunSystem.leading`); off, a shell lands behind a moving target.
- **Bursts** (`TtwCombat.burst`): the crater of the ammo (`shell`, `rocket`),
  snow blown off, the look, damage falling off from the middle, a fire where
  there is fuel. Aircraft in the air are over it.
- **Air.** Tanks can shoot at aircraft; a shot at one bursts in the air and
  hits at exactly the gun's `air_accuracy` (35%): kept as a count of shots,
  not rolled. A miss passes to one side.
- **Rockets** (the gunship's kit): flatter and faster, fired only in the air,
  from its height, at ground targets.

## Helicopters (`TtwFlight`, `TtwFlightSystem`, `TtwAircraft2D`)

- Fly straight to an order's target over anything, at `cruise_px`, after
  lifting off `LIFT_OFF_PX`. The wind pushes them by `drift` of itself; the
  pilot steers for the ground velocity it wants against that push, so the
  nose turns into the wind and the helicopter crabs across it, and it holds
  station when it stops.
- Out of fuel it can steer no more: it sinks at `climb_px` and drifts
  downwind until it is down, and stays there (a Tanker can fuel it).
- With no order over its side's helipad it lands; landed there it is
  refuelled and repaired. Built at a helipad, it starts on the pad.
- Rotor wash under a low helicopter: rings on the water, dust off dry ground
  and snow, stronger the lower it is.
- Drawn lifted by its height (`TILT_K`) with its shadow on the ground, over
  ground units, with the rotor's blur.

## Truck kits and the bucket (`TtwKitSystem`)

- **Wrecker**: the winch and hitch (`docs/rts.md`). Its amber beacon (the
  six orange pixels on its roof, in every facing) flashes slowly, 48 times a
  minute, and lights the ground and water around it; dark once it is a
  wreck. Both are drawn on the GPU's clock from `shaders/beacon.gdshaderinc`
  (the sprite in `vehicle.gdshader`, the light in `beacon_glow.gdshader` on
  the ground effects layer, carried by a `RemoteTransform2D`), so they cost
  no script time. Other vehicles and props are not lit by it.
- **Tanker** (`TtwTanker`): its cargo is filled at its side's depots along
  with its own tank; every `SERVICE_TICKS` it gives `rate` a second to each
  unit of its side within `reach_tiles`, ground ones and aircraft on the
  ground.
- **Engineer** (`TtwEngineer`): structures are placed only with an engineer
  of the side within `build_tiles` (refused with the reason). R starts and
  stops it laying road: each tile it drives onto becomes gravel, its ruts
  filled, loose mud cleared, wear gone, for `pave_fuel`.
- **Water tanker** (`TtwWaterTank`): pumps from water within
  `pump_reach_px` into its tank; F sprays a spot (it drives within
  `spray_tiles` first), sweeping across it until the tank is empty: the
  ground is soaked (mud made on purpose) and fires under it go out.
- **Bucket** (`TtwBucket`): a helicopter with no order hovering over water at
  least `min_depth_px` deep sinks to `dip_px` and fills; F flies it to a spot
  and drops it all there.
- Water is booked throughout: what is pumped and dipped is the water's
  `drawn`, what is sprayed and dropped its `poured`, and dry ground drinks a
  little (`TtwWater.SOIL_HOLDS` a tile, not pavement: its `infiltrated`), so
  a tanker load makes a patch of mud, not a film over the map. A volume unit
  is 1 px of depth over a whole tile: a tank holds 8, a bucket 4.

## Specials (`TtwSpecialSystem`)

- **Boss** (`TtwBoss`): garages and helipads of its side within
  `reach_tiles` build `1 + speedup` times as fast; bosses do not add up.
- **Hippy** (`TtwSmokeLauncher`): F throws smoke on a spot within
  `throw_tiles` (as far as it can toward it), every `cooldown_seconds`. The
  cloud (`TtwSmokeCloud`, an entity of its own) slows every ground unit
  inside to `slow` of its speed, hides what is in it from guns, drifts with
  the wind like its look (`TtwSmokeScreen.DRIFT`) and clears after
  `seconds`.
- **Nurse** (`TtwMedic`): heals its side's ground vehicles within
  `reach_tiles` at `rate`, never helicopters, never itself.
