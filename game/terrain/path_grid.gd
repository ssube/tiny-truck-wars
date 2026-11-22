class_name TtwPathGrid extends RefCounted
## Where ground vehicles can go and what it costs, one weight per tile, read
## from every layer the drive reads: material and wear, ruts (between crossing
## and following them), loose mud, wetness, water depth, snow (deep drags,
## packed slips), oil, the grade; and obstacles (trees, logs, buildings).
## Water at a vehicle's engine intake, ground that holds more than a truck's
## traction, and obstacles are walls; ground near the stuck limit costs much
## more, so routes go around bogs they could just about cross.
##
## Kept on the map's TtwGround (`paths`) and searched with AStarGrid2D. A tile
## is weighed again when the terrain queues it (ruts, craters, settling,
## material and elevation changes: TtwTerrain.path_queue) and by a slow sweep
## over the whole map for what changes everywhere at once (water levels,
## drying, snowfall and thaw).

## Cells sampled in each tile (of 8×8).
const SAMPLES: Array[Vector2i] = [Vector2i(2, 2), Vector2i(6, 2), Vector2i(2, 6), Vector2i(6, 6)]
## Water deeper than this costs more by WATER_COST per px; at FLOOD_PX it is a wall.
const WADE_PX := 4.0
const FLOOD_PX := 8.0
const WATER_COST := 0.5
## Routes prefer good ground strongly: a tile costs its resistance to this
## power (pavement 1, gravel 1.3, grass 1.8, sand 2.6, mud 4.8), so a road
## round a field beats a straight line through its mud.
const SURFACE_POWER := 2.0
## Water any deeper than WET_PX costs WATER_STEP more on top (so routes stay
## out of fords and puddles they could drive through when there is a dry way).
const WET_PX := 0.5
const WATER_STEP := 6.0
## Cost per unit of grade, either way (climbing is slow, descending wears).
const GRADE_COST := 1.0
## The traction a route is planned for (a truck's), the share of it past which
## ground is a risk, and what a risky tile costs times its resistance.
const TRACTION := 6.0
const RISK_SHARE := 0.75
const RISK_COST := 6.0
## How far (px) an obstacle's shape is grown when deciding which tile centres
## it blocks: the widest ground vehicle's radius (a tank's, 14.5 px: half its
## gauge and a tread), so a route along open tile centres clears an obstacle
## for every vehicle, like a navigation agent's radius.
const OBSTACLE_GROW := 15.0
## Vehicles standing about (wrecks, stuck or stranded ones, idle ones) add
## CROWD_COST to each tile they cover, with a vehicle's clearance: routes go
## round a jam on the road rather than queue into it. Put down by
## TtwCrowdSystem every few ticks (the grid lags a little: fog of war).
const CROWD_COST := 30.0
## Tiles weighed per step: from the terrain's queue, and by the sweep.
const QUEUE_BUDGET := 64
const SWEEP_BUDGET := 16

var terrain: TtwTerrain
var astar := AStarGrid2D.new()
## Each tile's weight (INF for a wall, before obstacles).
var cost: PackedFloat32Array
## How many obstacles block each tile.
var blocked: PackedInt32Array
## How many standing vehicles cover each tile.
var crowd: PackedInt32Array
## Tiles each obstacle blocks (instance id -> PackedInt32Array).
var _blocks: Dictionary = {}
var _sweep: int = 0

func _init(value: TtwTerrain) -> void:
	terrain = value
	var count := terrain.size_tiles.x * terrain.size_tiles.y
	cost.resize(count)
	blocked.resize(count)
	crowd.resize(count)
	astar.region = Rect2i(Vector2i.ZERO, terrain.size_tiles)
	astar.cell_size = Vector2(terrain.tile_size_px, terrain.tile_size_px)
	astar.offset = astar.cell_size * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	# Everything starts weighed; the terrain's queue so far is covered.
	for i in count:
		weigh(i)
	terrain.path_stale.fill(0)
	terrain.path_queue.clear()

## The cost of driving over one tile (1 = dry level road), or INF where a
## ground vehicle cannot go.
func tile_cost(tile: Vector2i) -> float:
	var t := terrain
	var ti := t.tile_index(tile)
	var level := t.water[ti]
	var snowy := t.snow_level > 0.0 or t.snow_base[ti] > 0.0
	var origin := tile * TtwTerrain.CELLS_PER_TILE
	var total := 0.0
	var deepest := 0.0
	for s in SAMPLES:
		var cell := origin + s
		var ci := t.cell_index(cell)
		var depth := maxf(0.0, level - (t.deform[ci] + t.loose[ci]))
		if depth >= FLOOD_PX:
			return INF
		deepest = maxf(deepest, depth)
		# Halfway between following ruts and crossing them.
		var r := TtwDriveSystem.resistance_in(t, ci, t.track_angle[ci] + PI / 4.0, depth)
		if t.oil[ci] > 0.0:
			r /= maxf(0.2, TtwOil.grip(t.effective_material(cell), t.oil[ci]))
		if snowy:
			var snow := TtwSnow.depth_at(t, ci)
			if snow > 0.0:
				if TtwSnow.is_packed(t, ci):
					r /= TtwDriveSystem.PACKED_SNOW_GRIP
				else:
					r *= 1.0 + snow * TtwDriveSystem.SNOW_DRAG
		if depth > WADE_PX:
			r *= 1.0 + (depth - WADE_PX) * WATER_COST
		total += r
	var r := total / SAMPLES.size()
	r *= 1.0 + t.elevation_gradient((Vector2(tile) + Vector2(0.5, 0.5)) * t.tile_size_px).length() * GRADE_COST
	if r > TRACTION:
		return INF
	var cost := pow(r, SURFACE_POWER)
	if r > TRACTION * RISK_SHARE:
		cost *= RISK_COST
	if deepest > WET_PX:
		cost += WATER_STEP
	return cost

## Weighs one tile (by index) again.
func weigh(i: int) -> void:
	var tile := Vector2i(i % terrain.size_tiles.x, i / terrain.size_tiles.x)
	var c := tile_cost(tile)
	cost[i] = c
	var wall := is_inf(c) or blocked[i] > 0
	astar.set_point_solid(tile, wall)
	if not is_inf(c):
		astar.set_point_weight_scale(tile, c + crowd[i] * CROWD_COST)

## Weighs what the terrain queued (up to QUEUE_BUDGET) and the next stretch of
## the sweep. Returns how many tiles it weighed.
func step() -> int:
	var queue := terrain.path_queue
	var take := mini(queue.size(), QUEUE_BUDGET)
	for k in take:
		var i := queue[k]
		terrain.path_stale[i] = 0
		weigh(i)
	if take > 0:
		terrain.path_queue = queue.slice(take)
	var count := cost.size()
	for k in mini(SWEEP_BUDGET, count):
		weigh(_sweep)
		_sweep = (_sweep + 1) % count
	return take + mini(SWEEP_BUDGET, count)

## Marks the tiles `obstacle` (standing at `at`) blocks, in place of any it
## blocked before under `key` (an instance id). An empty-handed call
## (obstacle null) unblocks.
func place(key: int, obstacle: TtwObstacle, at: Vector2, tiles: Array[Vector2i]) -> void:
	var before: PackedInt32Array = _blocks.get(key, PackedInt32Array())
	var now := PackedInt32Array()
	if obstacle != null:
		for tile in tiles:
			if not terrain.has_tile(tile):
				continue
			var center := (Vector2(tile) + Vector2(0.5, 0.5)) * terrain.tile_size_px
			if TtwObstacles.push_out(center, OBSTACLE_GROW, obstacle, at) != center:
				now.append(terrain.tile_index(tile))
	if before == now:
		return
	for i in before:
		blocked[i] -= 1
		_refresh_wall(i)
	for i in now:
		blocked[i] += 1
		_refresh_wall(i)
	if now.is_empty():
		_blocks.erase(key)
	else:
		_blocks[key] = now

func _refresh_wall(i: int) -> void:
	var tile := Vector2i(i % terrain.size_tiles.x, i / terrain.size_tiles.x)
	var wall := is_inf(cost[i]) or blocked[i] > 0
	astar.set_point_solid(tile, wall)
	if not is_inf(cost[i]):
		astar.set_point_weight_scale(tile, cost[i] + crowd[i] * CROWD_COST)

## Puts down where vehicles stand: `counts` (tile index -> vehicles) in
## place of the last ones; only tiles whose count changed are touched.
func set_crowd(counts: Dictionary) -> void:
	for i in _crowded.keys():
		if not counts.has(i):
			crowd[i] = 0
			_refresh_wall(i)
	for i in counts:
		if crowd[i] != counts[i]:
			crowd[i] = counts[i]
			_refresh_wall(i)
	_crowded = counts

var _crowded: Dictionary = {}

## Whether a ground vehicle can stand on the tile under `at`.
func is_open(at: Vector2) -> bool:
	var tile := terrain.tile_of(at)
	return terrain.has_tile(tile) and not astar.is_point_solid(tile)

## A route for a ground vehicle from `from` to `to` (world px): tile centres
## where it turns, ending at `to` (or, when `to` cannot be reached, as near it
## as the ground allows). Empty when there is nowhere to go.
func find(from: Vector2, to: Vector2) -> PackedVector2Array:
	var limit := terrain.size_tiles - Vector2i.ONE
	var start := _open_near(terrain.tile_of(from).clamp(Vector2i.ZERO, limit))
	var wanted := terrain.tile_of(to).clamp(Vector2i.ZERO, limit)
	var goal := _open_near(wanted)
	if start.x < 0 or goal.x < 0:
		return PackedVector2Array()
	var ids := astar.get_id_path(start, goal, true)
	var out := PackedVector2Array()
	for k in ids.size():
		# Keep only the turns.
		if k > 0 and k < ids.size() - 1 and ids[k] - ids[k - 1] == ids[k + 1] - ids[k]:
			continue
		out.append((Vector2(ids[k]) + Vector2(0.5, 0.5)) * terrain.tile_size_px)
	if not out.is_empty():
		out.remove_at(0)
		if not ids.is_empty() and ids[ids.size() - 1] == wanted:
			if out.is_empty():
				out.append(to)
			else:
				out[out.size() - 1] = to
	return out

## The open tile nearest `tile` (itself if open), searching rings out to 6
## tiles; (-1, -1) if none.
func _open_near(tile: Vector2i) -> Vector2i:
	if not astar.is_point_solid(tile):
		return tile
	for ring in range(1, 7):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var t := tile + Vector2i(x, y)
				if astar.is_in_boundsv(t) and not astar.is_point_solid(t) and Vector2(x, y).length() < best_d:
					best = t
					best_d = Vector2(x, y).length()
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
