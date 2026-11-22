class_name TtwDriveSystem extends System
## Moves ground vehicles over the ground: speed from throttle against the
## resistance under them, the grade along the heading (uphill slower, downhill
## faster) and the water's current (which carries them: against it slower,
## with it faster); fuel burned by effort; wear from water deeper than the
## wading depth, growing faster than the depth; the engine flooded by water
## up to its intake (health to 1%, no restart, no explosion); a crater and a
## wreck when health reaches 0.

signal flooded(entity: Entity)
signal destroyed(entity: Entity)
signal stalled_engine(entity: Entity)
## The ground held it: resistance passed its traction while it tried to drive.
signal got_stuck(entity: Entity)
signal freed(entity: Entity)

## Resistance added per px of rut depth when crossing ruts (driving along
## fresh ruts costs RUT_ALONG of that).
const RUT_CROSS := 0.12
const RUT_ALONG := 0.25
const LOOSE_DRAG := 0.10
## Resistance added per px of loose snow, and the grip left on packed snow.
const SNOW_DRAG := 0.08
const PACKED_SNOW_GRIP := 0.65
const WATER_DRAG := 0.09
## Speed share lost per unit of grade going up, gained going down.
const GRADE_UP := 1.6
const GRADE_DOWN := 0.8
## How much of the current a vehicle is carried by, at and past its wading depth.
const CURRENT_CARRY := 0.6
## Health share a flooded engine leaves.
const FLOODED_HEALTH := 0.01
## Strain starts past these: a grade along the direction of travel, and a
## share of the traction the resistance uses.
const STALL_GRADE := 0.35
const STALL_PULL := 0.8
const MAX_PULL_STRAIN := 0.35
## The stall meter fills by strain per second times (1 + this × wear share), and
## drains by STALL_DRAIN per second without strain. It stalls at 1.
const STALL_WEAR := 2.0
const STALL_DRAIN := 0.5
## Ticks a stalled engine takes to restart, and the health share under which
## it cannot be restarted at all (more than 95% worn).
const RESTART_TICKS := 120
const NO_RESTART_HEALTH := 0.05
## A stuck vehicle is free again once the resistance under it falls below
## this share of its traction.
const FREE_SHARE := 0.85

var session: KitSession
## The smoke clouds this tick (TtwSmokeCloud): units inside go slower.
var _clouds: Array = []

func query() -> QueryBuilder:
	return q.with_all([TtwDrive, TtwVehicle, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	_clouds = session.view([TtwSmokeCloud])
	for entity in entities:
		drive(entity, terrain, delta)

func drive(entity: Entity, terrain: TtwTerrain, delta: float) -> void:
	var body := (entity.get_component(KitBody) as KitBody).node
	if not is_instance_valid(body) or entity.has_component(TtwWrecked):
		return
	var d: TtwDrive = entity.get_component(TtwDrive)
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	var fuel: TtwFuel = entity.get_component(TtwFuel)
	var condition: TtwCondition = entity.get_component(TtwCondition)
	if fuel != null and fuel.amount < 0.0:
		fuel.amount = fuel.capacity
	if condition != null and condition.health < 0.0:
		condition.health = condition.max_health
	var position := body.position
	_restart(entity, condition)
	var running := _runs(entity, fuel)
	var throttle := clampf(d.throttle, -1.0, 1.0) if running else 0.0
	var along := Vector2.from_angle(d.heading)

	# The cell and the tile under it, worked out once for the resistance, the
	# water's depth and its current.
	var tile_px := terrain.tile_size_px
	var cell := terrain.cell_index(terrain.cell_of(position).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE))
	var tile := terrain.tile_index(terrain.tile_of(position).clamp(Vector2i.ZERO, terrain.size_tiles - Vector2i.ONE))
	var depth := maxf(0.0, terrain.water[tile] - (terrain.deform[cell] + terrain.loose[cell]))
	var resistance := resistance_in(terrain, cell, d.heading, depth) + d.load
	d.resistance = resistance
	# Oil under it: it grips less (traction), gets going slower and slides
	# through its turns.
	d.grip = TtwOil.grip(terrain.effective_material(terrain.cell_of(position)), terrain.oil[cell]) if terrain.oil[cell] > 0.0 else 1.0
	# Snow: loose snow drags; packed snow is slippery.
	var snow := TtwSnow.depth_at(terrain, cell) if terrain.snow_level > 0.0 or terrain.snow_base[tile] > 0.0 else 0.0
	if snow > 0.0:
		if TtwSnow.is_packed(terrain, cell):
			d.grip *= PACKED_SNOW_GRIP
		else:
			resistance *= 1.0 + snow * SNOW_DRAG
			d.resistance = resistance
	d.grade = terrain.elevation_gradient(position).dot(along)
	var target := throttle * (d.max_speed_tiles * tile_px) * slope_factor(d.grade, throttle) / resistance
	if not _clouds.is_empty():
		target *= TtwSpecialSystem.smoke_factor(_clouds, position)
	var stuck := entity.has_component(TtwStuck)
	if resistance > d.grip_traction():
		target = 0.0
		if running and throttle != 0.0 and not stuck:
			stuck = true
			entity.add_component(TtwStuck.new())
			got_stuck.emit(entity)
	elif stuck and resistance < d.grip_traction() * FREE_SHARE:
		stuck = false
		entity.remove_component(TtwStuck)
		freed.emit(entity)
	var rate := d.accel_tiles * tile_px * (d.grip if absf(target) > absf(d.speed) else 2.0)
	# The ground holds a stuck vehicle where it is: it does not coast out.
	d.speed = 0.0 if stuck else move_toward(d.speed, target, rate * delta)
	var turning := d.steer * d.turn_rate * delta * lerpf(0.35, 1.0, d.grip)
	if v.running == TtwVehicle.Running.WHEELS:
		# Wheels turn with the motion, not on the spot.
		turning *= clampf(d.speed / (0.5 * tile_px), -1.0, 1.0)
	elif not running or stuck:
		turning = 0.0
	d.heading = wrapf(d.heading + turning, -PI, PI)
	along = Vector2.from_angle(d.heading)
	var drift := (terrain.flow[tile] if depth > 0.0 else Vector2.ZERO) * current_share(v, depth)
	position += (along * d.speed + drift) * delta
	body.position = position.clamp(Vector2.ZERO, terrain.size_px() - Vector2.ONE)

	if running and throttle != 0.0:
		_strain(entity, d, condition, strain(v, d, depth, throttle), delta)
	elif d.stall_meter > 0.0:
		d.stall_meter = maxf(0.0, d.stall_meter - STALL_DRAIN * delta)
	if fuel != null and running:
		var effort := absf(throttle) * resistance * maxf(0.4, 1.0 + d.grade * 2.0 * signf(throttle))
		fuel.amount = maxf(0.0, fuel.amount - (fuel.idle_burn + fuel.drive_burn * effort) * delta)
	if condition != null:
		_water(entity, v, condition, depth, delta)

## Whether the engine can run: not flooded, stalled or wrecked, fuel left.
static func engine_runs(entity: Entity) -> bool:
	return _runs(entity, entity.get_component(TtwFuel))

## engine_runs() for a caller that already holds the entity's tank (or null).
static func _runs(entity: Entity, fuel: TtwFuel) -> bool:
	if entity.has_component(TtwFlooded) or entity.has_component(TtwWrecked) or entity.has_component(TtwStalled):
		return false
	return fuel == null or fuel.level() > 0.0

## How hard the engine is labouring (0 = not at all): water over the wading
## depth, a climb steeper than STALL_GRADE, resistance near the traction limit.
static func strain(v: TtwVehicle, d: TtwDrive, depth: float, throttle: float) -> float:
	var total := 0.0
	if depth > v.wading_depth_px:
		total += (depth - v.wading_depth_px) / maxf(v.wading_depth_px, 0.1)
	var climb := d.grade * signf(throttle)
	if climb > STALL_GRADE:
		total += (climb - STALL_GRADE) * 3.0
	var pull := d.resistance / maxf(d.grip_traction(), 0.1)
	if pull > STALL_PULL:
		# Capped: a vehicle stuck and flooring it spins (and digs in) for a few
		# seconds before it stalls.
		total += minf((pull - STALL_PULL) * 1.0, MAX_PULL_STRAIN)
	return total * absf(throttle)

## Whether a stalled vehicle this worn can be restarted.
static func can_restart(condition: TtwCondition) -> bool:
	return condition == null or condition.share() >= NO_RESTART_HEALTH

func _strain(entity: Entity, d: TtwDrive, condition: TtwCondition, amount: float, delta: float) -> void:
	if amount <= 0.0:
		d.stall_meter = maxf(0.0, d.stall_meter - STALL_DRAIN * delta)
		return
	var worn := 1.0 - (condition.share() if condition != null else 1.0)
	d.stall_meter += amount * (1.0 + STALL_WEAR * worn) * delta
	# The tolerance keeps a meter filled in equal steps from missing 1 by rounding.
	if d.stall_meter >= 1.0 - 1e-6:
		d.stall_meter = 0.0
		d.speed = 0.0
		var stalled := TtwStalled.new()
		stalled.restart_ticks = RESTART_TICKS
		entity.add_component(stalled)
		stalled_engine.emit(entity)

func _restart(entity: Entity, condition: TtwCondition) -> void:
	var stalled: TtwStalled = entity.get_component(TtwStalled)
	if stalled == null or not can_restart(condition):
		return
	stalled.restart_ticks -= 1
	if stalled.restart_ticks <= 0:
		entity.remove_component(TtwStalled)

## Speed share from the grade along the direction of travel: below 1 going
## up, above 1 going down.
static func slope_factor(grade: float, throttle: float) -> float:
	var climb := grade if throttle >= 0.0 else -grade
	return clampf(1.0 - climb * (GRADE_UP if climb > 0.0 else GRADE_DOWN), 0.2, 1.7)

## How much of the current carries a vehicle in water `depth` px deep.
static func current_share(v: TtwVehicle, depth: float) -> float:
	return clampf(depth / maxf(v.wading_depth_px, 0.1), 0.0, 1.0) * CURRENT_CARRY

## How hard the ground under a point is to drive over, heading `heading`
## (1 = paved, dry, level road).
static func resistance_at(terrain: TtwTerrain, position: Vector2, heading: float) -> float:
	var cell := terrain.cell_index(terrain.cell_of(position).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE))
	return resistance_in(terrain, cell, heading, terrain.water_depth_at(position))

## resistance_at() for the cell of index `cell`, under water `depth` px deep.
static func resistance_in(terrain: TtwTerrain, cell: int, heading: float, depth: float) -> float:
	var n := TtwTerrain.CELLS_PER_TILE
	var width := terrain.size_cells.x
	var base := terrain.surface[(cell / width / n) * terrain.size_tiles.x + cell % width / n]
	var material := TtwMaterials.effective(base, terrain.wear[cell])
	var r: float = TtwMaterials.RESISTANCE[material]
	var rut := maxf(0.0, -terrain.deform[cell])
	if rut > 0.0:
		var along := absf(cos(heading - terrain.track_angle[cell]))
		var fresh := terrain.track[cell]
		var follow := lerpf(1.0, RUT_ALONG, along * minf(1.0, fresh + 0.5))
		r *= 1.0 + rut * RUT_CROSS * follow
	r *= 1.0 + terrain.loose[cell] * LOOSE_DRAG
	r *= 1.0 + terrain.wet[cell] * 0.15 * TtwMaterials.WET_SOFTENING[material]
	r *= 1.0 + depth * WATER_DRAG
	return r

## Health lost per second in water `depth` px deep: nothing up to the wading
## depth, then growing faster than the depth over it.
static func water_wear(condition: TtwCondition, vehicle: TtwVehicle, depth: float) -> float:
	var over := depth - vehicle.wading_depth_px
	if over <= 0.0:
		return 0.0
	return condition.water_wear * over * (1.0 + over / maxf(vehicle.wading_depth_px, 0.1))

func _water(entity: Entity, v: TtwVehicle, condition: TtwCondition, depth: float, delta: float) -> void:
	if entity.has_component(TtwFlooded):
		return
	if depth >= v.flood_depth_px:
		condition.health = minf(condition.health, condition.max_health * FLOODED_HEALTH)
		entity.add_component(TtwFlooded.new())
		flooded.emit(entity)
		return
	condition.health = maxf(0.0, condition.health - water_wear(condition, v, depth) * delta)
	if condition.health <= 0.0:
		wreck(entity)

## Destroys a vehicle: it explodes, leaving a crater, and stays as a wreck.
func wreck(entity: Entity) -> void:
	if entity.has_component(TtwWrecked):
		return
	entity.add_component(TtwWrecked.new())
	# A wreck bleeds its oil.
	entity.add_component(TtwLeak.new())
	var terrain := TtwGround.of(session)
	var body := (entity.get_component(KitBody) as KitBody).node
	if terrain != null and is_instance_valid(body):
		TtwStamps.crater(terrain, body.position, &"vehicle")
	destroyed.emit(entity)
