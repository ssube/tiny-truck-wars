class_name Kit2D extends RefCounted
## Shared world units. Art packs pick their tile size in Project Settings
## (kit/world/tile_size); gameplay distances are authored in tiles and converted here.

const TILE_SIZE_SETTING := "kit/world/tile_size"

# Physics layer bits, matching [layer_names] in project.godot.
const LAYER_GROUND_UNITS := 1
const LAYER_AIR_UNITS := 2
const LAYER_STRUCTURES := 4
const LAYER_AREAS := 8

static func tile_size() -> int:
	return int(ProjectSettings.get_setting(TILE_SIZE_SETTING, 16))

static func tiles(count: float) -> float:
	return count * tile_size()
