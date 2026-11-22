class_name TtwDunesMap extends RefCounted
## A desert map: sand everywhere, drifting in a strong wind; gravel tracks
## between the bases; two rock ridges across the middle that only gaps get
## through (they also stop shells); an oasis pond in the middle with trees
## round it. Hot and dry. Mirrored.

const SIZE := Vector2i(96, 56)
## Each ridge's middle column (they mirror: 95 - 36 = 59).
const RIDGE_X := [36, 59]
## The rows where each ridge is open.
const GAPS := [12, 28, 44]
const RIDGE_PX := 30.0

static func terrain(seed: int = 5) -> TtwTerrain:
	var t := TtwTerrain.new(SIZE)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.05
	for y in SIZE.y:
		for x in SIZE.x:
			var mx := x if x < SIZE.x / 2 else SIZE.x - 1 - x
			var n := noise.get_noise_2d(mx, y)
			t.set_material(Vector2i(x, y), TtwMaterials.GRAVEL if n < -0.45 else TtwMaterials.SAND)
			# Dunes: long low swells across the wind.
			var dune := 6.0 * (0.5 + 0.5 * sin(mx * 0.35 + n * 3.0))
			t.set_elevation(Vector2i(x, y), dune)
	# The ridges, rock, open at the gaps.
	for rx in RIDGE_X:
		for y in SIZE.y:
			var open := false
			for g in GAPS:
				if absi(y - g) <= 2:
					open = true
			if open:
				continue
			for x in range(rx - 1, rx + 2):
				t.set_material(Vector2i(x, y), TtwMaterials.ROCK)
				t.set_elevation(Vector2i(x, y), RIDGE_PX)
	# Gravel tracks from each base to the gaps.
	for tile in road_tiles():
		t.set_material(tile, TtwMaterials.GRAVEL)
	# The oasis: a pond, with grass round it.
	var center := Vector2(SIZE.x / 2.0, SIZE.y / 2.0)
	var n := TtwTerrain.CELLS_PER_TILE
	for y in range(int(center.y) - 7, int(center.y) + 7):
		for x in range(int(center.x) - 7, int(center.x) + 7):
			var tile := Vector2i(x, y)
			var d := (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(center)
			if d < 6.5:
				t.set_material(tile, TtwMaterials.GRASS)
				t.set_elevation(tile, 0.0)
			if d < 3.5:
				t.set_material(tile, TtwMaterials.MUD)
				t.water[t.tile_index(tile)] = -1.0
				for cy in range(y * n, (y + 1) * n):
					for cx in range(x * n, (x + 1) * n):
						t.deform[cy * t.size_cells.x + cx] = -6.0 * (1.0 - d / 3.5) - 1.5
	t.mark_all()
	return t

## The track tiles (a set: tile -> true), not over the ridges.
static func road_tiles() -> Dictionary:
	var out := {}
	for g in GAPS:
		for x in range(8, SIZE.x - 8):
			var mx := x if x < SIZE.x / 2 else SIZE.x - 1 - x
			var y := roundi(lerpf(SIZE.y / 2.0, g, clampf((mx - 8.0) / 24.0, 0.0, 1.0)))
			if not _ridge(Vector2i(x, y)):
				out[Vector2i(x, y)] = true
	return out

## Whether a tile is rock ridge.
static func _ridge(tile: Vector2i) -> bool:
	for rx in RIDGE_X:
		if absi(tile.x - rx) <= 1 and not GAPS.any(func(g): return absi(tile.y - g) <= 2):
			return true
	return false

static func layout() -> Array[Dictionary]:
	var tile := TtwTerrain.tile_px()
	var out: Array[Dictionary] = []
	var mid := SIZE.y / 2.0
	for side in [1, 2]:
		TtwMaps.base(out, side, SIZE.x, mid)
	var center := Vector2(SIZE.x / 2.0, mid)
	for k in 7:
		var a := TAU * k / 7.0 + 0.3
		out.append({"kind": [&"tree_oak", &"tree_oak_b"][k % 2], "at": (center + Vector2.from_angle(a) * 5.2) * tile})
	for x in [RIDGE_X[0] - 6.0, RIDGE_X[1] + 6.0]:
		TtwMaps.neutral_depot(out, Vector2(x, GAPS[0]))
		TtwMaps.neutral_depot(out, Vector2(x, GAPS[2]))
	out.append({"kind": &"barracks", "at": Vector2(center.x, 6.0) * tile})
	out.append({"kind": &"barracks", "at": Vector2(center.x, SIZE.y - 6.0) * tile})
	return out

static func weather(w: TtwWeather) -> void:
	w.temperature = 32.0
	w.sun = 1.0
	w.snowfall = 0.0
	w.rain = 0.0
	w.wind = Vector2(42.0, 8.0)
