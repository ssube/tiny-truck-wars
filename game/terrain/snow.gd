class_name TtwSnow extends RefCounted
## Snow on the ground: a cell's depth is the tile's authored snow plus the
## map-wide fallen-less-thawed level less what was taken from that cell
## (pressed, melted, blown off; negative where pushed up into a berm).

## Share of the snow under a contact pressed down by a pass, and the share of
## that pushed aside into berms either side.
const PACK := 0.6
const ASIDE := 0.35
const BERM_PX := 3.0
## Taken from a cell, past this snow counts as packed (firm and slippery).
const PACKED := 0.4

static func depth_at(t: TtwTerrain, cell: int) -> float:
	var n := TtwTerrain.CELLS_PER_TILE
	var tile := (cell / t.size_cells.x / n) * t.size_tiles.x + (cell % t.size_cells.x) / n
	return maxf(0.0, t.snow_base[tile] + t.snow_level - t.snow_gone[cell])

static func depth(t: TtwTerrain, world: Vector2) -> float:
	return depth_at(t, t.cell_index(t.cell_of(world).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)))

## Whether a cell's snow is packed (pressed firm: slippery).
static func is_packed(t: TtwTerrain, cell: int) -> bool:
	return t.snow_gone[cell] > PACKED and depth_at(t, cell) > 0.1

## A contact patch packs the snow under it and pushes some into berms.
static func press(t: TtwTerrain, center: Vector2, heading: float, length_px: float, width_px: float) -> void:
	var along := Vector2.from_angle(heading)
	var side := along.orthogonal()
	var cell_px := TtwTerrain.cell_px()
	var reach := maxf(length_px, width_px) * 0.5 + BERM_PX + cell_px
	var lo := t.cell_of(center - Vector2(reach, reach)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var hi := t.cell_of(center + Vector2(reach, reach)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var foot: PackedInt32Array = []
	var berm: PackedInt32Array = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px - center
			var u := absf(p.dot(along))
			var v := absf(p.dot(side))
			if u <= length_px * 0.5:
				if v <= width_px * 0.5:
					foot.append(y * t.size_cells.x + x)
				elif v <= width_px * 0.5 + BERM_PX:
					berm.append(y * t.size_cells.x + x)
	var pushed := 0.0
	for i in foot:
		var d := depth_at(t, i)
		if d <= 0.0:
			continue
		var packed := d * PACK
		t.snow_gone[i] += packed
		pushed += packed * ASIDE
	if pushed > 0.0 and not berm.is_empty():
		var each := pushed / berm.size()
		for i in berm:
			t.snow_gone[i] -= each
	if pushed > 0.0:
		t.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE))

## A blast throws the snow off a disc (and melts it).
static func blast(t: TtwTerrain, at: Vector2, radius_px: float) -> void:
	var cell_px := TtwTerrain.cell_px()
	var lo := t.cell_of(at - Vector2(radius_px, radius_px)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var hi := t.cell_of(at + Vector2(radius_px, radius_px)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if ((Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px).distance_to(at) <= radius_px:
				var i := y * t.size_cells.x + x
				t.snow_gone[i] += depth_at(t, i)
	t.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE))

## Melts about `amount` (px) of snow off a tile (fire on it): most in the
## middle, unevenly toward the edge, so the hole is not a square.
static func melt_tile(t: TtwTerrain, tile: Vector2i, amount: float) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	var middle := (Vector2(tile) + Vector2(0.5, 0.5)) * n
	for cy in range(tile.y * n, tile.y * n + n):
		for cx in range(tile.x * n, tile.x * n + n):
			var i := cy * t.size_cells.x + cx
			var edge := Vector2(cx + 0.5, cy + 0.5).distance_to(middle) / (n * 0.7)
			var jitter := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			var share := clampf(1.3 - edge + (jitter - 0.5) * 0.6, 0.15, 1.0)
			t.snow_gone[i] += minf(amount * share, depth_at(t, i))
	t.mark_cells(Rect2i(tile * n, Vector2i(n, n)))
