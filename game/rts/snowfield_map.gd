class_name TtwSnowfieldMap extends RefCounted
## A winter map: snow over grass and frozen mud, deep in the hollows and
## thin on the rises, still falling; a long lake down the middle (too deep to
## drive) with land at its ends; gravel roads ploughed clear from each base;
## pine woods. Cold, so it does not thaw unless something burns. Mirrored.

const SIZE := Vector2i(88, 56)
const LAKE_X := 44
## The lake's rows: open land north and south of it.
const LAKE_ROWS := Vector2i(12, 44)
const LEVEL := -1.5
const DEEP := -12.0

static func terrain(seed: int = 11) -> TtwTerrain:
	var t := TtwTerrain.new(SIZE)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.06
	for y in SIZE.y:
		for x in SIZE.x:
			var mx := x if x < SIZE.x / 2 else SIZE.x - 1 - x
			var n := noise.get_noise_2d(mx, y)
			var id := TtwMaterials.GRASS
			if n > 0.15 and mx > 14:
				id = TtwMaterials.MUD
			elif n < -0.4:
				id = TtwMaterials.GRAVEL
			t.set_material(Vector2i(x, y), id)
			var rise := 14.0 * (0.5 + 0.5 * noise.get_noise_2d(mx * 0.5 + 50.0, y * 0.5))
			t.set_elevation(Vector2i(x, y), rise)
			# Deep in the hollows, thin on the rises.
			t.snow_base[t.tile_index(Vector2i(x, y))] = clampf(6.0 - rise * 0.25 + n * 2.0, 1.5, 7.0)
	# Ploughed gravel roads from each base round the lake's ends.
	for tile in road_tiles():
		t.set_material(tile, TtwMaterials.GRAVEL)
		t.snow_base[t.tile_index(tile)] = 0.3
	# The lake.
	var n := TtwTerrain.CELLS_PER_TILE
	for y in range(LAKE_ROWS.x, LAKE_ROWS.y):
		var narrowing := minf(y - LAKE_ROWS.x, LAKE_ROWS.y - 1 - y)
		var half := 2 + mini(int(narrowing), 3)
		for x in range(LAKE_X - half, LAKE_X + half):
			var tile := Vector2i(x, y)
			t.set_material(tile, TtwMaterials.SAND)
			t.water[t.tile_index(tile)] = LEVEL
			# Meltwater: clear and icy blue.
			t.water_color[t.tile_index(tile)] = Color(0.42, 0.62, 0.70, 0.7)
			t.snow_base[t.tile_index(tile)] = 0.0
			for cy in range(y * n, (y + 1) * n):
				for cx in range(x * n, (x + 1) * n):
					t.deform[cy * t.size_cells.x + cx] = DEEP
	t.mark_all()
	return t

## The road tiles (a set: tile -> true).
static func road_tiles() -> Dictionary:
	var out := {}
	for end_y in [LAKE_ROWS.x - 5, LAKE_ROWS.y + 5]:
		for x in range(6, SIZE.x - 6):
			var mx := x if x < SIZE.x / 2 else SIZE.x - 1 - x
			var y := roundi(lerpf(SIZE.y / 2.0, end_y, clampf((mx - 8.0) / 20.0, 0.0, 1.0)))
			for dy in range(-1, 1):
				out[Vector2i(x, y + dy)] = true
	return out

static func layout() -> Array[Dictionary]:
	var tile := TtwTerrain.tile_px()
	var out: Array[Dictionary] = []
	var mid := SIZE.y / 2.0
	for side in [1, 2]:
		TtwMaps.base(out, side, SIZE.x, mid)
		var toward := 1.0 if side == 1 else -1.0
		var edge := 0.0 if side == 1 else float(SIZE.x)
		# Pine woods between the base and the lake.
		for k in 10:
			var x := edge + toward * (20.0 + (k % 4) * 2.5)
			out.append({"kind": &"tree_pine", "at": Vector2(x, 16.0 + k * 2.6) * tile})
	TtwMaps.neutral_depot(out, Vector2(LAKE_X, LAKE_ROWS.x - 8.0))
	TtwMaps.neutral_depot(out, Vector2(LAKE_X, LAKE_ROWS.y + 8.0))
	TtwMaps.neutral_depot(out, Vector2(LAKE_X - 12.0, mid))
	TtwMaps.neutral_depot(out, Vector2(LAKE_X + 12.0, mid))
	out.append({"kind": &"shed", "at": Vector2(LAKE_X - 6.0, LAKE_ROWS.x - 4.0) * tile})
	out.append({"kind": &"shed", "at": Vector2(LAKE_X + 6.0, LAKE_ROWS.y + 4.0) * tile})
	return out

static func weather(w: TtwWeather) -> void:
	w.temperature = -4.0
	w.sun = 0.3
	w.snowfall = 0.25
	w.rain = 0.0
	w.wind = Vector2(14.0, 6.0)
