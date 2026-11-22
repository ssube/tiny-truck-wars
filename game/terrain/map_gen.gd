class_name TtwMapGen extends RefCounted
## Deterministic test grounds, built from a seed. Real maps are authored; these
## give the Mud Lab and the tests every material, a hill, a channel of water and
## a cliff in a small space.

## The Mud Lab's ground: a mud field around a paved road, gravel and sand
## patches, a hill, a river channel with water in it and a cliff edge.
## px the river's valley falls per tile southward.
const RIVER_FALL := 0.25
## The river's level in its channel (relief px): below the banks (0).
const RIVER_LEVEL := -1.5

static func mud_lab(tiles: Vector2i = Vector2i(64, 40), seed: int = 7) -> TtwTerrain:
	var terrain := TtwTerrain.new(tiles)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.08
	var road_y := tiles.y / 2
	var river_x := int(tiles.x * 0.78)
	for y in tiles.y:
		for x in tiles.x:
			var tile := Vector2i(x, y)
			var n := noise.get_noise_2d(x, y)
			var id := TtwMaterials.GRASS
			if n > -0.05 and x > 6 and x < river_x - 4:
				id = TtwMaterials.MUD
			if abs(y - road_y) <= 1 and x < river_x - 3:
				id = TtwMaterials.PAVEMENT
			elif abs(x - 10) <= 3 and abs(y - road_y + 7) <= 2:
				id = TtwMaterials.GRAVEL
			elif abs(x - river_x) <= 4:
				id = TtwMaterials.SAND
			terrain.set_material(tile, id)
			# A low hill top-left, a step up to a rock shelf bottom-right.
			var hill := 24.0 * exp(-Vector2(x - 14, y - 8).length_squared() / 40.0)
			var shelf := 20.0 if x > river_x + 5 and y > tiles.y - 12 else 0.0
			if shelf > 0.0:
				terrain.set_material(tile, TtwMaterials.ROCK if y < tiles.y - 10 else TtwMaterials.GRASS)
			# The river's valley falls gently to the south, so it runs.
			var valley := -RIVER_FALL * y if abs(x - river_x) <= 4 else 0.0
			terrain.set_elevation(tile, hill + shelf + valley)
	# The river: a channel cut into the relief, filled to a level.
	for y in tiles.y:
		for x in range(river_x - 2, river_x + 3):
			terrain.water[terrain.tile_index(Vector2i(x, y))] = RIVER_LEVEL
	var channel := Rect2i(Vector2i((river_x - 2) * TtwTerrain.CELLS_PER_TILE, 0), Vector2i(5 * TtwTerrain.CELLS_PER_TILE, terrain.size_cells.y))
	for cy in range(channel.position.y, channel.end.y):
		for cx in range(channel.position.x, channel.end.x):
			var across := (float(cx - channel.position.x) + 0.5) / channel.size.x * 2.0 - 1.0
			terrain.deform[cy * terrain.size_cells.x + cx] = -7.0 * (1.0 - across * across)
	# Fed at the top edge, drained at the bottom.
	var channel_tiles := Rect2i(river_x - 2, 0, 5, 1)
	terrain.water_sources.append({"rect": channel_tiles, "level": RIVER_LEVEL})
	terrain.water_sinks.append({"rect": Rect2i(river_x - 2, tiles.y - 1, 5, 1), "level": -RIVER_FALL * (tiles.y - 1) + RIVER_LEVEL - 1.0})
	terrain.mark_all()
	return terrain

## The Mud Lab's trees and buildings: a grove on the hill, a few trees along
## the river and by the road, and buildings beside the road.
static func mud_lab_props(tiles: Vector2i, seed: int = 7) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Dictionary] = []
	var tile := TtwTerrain.tile_px()
	var kinds := [&"tree_oak", &"tree_oak_b", &"tree_pine"]
	for k in 14:
		var at := Vector2(14, 8) * tile + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 80.0)
		out.append({"kind": kinds[k % 3], "at": at})
	var river_x := int(tiles.x * 0.78)
	for k in 6:
		out.append({"kind": &"tree_pine", "at": Vector2(river_x + 6.5, 3 + k * 5.5) * tile})
	var road_y := tiles.y / 2
	out.append({"kind": &"house", "at": Vector2(30, road_y - 2.5) * tile})
	out.append({"kind": &"shed", "at": Vector2(36, road_y - 2.5) * tile})
	out.append({"kind": &"barracks", "at": Vector2(24, road_y + 7) * tile})
	return out
