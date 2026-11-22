# itch.io page: Tiny Truck Wars

The page's fields, in the order the edit form asks for them.

| Field | Value |
|---|---|
| Title | Tiny Truck Wars |
| Project URL | tiny-truck-wars |
| Short description | A tiny RTS where the mud fights back. |
| Classification | Games |
| Kind of project | HTML (the web build plays in the page; the Windows and Linux zips are extra downloads) |
| Release status | Prototype |
| Pricing | $0 or donate (suggested: $0) |
| Uploads | Pushed with butler (`ci/itch-push.sh`): channel `web` (tick "This file will be played in the browser"), `windows` (tick Windows), `linux` (tick Linux) |
| Embed | Embed in page, manually set size 1280 × 720; Fullscreen button on; not mobile friendly; do not start on page load (about 40 MB to load); no scrollbars; SharedArrayBuffer off (the web build is single-threaded) |
| Genre | Strategy |
| Tags (max 10) | rts, real-time-strategy, top-down, pixel-art, tanks, simulation, sandbox, physics, godot, singleplayer |
| AI generation disclosure | Yes: Graphics, Code |
| Statement of AI usage | The vehicle and building sprites were generated from my descriptions and then picked and cleaned up by hand. Much of the code was written with an AI coding assistant, working from my design and my review. |
| Custom noun | (blank) |
| Community | Comments |
| Visibility | Draft until the page has been looked over, then Public |
| Cover image | `reports/itch/cover.png` (630 × 500) |
| Gameplay video | the AI-vs-AI clip (`reports/itch/clip.mp4`), uploaded to YouTube first |
| Screenshots | `reports/itch/shot-1-battle.png` … `shot-5-chain.png` (1920 × 1080) |

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
- Ctrl and right click to fire at a spot on the ground, a tree or a house.
- With a wrecker selected, right click a stuck vehicle to winch it out, or a tree to winch itself out of the mud.
- H: stop. X: wreckers let go. R: engineers lay road. F: water tankers spray, bucket helicopters drop,
  hippies throw smoke at the cursor.
- WASD or arrows to pan, mouse wheel to zoom, Esc for the menu, F5 and F9 to
  save and load.

### Units

Garages build the ground vehicles; helipads build the helicopters. Tanks shove trucks and cars out of the way, trucks shove cars, and cars can't push anything.

- **Tank**: the main fighter. Fires shells on an arc that lead moving targets; ridges and tall buildings can stop them. Can shoot at helicopters too, hitting about one shot in three.
- **Wrecker**: a truck with a winch and tow hitch. Pulls stuck vehicles out of the mud, winches itself out on a tree, and tows wrecks home, where the garage breaks them up for fuel. Only a winch can move a wreck.
- **Tanker**: a truck that fills up at your depots and refuels anything of yours parked near it, including landed helicopters.
- **Engineer**: the only unit that can build. Garages, depots and helipads can only be put down within a few tiles of an engineer, and it can lay gravel road over the mud as it drives (R).
- **Water tanker**: pumps from rivers and ponds, then sprays a spot (F) to turn a field into mud on purpose or put out a fire.
- **Hippy**: a beaten-up car that throws a smoke screen (F). Ground units in the smoke slow down, and tanks can't pick out targets inside it.
- **Boss**: a black state limousine. Garages and helipads near it build faster.
- **Nurse**: a field ambulance that repairs your tanks and trucks nearby, but not helicopters.
- **Gunship**: a helicopter that fires rockets at ground targets. Flies over rivers and mud, gets pushed around by the wind, and lands on a helipad to refuel and repair.
- **Bucket helicopter**: dips a bucket in the river and drops it on a spot (F), for putting out fires or soaking the ground.

### Downloads

Windows and Linux: unzip and run `tiny-truck-wars.exe` or
`tiny-truck-wars.x86_64`. Saves go in your user data folder.

### Licence

The code is MIT and the source is on GitHub:
https://github.com/ssube/tiny-truck-wars. The art is CC BY-NC 4.0.
