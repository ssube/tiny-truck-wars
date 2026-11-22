class_name TtwSkirmishMap extends RefCounted
## The first skirmish map: two bases, west (side 1) and east (side 2), a
## river between them too deep to drive through except at two fords, mud
## fields either side, roads from each base to the fords, groves, and four
## neutral depots to take: north, south and two either side of the river in
## the middle. Mirrored, so neither side has the better start.

const SIZE := Vector2i(96, 56)
## The river's middle: the line between tiles 47 and 48, the map's middle.
## Its channel is tiles RIVER_X - 2 to RIVER_X + 1, its sand banks 6 tiles
## either side of the line.
const RIVER_X := 48
const CHANNEL := Vector2i(RIVER_X - 2, RIVER_X + 2)
## Water level (relief px): the channel is deep (a wall) except at the fords.
const LEVEL := -1.5
const DEEP := -12.0
const FORD := -4.0
const FORDS := [14, 41]

static func terrain(seed: int = 3) -> TtwTerrain:
	var t := TtwTerrain.new(SIZE)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.07
	for y in SIZE.y:
		for x in SIZE.x:
			# Mirror the noise so both halves match.
			var mx := x if x < SIZE.x / 2 else SIZE.x - 1 - x
			var n := noise.get_noise_2d(mx, y)
			var id := TtwMaterials.GRASS
			if n > 0.05 and mx > 16:
				id = TtwMaterials.MUD
			elif n < -0.45:
				id = TtwMaterials.GRAVEL
			if _from_middle(x) <= 5.5:
				id = TtwMaterials.SAND
			t.set_material(Vector2i(x, y), id)
			# Low rises behind each base.
			var rise := 18.0 * exp(-pow(mx - 3.0, 2.0) / 30.0) * (0.6 + 0.4 * sin(y * 0.2))
			t.set_elevation(Vector2i(x, y), rise)
	# Roads: from each base east-west to each ford.
	for tile in road_tiles():
		t.set_material(tile, TtwMaterials.PAVEMENT)
	# The river: a channel, deep except at the fords.
	var n := TtwTerrain.CELLS_PER_TILE
	for y in SIZE.y:
		var depth := DEEP
		for ford_y in FORDS:
			if absi(y - ford_y) <= 2:
				depth = FORD
		var wide := CHANNEL.y - CHANNEL.x
		for x in range(CHANNEL.x, CHANNEL.y):
			t.water[t.tile_index(Vector2i(x, y))] = LEVEL
		for cy in range(y * n, (y + 1) * n):
			for cx in range(CHANNEL.x * n, CHANNEL.y * n):
				var across := (float(cx - CHANNEL.x * n) + 0.5) / (wide * n) * 2.0 - 1.0
				t.deform[cy * t.size_cells.x + cx] = depth * (1.0 - across * across)
	t.water_sources.append({"rect": Rect2i(CHANNEL.x, 0, CHANNEL.y - CHANNEL.x, 1), "level": LEVEL})
	t.water_sinks.append({"rect": Rect2i(CHANNEL.x, SIZE.y - 1, CHANNEL.y - CHANNEL.x, 1), "level": LEVEL - 1.0})
	t.mark_all()
	return t

## The road tiles: from each base to each ford (a set: tile -> true).
static func road_tiles() -> Dictionary:
	var out := {}
	for ford_y in FORDS:
		for x in range(8, SIZE.x - 8):
			if _from_middle(x) <= 5.5:
				continue
			var span := _from_middle(x) / float(RIVER_X - 8)
			var y := roundi(lerpf(ford_y, SIZE.y / 2, clampf(span, 0.0, 1.0)))
			for dy in range(-1, 1):
				out[Vector2i(x, y + dy)] = true
	return out

## How far tile column `x`'s middle is from the river's middle line (tiles).
static func _from_middle(x: int) -> float:
	return absf(x + 0.5 - RIVER_X)

## What stands on the map: {kind, at, team?, structure?} (world px).
static func layout() -> Array[Dictionary]:
	var tile := TtwTerrain.tile_px()
	var out: Array[Dictionary] = []
	var mid := SIZE.y / 2.0
	for side in [1, 2]:
		TtwMaps.base(out, side, SIZE.x, mid)
		var toward := 1.0 if side == 1 else -1.0
		# Groves between the base and the river.
		for k in 6:
			var gx := RIVER_X - toward * (12.0 + (k % 3) * 2.0)
			out.append({"kind": [&"tree_oak", &"tree_pine", &"tree_oak_b"][k % 3], "at": Vector2(gx, 6.0 + k * 1.7) * tile})
			out.append({"kind": [&"tree_pine", &"tree_oak", &"tree_oak_b"][k % 3], "at": Vector2(gx, SIZE.y - 6.0 - k * 1.7) * tile})
	# Neutral depots: north and south on the river banks, and two in the middle.
	TtwMaps.neutral_depot(out, Vector2(RIVER_X - 9.0, 5.0))
	TtwMaps.neutral_depot(out, Vector2(RIVER_X + 9.0, SIZE.y - 5.0))
	TtwMaps.neutral_depot(out, Vector2(RIVER_X - 9.0, mid))
	TtwMaps.neutral_depot(out, Vector2(RIVER_X + 9.0, mid))
	out.append({"kind": &"house", "at": Vector2(RIVER_X - 14.0, FORDS[0] + 4.0) * tile})
	out.append({"kind": &"house", "at": Vector2(RIVER_X + 14.0, FORDS[1] - 4.0) * tile})
	return out

## Spring: mild, a breeze.
static func weather(w: TtwWeather) -> void:
	w.temperature = 8.0
	w.sun = 0.5
	w.rain = 0.0
	w.snowfall = 0.0
	w.wind = Vector2(18.0, 4.0)
