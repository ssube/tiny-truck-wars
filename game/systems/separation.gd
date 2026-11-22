class_name TtwSeparationSystem extends System
## Keeps ground vehicles out of each other. Each is a circle (the radius the
## obstacle push uses: half its gauge and a tread); every tick the vehicles
## are put in a grid of CELL_PX cells, and each overlapping pair is pushed
## apart along the line between them, each by its share. A vehicle that
## cannot move by itself (stuck, a wreck, out of fuel) holds its ground: the
## other one goes round it. A wrecker and what it tows or winches are on one
## rope and left be. Aircraft are over all of it.
##
## Runs after the drive and the tow and before the obstacle push, so a
## vehicle is never shoved into a tree or a wall.

## Grid cell: wider than any two radii, so a pair is always in neighbouring cells.
const CELL_PX := 32.0
## Added to a cell's x and y so both are positive in a sorted number.
const CELL_BIAS := 32768

var session: KitSession
## One row per vehicle with a body in the tree, in the view's order: looked
## up when the view changes, not every tick.
var _entities: Array[Entity] = []
var _bodies: Array[Node2D] = []
var _radii: PackedFloat32Array = []
var _count: int = 0
## The world's version when the view was last looked at, and whether every
## vehicle in it had its body (if not, the rows are made again each tick).
var _types: Array = [TtwVehicle, KitBody]
var _version: int = -1
var _whole: bool = false
## This tick: where each row is (kept as they are pushed), every row's cell
## and index as one sorted number, and whether it holds its ground (0 not
## asked yet, 1 it can be moved, 2 it holds).
var _at: PackedVector2Array = []
var _cells: PackedInt64Array = []
var _fixed: PackedByteArray = []
var _fixed_asked: bool = false
## Who touched whom this tick (entity -> Array of entities).
var _touching: Dictionary = {}

## The map's entity: one call a tick (it needs every vehicle at once).
func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(_matches: Array[Entity], _components: Array, _delta: float) -> void:
	if not _touching.is_empty():
		_touching.clear()
	_gather()
	var count := _count
	if count < 2:
		return
	var at := _at
	var cells := _cells
	var radii := _radii
	for i in count:
		# Its cell now (it may have been pushed), against the cells the others
		# were in when gathered: a row of three cells is one run of `cells`.
		var here := at[i]
		var west := floori(here.x / CELL_PX) + CELL_BIAS - 1
		var row := floori(here.y / CELL_PX) + CELL_BIAS - 1
		for _dy in 3:
			var from := (row << 32) | (west << 16)
			var to := from + (3 << 16)
			var t := cells.bsearch(from)
			while t < count:
				var cell := cells[t]
				if cell >= to:
					break
				var j := cell & 0xFFFF
				if j > i:
					var reach := radii[i] + radii[j]
					var gap := at[j] - at[i]
					var d2 := gap.length_squared()
					if d2 < reach * reach:
						_part(i, j, reach, gap, d2)
				t += 1
			row += 1

## The radius a vehicle keeps clear around it (px).
static func radius_of(v: TtwVehicle) -> float:
	return v.gauge_px * 0.5 + v.contact_width_px * 0.5

## Reads where every vehicle is and sorts them by cell.
func _gather() -> void:
	var version := session.world.cache_version
	if version != _version or not _whole:
		var view := session.view(_types)
		if not _whole or view != _entities:
			_rows(view)
		_version = version
	var count := _count
	var bodies := _bodies
	var at := _at
	var cells := _cells
	for k in count:
		var body := bodies[k]
		if not is_instance_valid(body) or not body.is_inside_tree():
			# Its body went with the entity still here: the rows without it.
			_whole = false
			_gather()
			return
		var here := body.position
		at[k] = here
		cells[k] = ((floori(here.y / CELL_PX) + CELL_BIAS) << 32) | ((floori(here.x / CELL_PX) + CELL_BIAS) << 16) | k
	cells.sort()
	if _fixed_asked:
		_fixed.fill(0)
		_fixed_asked = false

## Makes the rows again from the view.
func _rows(view: Array) -> void:
	_entities.clear()
	_bodies.clear()
	_radii.clear()
	_whole = true
	for entity: Entity in view:
		var body := (entity.get_component(KitBody) as KitBody).node
		if not is_instance_valid(body) or not body.is_inside_tree():
			_whole = false
			continue
		_entities.append(entity)
		_bodies.append(body)
		_radii.append(radius_of(entity.get_component(TtwVehicle)))
	_count = _bodies.size()
	_at.resize(_count)
	_cells.resize(_count)
	_fixed.resize(_count)
	_fixed.fill(0)

## Whether row `k` cannot move by itself; asked once a tick, and only of one
## that overlaps another.
func _holds(k: int) -> bool:
	var state := _fixed[k]
	if state == 0:
		var entity := _entities[k]
		state = 2 if entity.has_component(TtwStuck) or TtwWinchSystem.immobile(entity) else 1
		_fixed[k] = state
		_fixed_asked = true
	return state == 2

## Parts rows `i` and `j`, which overlap: `gap` from i to j, `d2` its length
## squared, `reach` their two radii.
func _part(i: int, j: int, reach: float, gap: Vector2, d2: float) -> void:
	var fixed_a := _holds(i)
	var fixed_b := _holds(j)
	if fixed_a and fixed_b or _roped(_entities[i], _entities[j]) or _roped(_entities[j], _entities[i]):
		return
	_touch(_entities[i], _entities[j])
	_touch(_entities[j], _entities[i])
	var d := sqrt(d2)
	# Exactly on top of each other: part them along x, the lower index west.
	var away := gap / d if d > 0.0001 else Vector2.RIGHT
	var overlap := reach - d
	if fixed_a:
		_at[j] += away * overlap
		_bodies[j].position = _at[j]
	elif fixed_b:
		_at[i] -= away * overlap
		_bodies[i].position = _at[i]
	else:
		_at[i] -= away * overlap * 0.5
		_bodies[i].position = _at[i]
		_at[j] += away * overlap * 0.5
		_bodies[j].position = _at[j]

func _roped(wrecker: Entity, load: Entity) -> bool:
	return wrecker.has_component(TtwWinch) and (session.linked(wrecker, TtwTowing) == load or session.linked(wrecker, TtwWinching) == load)

func _touch(a: Entity, b: Entity) -> void:
	if _touching.has(a):
		(_touching[a] as Array).append(b)
	else:
		_touching[a] = [b]

## Whether `entity`, last tick, was pressed against a vehicle standing
## (no move order) nearer `target` than it is: as near as it will get.
func blocked_short(entity: Entity, target: Vector2) -> bool:
	var others: Variant = _touching.get(entity)
	if others == null:
		return false
	var body := session.body_of(entity)
	if body == null:
		return false
	var mine := body.position.distance_to(target)
	for other: Entity in others:
		var there := session.body_of(other)
		if there != null and not other.has_component(TtwMoveOrder) and there.position.distance_to(target) < mine:
			return true
	return false
