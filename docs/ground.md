# The ground

Mud, ruts, craters and water are simulated on the CPU (the truth that
gameplay and tests read), drawn by one terrain shader with parallax depth, and
dressed with visual-only effects on the GPU and in particles. The simulation
never uses level of detail; only drawing does.

## Layers (`game/terrain/terrain.gd`, `TtwTerrain`)

| Layer | Resolution | Meaning |
|---|---|---|
| `surface` | tile (16 px) | material id (`TtwMaterials`: mud, grass, pavement, gravel, sand, rock) |
| `elevation` | tile, bilinear | height in px; drawn as shading and a rock band on steep drops |
| `water`, `flow` | tile | the water's level (relief px) and current (px/s), kept by `TtwWater` |
| `deform` | cell (2 px) | signed height: ruts below 0, berms and rims above |
| `loose` | cell | loose mud lying on the ground (part of the height too) |
| `wet` | cell | 0..1; dries over 2 minutes, stays 1 under water |
| `track`, `track_angle` | cell | how fresh a tread print is, and its direction |
| `wear` | cell | worn-through grass is mud, worn-through pavement is gravel (`effective_material`) |
| `scorch` | cell | burn marks, fading over 4 minutes |
| `oil` | cell | oil on the ground (a film; ~0.2 takes all the grip it can); afloat it is `TtwWater.slick` |
| `snow_base`, `snow_level`, `snow_gone` | tile, map, cell | snow = base + level − gone (`TtwSnow`); gone is negative in berms |

Cell layers are separate packed-array members, never in a container (a
`container[i][j] = v` write copies the whole layer). Bulk writers write the
members, then call `mark_cells(rect)` once.

## What changes it

- **Presses** (`TtwStamps.press`, from `TtwTrackSystem`): once per contact per
  cell it enters. Squeezes out loose mud, sinks the ground as far as the material
  holds, and pushes the moved volume into berms (60%), a bow wave and spray (as
  loose mud), and some onto the vehicle, which drops it further on. A vehicle
  spinning in place presses again and digs itself in. Volume is conserved,
  except what a material compacts in place (`DISPLACE`), which springs back.
- **Craters** (`TtwStamps.crater`, by cause: shell < rocket < vehicle < building
  < depot): a bowl, its volume thrown into a rim and clods; tears and scorches.
- **Settling** (`TtwSettleSystem`): only disturbed cells, each about once a
  second: prints and burns fade, ground dries, grass springs back, and ground
  steeper than its material's angle of repose slumps (volume kept).
- **Water** (`TtwWater`, `TtwWaterSystem`): a virtual-pipe model on tiles over the
  wet area only. A tile holds a volume; its level comes from how its cells lie,
  so a little water fills only the ruts. Sources and sinks (`water_sources`,
  `water_sinks` on the terrain) keep their books (`added`, `drained`).

- **Oil** (`TtwOil`, `TtwOilSystem`): spilt onto the ground, or onto the water as a
  slick that the water's flux carries downstream (volume kept; a drying tile
  leaves it on the ground, flooded ground lifts it off). Wrecks bleed, worn
  vehicles drip, tyres smear it. It is fuel for the fire and burns away.
- **Snow** (`TtwSnow`, `TtwSnowSystem`): snowfall and thaw move one map-wide
  level; presses pack it and push berms; blasts and fire clear and melt it. The
  thaw is booked every two seconds: runoff into rutted tiles' water, the rest
  into the soil's moisture.
- **Fire** (`TtwFireField`, `TtwFireSystem`): per tile, burning tiles only. Fuel
  from trees, logs, buildings, wrecks and oil; spreads to neighbours (faster
  downwind); water, soaked ground and rain put it out (a slick burns on water).
  It hurts what stands in it, scorches, melts snow, burns oil.
- **Weather** (`TtwWeather`, `TtwWeatherSystem`): temperature, sun, wind (the
  a three-beat gust, on the tick), rain and snowfall; rain wets the soil as one
  global value. Sand dries fast, packs firm when damp, and drifts downwind.
- **Pour and draw** (`TtwWater.pour`, `.draw`, `TtwGame.pour`): water tankers and
  buckets: volume in or out (booked), the ground soaked, fires put out.

## World objects (`game/world/`, `prefabs/world/`)

Trees, logs and buildings are static bodies on the structures layer with
health (`TtwHealth`) and an obstacle shape (`TtwObstacle`). The physics engine
finds what is near each vehicle; `TtwObstacles` pushes it out (exact circle and
box geometry). A fast heavy vehicle rams and hurts what it hits. A destroyed
tree falls away from the hit into a log; a log splinters and floats; a
building collapses into a crater and rubble (gravel, heaped). Blasts go
through `TtwGame.explode` (crater, look, damage, fire). Art is placeholder from
`tools/make_world_textures.py`.

## Driving (`TtwDriveSystem`)

`speed = max × throttle × slope / resistance`. Resistance comes from the
material, ruts (crossing costs far more than following), loose mud, wetness and
water. Grade and current are signed along the heading. Fuel burns by effort.
Water deeper than the wading depth wears the vehicle, faster than the depth;
water at the intake floods the engine (1% health, no restart, no explosion).
Strain (water, steep climbs, pushing against traction) fills a stall meter;
more than 95% worn, a stall is for good. Grip (oil, packed snow) cuts
traction, acceleration and steering; loose snow adds resistance. Trees, logs
and buildings stop it (TtwObstacleSystem).

## Drawing

- `shaders/terrain.gdshader`, one quad per 16×16-tile chunk (`TtwTerrainView`):
  material splat in three-tone palettes with wandering edges, relief ray-marched
  along the camera's tilt per world pixel, cavity and ridge light, self-shadow,
  tread chevrons, wear, burns, a tide line, glistening spoil, drying cracks.
- Water: waves travelling with the current, contact and crest foam, refraction,
  depth absorption, caustics, sky at grazing angles, plus the GPU detail
  below.
- Tiers: full near the view's centre, mid and far further out or zoomed out,
  with hysteresis and a cross-fade. Off-screen chunks are not drawn or uploaded.
- The chunks are drawn into a buffer of one texel per world pixel over what
  the camera shows, and the buffer is put on screen enlarged: the shader
  runs once per world pixel, not once per screen pixel. A changed chunk
  uploads only the layers that were written (`mark_cells(rect, layers)`).
- Overlays (Mud Lab `O`): wear, wetness, relief, loose mud, tread prints, scorch,
  water depth, material, elevation, oil, snow depth, LOD tier.
- Oil: a dark stain and a banded thin-film sheen; snow: soft drifts, blue
  shade, sparkle, slush in a thaw; precipitation over the view (`TtwPrecipitation`).

## Visual-only effects (`game/fx/`)

- `TtwWaterFx`: a never-cleared HDR buffer, one texel per quarter tile: foam and
  silt carried by the current, ripples from a damped wave equation (wakes,
  splashes, rain, the spray of a blast falling back). Never read back.
- `TtwDebris`: clods, droplets and wreckage with rough physics: arcs, bounces,
  sliding downhill, drifting downstream; droplets ripple where they land. At most
  600; those out of view are not drawn and move every fourth frame.
- `TtwPuffs`: pooled dust and smoke emitters under a particle budget. Smoke is lit
  from the top left, and from below where there is fire.
- `TtwFire` (flames, shimmer, firelight on the ground, lit smoke),
  `TtwSmokeScreen`, and `TtwFx.explode` for the look of any blast.

## Tools and checks

- Mud Lab: `godot --path . res://tools/mud_lab.tscn` (keys in `tools/mud_lab.gd`).
- Review pictures: `ci/run-probes.sh` writes `reports/render/*.png` (mud lab,
  drive, water, fx); `perf_probe` writes `reports/render/perf.txt`, and
  `fps_probe` where a frame's time goes (`reports/render/fps.txt`).
