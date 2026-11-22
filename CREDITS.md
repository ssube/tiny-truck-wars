# Tiny Truck Wars: credits

## Art

All art in `assets/` is © 2026 Sean Sube, licensed CC BY-NC 4.0
(`licenses/Art-CC-BY-NC-4.0.md`).

- The unit and structure sprites (trucks, tank, helicopter, hippy van, boss
  limousine, field ambulance, garage, depot, helipad) were generated with
  PixelLab (https://pixellab.ai) from written prompts, then chosen and
  imported by hand.
- Trees, logs, buildings, rubble and the effect textures are placeholder art
  drawn by scripts in `tools/`.
- The ground is drawn by the game's shaders (code, MIT).

## Software

- **Godot Engine** (https://godotengine.org), MIT licence: `licenses/Godot.txt`.
  Godot's own third-party components are listed at https://godotengine.org/license.
- **GECS** (https://github.com/csprance/gecs), the entity component system,
  CC0 1.0: `licenses/GECS.txt`. The copy in `addons/gecs` carries one fix (an
  entity added to an existing archetype now invalidates cached queries).
- **gdUnit4** (https://github.com/MikeSchulze/gdUnit4), MIT licence, is used for
  the tests only and is not part of the game's builds.
