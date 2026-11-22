class_name TtwWater extends RefCounted
## Shallow water on the tile grid: a virtual-pipe model. Each tile holds a
## depth over its floor (elevation plus the mean relief of its cells); a pipe
## to each neighbour carries flux driven by the difference in surface height.
## Volume is conserved: water only moves between tiles, except at sources
## (which keep their tiles up to a level) and sinks (which drain to one).
##
## Only the wet area is stepped (its bounding rect, grown by a tile), so dry
## land costs nothing. A tile's floors are worked out again only when its
## cells changed (TtwTerrain.floors_stale) and the water is about to read
## them, so ground churned far from any water costs it nothing either. After each step the terrain's `water` (the level the
## shader and gameplay read) and `flow` (the current) are refreshed there, and
## newly flooded ground is soaked.
##
## A tile's water is a volume (px of depth averaged over the tile). Its level
## comes from how its cells lie: a little water fills only the lowest cells
## (ruts, a crater's floor), and once it is over every cell the level is the
## mean floor plus the volume. So puddles form in ruts narrower than a tile.
##
## Units: px of depth, seconds. Fluxes are depth per second through a face.

## Pipe gain (1/s²): how hard a 1 px difference in level pushes. Stable while
## STEP_SECONDS × GAIN stays well under 1.
const GAIN := 6.0
## Flux lost per second (keeps a pool from sloshing for ever).
const DAMPING := 0.8
## Simulated seconds per step; TtwWaterSystem steps every STEP_TICKS ticks.
const STEP_TICKS := 2
## Volume (px averaged over the tile) under which a tile counts as dry.
const DRY := 0.002
## The level stored for a dry tile beside water: just under its lowest cell,
## so the level fades smoothly to the shore between the two tiles and never
## shows water in that dry tile's own ruts.
const SHORE_DROP := 0.5
## How far (px) above the water's level the ground around it is soaked.
const SOAK_EDGE := 0.6
## Ground takes water in: up to SOIL_HOLDS (px over the tile) at INFILTRATION
## px per second times its material's TtwMaterials.INFILTRATES (none for mud,
## which is full already, or pavement). So a little water poured on dry
## grass makes a patch of mud rather than a film spreading over the whole
## map. Ground that starts under water, or is filled by hand, is full.
const SOIL_HOLDS := 0.4
const INFILTRATION := 0.5
## A film this thin (px over the tile) is held by the ground's roughness: it
## does not flow on. Volume is kept; it soaks in or stays.
const FILM_PX := 0.05

var terrain: TtwTerrain
var depth: PackedFloat32Array
## Outflow through the west, east, north and south faces.
var flux_w: PackedFloat32Array
var flux_e: PackedFloat32Array
var flux_n: PackedFloat32Array
var flux_s: PackedFloat32Array
## Mean and lowest relief of each tile's cells (px), kept as cells change.
var floor_mean: PackedFloat32Array
var floor_min: PackedFloat32Array
var floor_max: PackedFloat32Array
## Each tile's cell reliefs in rising order, made when first needed.
var _sorted: Dictionary = {}
## Beside each: the running sum of those cells (one more entry than cells).
var _sums: Dictionary = {}
const _NONE: PackedFloat32Array = []
## Sources and sinks are the terrain's (TtwTerrain.water_sources/_sinks).
## Volume (px of depth × tiles) sources have added and sinks taken, ever.
var added: float = 0.0
var drained: float = 0.0
## Volume poured in (water tankers, buckets) and drawn out (pumps, buckets).
var poured: float = 0.0
var drawn: float = 0.0
## What each tile's ground has taken in (px), and the volume taken in, ever.
var absorbed: PackedFloat32Array
var infiltrated: float = 0.0
## Oil floating on each tile's water (volume), carried by the same flux as
## the water, so it runs downstream and is kept. When a tile dries, its slick
## settles back onto the ground as oil (TtwTerrain.oil).
var slick: PackedFloat32Array
## Slick volume in the water, and what sinks have carried off.
var slick_total: float = 0.0
var slick_drained: float = 0.0
## The slick changed since the view last uploaded it.
var slick_dirty: bool = false
## Tiles that hold any water, grown by one when stepping; empty when all is
## dry. Every tile outside it has no water and no flux.
var wet_rect: Rect2i = Rect2i()
var _soaked: PackedByteArray
## Each stepped tile's surface (elevation plus level), worked out once per
## step. Doubles, so the fluxes come out as they would from level_of().
var _surface: PackedFloat64Array

func _init(owner: TtwTerrain) -> void:
	terrain = owner
	var count := owner.size_tiles.x * owner.size_tiles.y
	depth.resize(count)
	slick.resize(count)
	flux_w.resize(count)
	flux_e.resize(count)
	flux_n.resize(count)
	flux_s.resize(count)
	floor_mean.resize(count)
	floor_min.resize(count)
	floor_max.resize(count)
	_soaked.resize(count)
	_surface.resize(count)
	absorbed.resize(count)
	refresh_floors(Rect2i(Vector2i.ZERO, owner.size_tiles))
	adopt_levels()

## Takes the terrain's authored water levels (TtwTerrain.water) as depths.
func adopt_levels() -> void:
	for i in depth.size():
		if terrain.water[i] > TtwTerrain.NO_WATER:
			depth[i] = volume_at(i, terrain.water[i])
			absorbed[i] = SOIL_HOLDS
	find_wet()

## Brings the floors of `tiles` up to date with their cells: only the tiles
## flagged since they were last read (TtwTerrain.floors_stale) are redone.
func freshen(tiles: Rect2i) -> void:
	tiles = tiles.intersection(Rect2i(Vector2i.ZERO, terrain.size_tiles))
	var stale := terrain.floors_stale
	var w := terrain.size_tiles.x
	for ty in range(tiles.position.y, tiles.end.y):
		for i in range(ty * w + tiles.position.x, ty * w + tiles.end.x):
			if stale[i] != 0:
				_refresh_tile(i)

## Recomputes the floors of `tiles` from their cells, stale or not.
func refresh_floors(tiles: Rect2i) -> void:
	tiles = tiles.intersection(Rect2i(Vector2i.ZERO, terrain.size_tiles))
	var w := terrain.size_tiles.x
	for ty in range(tiles.position.y, tiles.end.y):
		for i in range(ty * w + tiles.position.x, ty * w + tiles.end.x):
			_refresh_tile(i)

## One tile's floors from its cells; it is no longer stale.
func _refresh_tile(i: int) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	var width := terrain.size_cells.x
	var deform := terrain.deform
	var loose := terrain.loose
	var tx := i % terrain.size_tiles.x
	var ty := i / terrain.size_tiles.x
	var total := 0.0
	var lowest := INF
	var highest := -INF
	var first := ty * n * width + tx * n
	for row in range(first, first + n * width, width):
		for c in range(row, row + n):
			var r := deform[c] + loose[c]
			total += r
			if r < lowest:
				lowest = r
			if r > highest:
				highest = r
	floor_mean[i] = total / (n * n)
	floor_min[i] = lowest
	floor_max[i] = highest
	_sorted.erase(i)
	terrain.floors_stale[i] = 0

## The tile's water surface, absolute: its elevation plus level_of().
func surface(i: int) -> float:
	return terrain.elevation[i] + level_of(i)


## The level (relief px) a tile's water reaches: where an empty tile's lowest
## cell is, rising through its cells as they fill.
func level_of(i: int) -> float:
	if terrain.floors_stale[i] != 0:
		_refresh_tile(i)
	return _level(i)

## level_of() for a tile whose floors are fresh (freshen() covers it).
func _level(i: int) -> float:
	var v := depth[i]
	if v <= 0.0:
		return floor_min[i]
	if v >= floor_max[i] - floor_mean[i]:
		return floor_mean[i] + v
	# The water covers the k lowest cells: the fewest whose level, (volume
	# + their sum) / k, does not reach the next cell up. Covering one more
	# cell never raises the level past the cell after it, so k is found by
	# halving rather than by trying each in turn.
	var cells := _cells_sorted(i)
	var sums: PackedFloat64Array = _sums[i]
	var count := cells.size()
	var volume := v * count
	var low := 1
	var high := count
	while low < high:
		var k := (low + high) >> 1
		if (volume + sums[k]) / k <= cells[k]:
			high = k
		else:
			low = k + 1
	return (volume + sums[low]) / low

## The volume over a tile when its water stands at `level` (relief px).
## Each tile's depth (volume per cell area, px) as an image, for the view.
func depth_image() -> Image:
	return Image.create_from_data(terrain.size_tiles.x, terrain.size_tiles.y, false, Image.FORMAT_RF, depth.to_byte_array())

func volume_at(i: int, level: float) -> float:
	if terrain.floors_stale[i] != 0:
		_refresh_tile(i)
	return _volume(i, level)

## volume_at() for a tile whose floors are fresh.
func _volume(i: int, level: float) -> float:
	if level <= floor_min[i]:
		return 0.0
	if level >= floor_max[i]:
		return level - floor_mean[i]
	var cells := _cells_sorted(i)
	var total := 0.0
	for r in cells:
		if r >= level:
			break
		total += level - r
	return total / cells.size()

func _cells_sorted(i: int) -> PackedFloat32Array:
	var cells: PackedFloat32Array = _sorted.get(i, _NONE)
	if cells.is_empty():
		var n := TtwTerrain.CELLS_PER_TILE
		var width := terrain.size_cells.x
		var deform := terrain.deform
		var loose := terrain.loose
		var first := (i / terrain.size_tiles.x) * n * width + (i % terrain.size_tiles.x) * n
		cells = PackedFloat32Array()
		for row in range(first, first + n * width, width):
			for c in range(row, row + n):
				cells.append(deform[c] + loose[c])
		cells.sort()
		# sums[k]: the k lowest cells added up, lowest first.
		var sums := PackedFloat64Array()
		sums.resize(cells.size() + 1)
		var sum := 0.0
		for k in cells.size():
			sum += cells[k]
			sums[k + 1] = sum
		_sorted[i] = cells
		_sums[i] = sums
	return cells

## Whether a tile has water over it (the sim's depth, not the drawn level).
func is_wet(tile_index: int) -> bool:
	return depth[tile_index] > DRY

## Sets a tile's water to reach `level` (relief units, like terrain.water):
## the depth over its floor, or none.
func fill_to(tile: Vector2i, level: float) -> void:
	if not terrain.has_tile(tile):
		return
	var i := terrain.tile_index(tile)
	depth[i] = volume_at(i, level)
	absorbed[i] = SOIL_HOLDS
	touch(Rect2i(tile, Vector2i.ONE))

## Marks tiles as possibly wet, so the next step looks at them.
func touch(tiles: Rect2i) -> void:
	wet_rect = tiles if wet_rect.size == Vector2i.ZERO else wet_rect.merge(tiles)

## Finds the wet area from scratch (after loading a map).
func find_wet() -> void:
	wet_rect = Rect2i()
	for y in terrain.size_tiles.y:
		for x in terrain.size_tiles.x:
			if depth[y * terrain.size_tiles.x + x] > DRY:
				touch(Rect2i(x, y, 1, 1))
	for s in terrain.water_sources:
		touch(s.rect)
	publish(Rect2i(Vector2i.ZERO, terrain.size_tiles))

func total_volume() -> float:
	var total := 0.0
	for d in depth:
		total += d
	return total

## One step of `dt` seconds over the wet area.
func step(dt: float) -> void:
	if wet_rect.size == Vector2i.ZERO:
		return
	var w := terrain.size_tiles.x
	var h := terrain.size_tiles.y
	var area := wet_rect.grow(1).intersection(Rect2i(Vector2i.ZERO, terrain.size_tiles))
	var x0 := area.position.x
	var x1 := area.end.x
	var y0 := area.position.y
	var y1 := area.end.y
	var keep := 1.0 - DAMPING * dt
	var push := dt * GAIN
	# Local names for the arrays: they share the members' storage, and a
	# local is read and written two to three times faster than a member.
	var stale := terrain.floors_stale
	var elevation := terrain.elevation
	var levels := _surface
	var d_ := depth
	var f_w := flux_w
	var f_e := flux_e
	var f_n := flux_n
	var f_s := flux_s
	var f_min := floor_min
	var f_mean := floor_mean
	var f_max := floor_max
	# Each tile's surface once (a wet tile reads its four neighbours'), with
	# its floors brought up to date first.
	for y in range(y0, y1):
		for i in range(y * w + x0, y * w + x1):
			if stale[i] != 0:
				_refresh_tile(i)
			var v := d_[i]
			if v <= 0.0:
				levels[i] = elevation[i] + f_min[i]
			elif v >= f_max[i] - f_mean[i]:
				levels[i] = elevation[i] + (f_mean[i] + v)
			else:
				levels[i] = elevation[i] + _level(i)
	# Fluxes from the difference in surface height.
	for y in range(y0, y1):
		var i := y * w + x0 - 1
		for x in range(x0, x1):
			i += 1
			var d := d_[i]
			if d <= FILM_PX:
				f_w[i] = 0.0
				f_e[i] = 0.0
				f_n[i] = 0.0
				f_s[i] = 0.0
				continue
			var here := levels[i]
			var fw := 0.0
			var fe := 0.0
			var fn := 0.0
			var fs := 0.0
			if x > 0:
				fw = maxf(0.0, f_w[i] * keep + push * (here - levels[i - 1]))
			if x < w - 1:
				fe = maxf(0.0, f_e[i] * keep + push * (here - levels[i + 1]))
			if y > 0:
				fn = maxf(0.0, f_n[i] * keep + push * (here - levels[i - w]))
			if y < h - 1:
				fs = maxf(0.0, f_s[i] * keep + push * (here - levels[i + w]))
			var out := (fw + fe + fn + fs) * dt
			if out > d:
				var k := d / out
				fw *= k
				fe *= k
				fn *= k
				fs *= k
			f_w[i] = fw
			f_e[i] = fe
			f_n[i] = fn
			f_s[i] = fs
	if slick_total > 0.0:
		_carry_slick(x0, x1, y0, y1, dt)
	# Depths from what flows in and out. The stepped area is every tile with
	# any water: a tile outside it has none and so no flux, and nothing flows
	# in from beyond it.
	var found_x0 := w
	var found_x1 := -1
	var found_y0 := h
	var found_y1 := -1
	var soil := absorbed
	var surface := terrain.surface
	var take_in := INFILTRATION * dt
	for y in range(y0, y1):
		var i := y * w + x0 - 1
		for x in range(x0, x1):
			i += 1
			var inflow := 0.0
			if x > 0: inflow += f_e[i - 1]
			if x < w - 1: inflow += f_w[i + 1]
			if y > 0: inflow += f_s[i - w]
			if y < h - 1: inflow += f_n[i + w]
			var outflow := f_w[i] + f_e[i] + f_n[i] + f_s[i]
			var d := d_[i] + dt * (inflow - outflow)
			# The ground drinks what it can hold.
			if d > 0.0 and soil[i] < SOIL_HOLDS and TtwMaterials.INFILTRATES[surface[i]] > 0.0:
				var drunk := minf(d, minf(take_in * TtwMaterials.INFILTRATES[surface[i]], SOIL_HOLDS - soil[i]))
				soil[i] += drunk
				infiltrated += drunk
				d -= drunk
			# A film too thin to matter is gone (so the area can shrink).
			if d > 1e-6:
				d_[i] = d
				if x < found_x0: found_x0 = x
				if x > found_x1: found_x1 = x
				if y < found_y0: found_y0 = y
				found_y1 = y
			else:
				d_[i] = 0.0
				if slick_total > 0.0 and slick[i] > 0.0:
					_settle_slick(i)
	var found := Rect2i(found_x0, found_y0, found_x1 - found_x0 + 1, found_y1 - found_y0 + 1) if found_x1 >= 0 else Rect2i()
	_apply_sources(found)
	wet_rect = found
	for s in terrain.water_sources:
		touch(s.rect)
	_publish(area)

## Moves each tile's slick out through its faces in the share its water does.
func _carry_slick(x0: int, x1: int, y0: int, y1: int, dt: float) -> void:
	var w := terrain.size_tiles.x
	var next := slick.duplicate()
	var d_ := depth
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * w + x
			var oil := slick[i]
			if oil <= 0.0 or d_[i] <= 0.0:
				continue
			var share := dt / d_[i]
			var ow := oil * flux_w[i] * share
			var oe := oil * flux_e[i] * share
			var on := oil * flux_n[i] * share
			var os := oil * flux_s[i] * share
			next[i] -= ow + oe + on + os
			if ow > 0.0: next[i - 1] += ow
			if oe > 0.0: next[i + 1] += oe
			if on > 0.0: next[i - w] += on
			if os > 0.0: next[i + w] += os
	slick = next
	slick_dirty = true

## A tile has dried: its slick lies on its cells as oil.
func _settle_slick(i: int) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	var tile := Vector2i(i % terrain.size_tiles.x, i / terrain.size_tiles.x)
	var each := slick[i] / (n * n)
	for cy in range(tile.y * n, tile.y * n + n):
		for cx in range(tile.x * n, tile.x * n + n):
			terrain.oil[cy * terrain.size_cells.x + cx] += each
	slick_total -= slick[i]
	slick[i] = 0.0
	terrain.mark_cells(Rect2i(tile * n, Vector2i(n, n)))

## Puts oil on a tile's water (it floats).
func add_slick(i: int, amount: float) -> void:
	slick[i] += amount
	slick_total += amount
	slick_dirty = true

## Slick volume across the map (for the books).
func slick_volume() -> float:
	var total := 0.0
	for v in slick:
		total += v
	return total

## The slick as an RF image, one texel per tile.
func slick_image() -> Image:
	return Image.create_from_data(terrain.size_tiles.x, terrain.size_tiles.y, false, Image.FORMAT_RF, slick.to_byte_array())

func _apply_sources(_found: Rect2i) -> void:
	for s in terrain.water_sources:
		_hold(s, true)
	for s in terrain.water_sinks:
		_hold(s, false)

func _hold(spec: Dictionary, raise: bool) -> void:
	var rect: Rect2i = Rect2i(spec.rect).intersection(Rect2i(Vector2i.ZERO, terrain.size_tiles))
	var level: float = spec.level
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * terrain.size_tiles.x + x
			var wanted := volume_at(i, level - terrain.elevation[i])
			if raise and depth[i] < wanted:
				added += wanted - depth[i]
				depth[i] = wanted
			elif not raise and depth[i] > wanted:
				if slick[i] > 0.0:
					var gone := slick[i] * (1.0 - wanted / depth[i])
					slick[i] -= gone
					slick_total -= gone
					slick_drained += gone
				drained += depth[i] - wanted
				depth[i] = wanted

## Writes the level and current the shader and gameplay read over `area`,
## and soaks ground that has just gone under.
func publish(area: Rect2i) -> void:
	freshen(area)
	_publish(area)

func _publish(area: Rect2i) -> void:
	var w := terrain.size_tiles.x
	var h := terrain.size_tiles.y
	area = area.intersection(Rect2i(Vector2i.ZERO, terrain.size_tiles))
	var tile_px := terrain.tile_size_px
	var level := terrain.water
	var flow := terrain.flow
	var d_ := depth
	var f_w := flux_w
	var f_e := flux_e
	var f_n := flux_n
	var f_s := flux_s
	var f_min := floor_min
	var f_mean := floor_mean
	var f_max := floor_max
	var soaked := _soaked
	for y in range(area.position.y, area.end.y):
		var i := y * w + area.position.x - 1
		for x in range(area.position.x, area.end.x):
			i += 1
			var d := d_[i]
			if d > DRY:
				level[i] = f_mean[i] + d if d >= f_max[i] - f_mean[i] else _level(i)
				# Net flux through the tile, as a velocity (px/s).
				var into_e := (f_e[i - 1] if x > 0 else 0.0) - f_w[i] + f_e[i] - (f_w[i + 1] if x < w - 1 else 0.0)
				var into_s := (f_s[i - w] if y > 0 else 0.0) - f_n[i] + f_s[i] - (f_n[i + w] if y < h - 1 else 0.0)
				flow[i] = Vector2(into_e, into_s) * 0.5 * tile_px / maxf(d, 0.5)
				if soaked[i] == 0:
					soaked[i] = 1
					_soak(Vector2i(x, y))
			else:
				flow[i] = Vector2.ZERO
				if soaked[i] == 1:
					soaked[i] = 0
					_drain(Vector2i(x, y))
				# Beside water, a level just under this tile's lowest cell.
				if (x > 0 and d_[i - 1] > DRY) or (x < w - 1 and d_[i + 1] > DRY) or (y > 0 and d_[i - w] > DRY) or (y < h - 1 and d_[i + w] > DRY):
					level[i] = f_min[i] - SHORE_DROP
				else:
					level[i] = TtwTerrain.NO_WATER
	terrain.water_dirty = true

## The water has gone from a tile: its wet cells start drying (TtwSettleSystem).
func _drain(tile: Vector2i) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	var width := terrain.size_cells.x
	for cy in range(tile.y * n, tile.y * n + n):
		for cx in range(tile.x * n, tile.x * n + n):
			var i := cy * width + cx
			if terrain.wet[i] > 0.0:
				terrain.queue_settle(i)

## Soaks the cells the water covers (and a thin wet edge above it).
func _soak(tile: Vector2i) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	var width := terrain.size_cells.x
	var level := terrain.water[terrain.tile_index(tile)] + SOAK_EDGE
	for cy in range(tile.y * n, tile.y * n + n):
		for cx in range(tile.x * n, tile.x * n + n):
			var i := cy * width + cx
			if terrain.deform[i] + terrain.loose[i] < level:
				terrain.wet[i] = 1.0
				terrain.queue_settle(i)
	terrain.mark_cells(Rect2i(tile * n, Vector2i(n, n)))

## Pours `volume` (px of depth × tiles) over a disc of `radius_px` at `at`,
## more toward the middle, and soaks the ground under it (making mud on
## purpose). Returns the volume that landed on the map.
func pour(at: Vector2, volume: float, radius_px: float) -> float:
	var tile_px := TtwTerrain.tile_px()
	var center := at / tile_px
	var r := maxf(radius_px / tile_px, 0.5)
	var tiles: Array[Vector2i] = []
	var weights: PackedFloat32Array = []
	var total := 0.0
	for y in range(floori(center.y - r), ceili(center.y + r) + 1):
		for x in range(floori(center.x - r), ceili(center.x + r) + 1):
			var tile := Vector2i(x, y)
			if not terrain.has_tile(tile):
				continue
			var d := (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(center) / r
			if d < 1.0:
				tiles.append(tile)
				weights.append(1.0 - d * d)
				total += 1.0 - d * d
	if tiles.is_empty() or volume <= 0.0:
		return 0.0
	for k in tiles.size():
		var i := terrain.tile_index(tiles[k])
		depth[i] += volume * weights[k] / total
		touch(Rect2i(tiles[k], Vector2i.ONE))
	poured += volume
	# Every cell under the disc is soaked through.
	var cell_px := TtwTerrain.cell_px()
	var lo := terrain.cell_of(at - Vector2(radius_px, radius_px)).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var hi := terrain.cell_of(at + Vector2(radius_px, radius_px)).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var wet := terrain.wet
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if ((Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px).distance_to(at) <= radius_px:
				var i := y * terrain.size_cells.x + x
				wet[i] = 1.0
				terrain.queue_settle(i)
	terrain.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE))
	return volume

## Draws up to `volume` from the water nearest `at` (within `radius_px`),
## deepest first. Returns what it got.
func draw(at: Vector2, volume: float, radius_px: float = 24.0) -> float:
	var tile_px := TtwTerrain.tile_px()
	var center := at / tile_px
	var r := maxf(radius_px / tile_px, 0.5)
	var found: Array[int] = []
	for y in range(floori(center.y - r), ceili(center.y + r) + 1):
		for x in range(floori(center.x - r), ceili(center.x + r) + 1):
			var tile := Vector2i(x, y)
			if terrain.has_tile(tile) and (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(center) <= r and depth[terrain.tile_index(tile)] > DRY:
				found.append(terrain.tile_index(tile))
	found.sort_custom(func(a: int, b: int) -> bool: return depth[a] > depth[b])
	var got := 0.0
	for i in found:
		var take := minf(depth[i], volume - got)
		depth[i] -= take
		got += take
		touch(Rect2i(Vector2i(i % terrain.size_tiles.x, i / terrain.size_tiles.x), Vector2i.ONE))
		if got >= volume:
			break
	drawn += got
	return got

## Adds `volume` to one tile's water (snowmelt running in). Counted as poured.
func add_volume(i: int, volume: float) -> void:
	if volume <= 0.0:
		return
	depth[i] += volume
	poured += volume
	touch(Rect2i(Vector2i(i % terrain.size_tiles.x, i / terrain.size_tiles.x), Vector2i.ONE))
