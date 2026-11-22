class_name TtwBrushes extends RefCounted
## Hand painting of the ground's layers (the Mud Lab, tests, map tools). Each
## call writes a round patch with a smooth edge and marks it once. These do not
## conserve volume: vehicles and explosions do (TtwStamps).

enum Kind { DIG, RAISE, LOOSE, WET, DRY, WATER, TRACK }

## Applies `kind` at `world` over `radius_px`, `amount` per call at the centre.
## `heading` (radians) orients TRACK. WATER raises the water level over the
## patch to at least `amount` (px, relief units): ruts below it fill.
static func paint(terrain: TtwTerrain, kind: int, world: Vector2, radius_px: float, amount: float, heading: float = 0.0, water: TtwWater = null) -> void:
	if kind == Kind.WATER:
		_paint_water(terrain, world, radius_px, amount, water)
		return
	var cell_px := TtwTerrain.cell_px()
	var center := world / cell_px
	var r := radius_px / cell_px
	var first := Vector2i((center - Vector2(r, r)).floor()).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var last := Vector2i((center + Vector2(r, r)).ceil()).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var width := terrain.size_cells.x
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) / maxf(r, 0.001)
			if d >= 1.0:
				continue
			var k := amount * (1.0 - d * d) * (1.0 - d * d)
			var i := y * width + x
			match kind:
				Kind.DIG:
					terrain.deform[i] -= k
				Kind.RAISE:
					terrain.deform[i] += k
				Kind.LOOSE:
					terrain.loose[i] = maxf(0.0, terrain.loose[i] + k)
				Kind.WET:
					terrain.wet[i] = clampf(terrain.wet[i] + k, 0.0, 1.0)
				Kind.DRY:
					terrain.wet[i] = clampf(terrain.wet[i] - k, 0.0, 1.0)
				Kind.TRACK:
					terrain.track[i] = clampf(terrain.track[i] + k, 0.0, 1.0)
					terrain.track_angle[i] = heading
	terrain.mark_cells(Rect2i(first, last - first + Vector2i.ONE))

## With a simulation, water is poured in (to the level) and then flows;
## without one, the level is set and stays.
static func _paint_water(terrain: TtwTerrain, world: Vector2, radius_px: float, amount: float, water: TtwWater) -> void:
	var tile_px := TtwTerrain.tile_px()
	var center := world / tile_px
	var r := maxf(radius_px / tile_px, 0.5)
	for y in range(floori(center.y - r), ceili(center.y + r) + 1):
		for x in range(floori(center.x - r), ceili(center.x + r) + 1):
			var tile := Vector2i(x, y)
			if not terrain.has_tile(tile):
				continue
			var d := (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(center) / r
			if d < 1.0:
				var i := terrain.tile_index(tile)
				if water != null:
					water.fill_to(tile, amount)
				else:
					terrain.water[i] = amount if amount > terrain.NO_WATER else terrain.NO_WATER
	if water != null:
		water.publish(Rect2i(Vector2i((center - Vector2(r, r)).floor()) - Vector2i.ONE, Vector2i(ceili(r * 2) + 3, ceili(r * 2) + 3)))
	terrain.water_dirty = true
