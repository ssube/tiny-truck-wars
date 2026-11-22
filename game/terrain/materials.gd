class_name TtwMaterials extends RefCounted
## The ground's surface materials and what each does under a wheel. Ids are
## stored one byte per tile in TtwTerrain.surface and read by the terrain
## shader by the same number, so the order here is fixed.

enum { MUD, GRASS, PAVEMENT, GRAVEL, SAND, ROCK }

const NAMES := ["mud", "grass", "pavement", "gravel", "sand", "rock"]
const COUNT := 6

## How far a pass sinks in, as a share of the vehicle's own sink (0 = hard).
const SOFTNESS := [1.0, 0.45, 0.0, 0.12, 0.6, 0.0]
## Deepest rut (px) the material holds; deeper digging spills to the berms.
const MAX_DEPTH := [7.0, 3.0, 0.0, 1.5, 4.0, 0.0]
## Share of a rut that springs back per simulated second: compacted grass
## recovers; mud and sand keep their shape (sand slumps instead).
const REBOUND := [0.0, 0.02, 0.0, 0.0, 0.0, 0.0]
## How much wetness softens it further: softness × (1 + WET_SOFTENING × wetness).
## Sand is the other way about: damp sand packs firm.
const WET_SOFTENING := [1.2, 0.8, 0.0, 0.3, -0.6, 0.0]
## Wear per pass per px of the vehicle's sink. Grass worn to 1 is torn up
## (mud); pavement worn to 1 is broken (gravel). Pavement wears ~40x slower.
const WEAR_RATE := [0.0, 0.22, 0.006, 0.0, 0.0, 0.0]
## Share of what a press moves that is pushed aside (berms, bow, spray); the
## rest is compacted in place. Grass compacts and springs back.
const DISPLACE := [1.0, 0.35, 1.0, 0.6, 0.85, 1.0]
## The steepest step (px of height between neighbouring cells) a material
## holds; steeper slumps toward it (TtwSettleSystem). Hard ground never slumps.
const REPOSE := [1.0, 1.8, INF, 1.2, 0.7, INF]
## How much faster than other ground it dries, and its tread prints fade
## (sand lets go of both quickly).
const DRY_RATE := [1.0, 1.0, 1.0, 1.5, 3.0, 1.0]
const PRINT_FADE := [1.0, 1.0, 1.0, 1.0, 3.0, 1.0]
## How readily dry ground drinks water standing on it (TtwWater): mud is
## nearly full, pavement and rock take none, sand drinks fastest.
const INFILTRATES := [0.5, 1.0, 0.0, 1.0, 1.5, 0.0]
## Base rolling resistance (1 = paved road) before ruts, mud and water.
const RESISTANCE := [2.2, 1.35, 1.0, 1.15, 1.6, 1.0]

## What each becomes once worn through (wear >= 1): torn grass is mud, broken
## pavement is gravel. Loops that cannot afford a call read this themselves.
const WORN := [MUD, MUD, GRAVEL, GRAVEL, SAND, ROCK]

static func is_valid(id: int) -> bool:
	return id >= 0 and id < COUNT

## What a tile of `base` behaves as when worn to `wear`.
static func effective(base: int, wear: float) -> int:
	return WORN[base] if wear >= 1.0 else base
