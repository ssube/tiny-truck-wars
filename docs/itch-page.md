# itch.io page: Tiny Truck Wars

**Title:** Tiny Truck Wars (tech demo)

**Short description:** A tiny RTS where the mud fights back.

**Classification:** Game, released as a demo. Genre: Strategy. Tags: rts,
real-time-strategy, top-down, pixel-art, simulation, tanks, singleplayer,
godot. Platforms: Windows, Linux, HTML5 (playable in the browser).

**Pricing:** No payment (or "name your own price", minimum 0).

---

## Page body

Tiny Truck Wars is a tech demo of a small RTS I have been building in Godot,
where most of the work went into the ground rather than the armies.

Every vehicle that drives across a field leaves ruts. Mud gets pushed into
berms, rain and snowmelt fill the ruts with water, shells leave craters, and
all of it slows the next vehicle down and makes it burn more fuel. Drive a
column through the same bog twice and it gets stuck, and then you are sending
a wrecker out to winch it free while the other side takes your fuel depots.

What is in this version:

- Three skirmish maps against a computer opponent: a river with two fords, a
  snowfield with a lake down the middle, and sand dunes with rock ridges.
- Tanks that fire shells on an arc and lead moving targets, helicopters that
  get pushed around by the wind, and trucks fitted as wreckers, fuel tankers,
  engineers (who lay gravel road and build) and water tankers (who can make
  mud on purpose, or put out a fire).
- Fuel depots that refill faster in clusters and explode when they are
  destroyed, sometimes taking their neighbours with them.
- The Mud Lab, a sandbox where you can drive, dig, pour water and watch the
  ground react.

It is a demo: the art is mostly placeholder, there is no sound, the computer
opponent is simple, and the balance is rough. The browser version runs the
same simulation and can be slower than the downloads on a busy map.

### Controls

- Left click or drag to select, right click to move or attack.
- With a wrecker selected, right click a stuck vehicle to winch it out.
- R: engineers lay road. F: water tankers spray, bucket helicopters drop,
  hippies throw smoke at the cursor.
- WASD or arrows to pan, mouse wheel to zoom, Esc for the menu, F5 and F9 to
  save and load.

### Downloads

Windows and Linux: unzip and run `tiny-truck-wars.exe` or
`tiny-truck-wars.x86_64`. Saves go in your user data folder.

### Licence

The code is MIT and the source is on GitHub:
https://github.com/ssube/tiny-truck-wars. The art is CC BY-NC 4.0.
