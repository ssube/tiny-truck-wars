# Tiny Truck Wars

A small top-down RTS where the ground is the main character. Tanks, trucks and
helicopters fight over fuel depots, and every vehicle that drives across a field
leaves ruts behind it. Mud gets churned up, ruts fill with rain and meltwater,
shells leave craters, and all of it slows the next vehicle down and makes it burn
more fuel. Get a column stuck in a bog and you will be sending a wrecker to drag
it out while the other side takes your depots.

## Playing

You start with a garage, two fuel depots, two tanks, a wrecker and an engineer.
The computer has the same on the other side of the map. Destroy every enemy
garage to win.

- **Fuel** is the only resource. Depots refill slowly, faster in clusters, and
  explode when destroyed (which can set off the depots next to them). Take the
  neutral depots by parking a unit on them.
- **Garages** build tanks and trucks, repair what is parked near them and break
  up towed-in wrecks for fuel. **Helipads** build helicopters and must be near a
  depot. Only an **engineer** can build.
- **Trucks** come with a kit: a **wrecker** winches and tows, a **tanker**
  carries fuel to the front, an **engineer** lays gravel road and builds, and a
  **water tanker** pumps from rivers and sprays the ground into mud (or puts out
  a fire).
- **Tanks** fire shells on a high arc that lead moving targets; ridges and tall
  buildings get in the way. **Gunships** fire rockets, **bucket helicopters**
  drop water. The **boss** speeds up nearby garages, the **hippy** throws smoke
  that slows and hides units, and the **nurse** heals.

### Controls

| Input | Does |
|---|---|
| Left click / drag | Select units (or one structure) |
| Right click | Move; on an enemy, attack; with a wrecker, winch a stuck vehicle |
| X | Wreckers let go |
| S | Stop |
| R | Engineers start or stop laying road |
| F | Use the special at the cursor (spray, drop, smoke) |
| WASD / arrows / screen edge | Pan |
| Mouse wheel | Zoom |
| Esc | Menu: save, load, new game on any map |
| F5 / F9 | Quick save / quick load |

### Maps

- **River crossing**: mud fields either side of a river you can only ford in two
  places.
- **Snowfield**: snow still falling, too cold to thaw, a lake down the middle.
- **Dunes**: sand drifting in a strong wind, rock ridges with gaps, an oasis.

## Running from source

You need Godot 4.7.2 (`godot` on your PATH, or set `GODOT`).

```sh
godot --headless --path . --import          # once, after cloning
./run-game.sh                               # 1920×1080 on the primary monitor
./run-game.sh --fullscreen -- --map=dunes   # --map=river|snowfield|dunes, --watch, --load=<path>
```

`--watch` lets the computer play both sides. The Mud Lab (`tools/mud_lab.tscn`)
is a sandbox for the ground: drive, dig, pour water and tune the shaders.

## Tests

```sh
KIT_TEST_HEADLESS=1 ./run-tests.sh res://tests/unit
KIT_TEST_HEADLESS=1 ./run-tests.sh res://tests/integration
./run-leak-check.sh
ci/run-probes.sh                            # render probes, needs xvfb
```

How it is built is written up in `docs/`: the ground (`ground.md`), the RTS rules
(`rts.md`), the units (`units.md`) and the ECS rules and measurements (`ecs.md`).

## Licence

The game's code is MIT licensed (`LICENSE`). Third-party software and art are
credited, with their licences, in `CREDITS.md`.
