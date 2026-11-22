class_name TtwPilotSystem extends System
## Drives vehicles with a move order (TtwMoveOrder): plans a route on the path
## grid, steers for each turn point in turn, and stops at the target. Routes
## are planned again every few seconds, so they follow the ground as it
## changes. Treads turn on the spot for sharp turns; wheels slow into them.
## A stuck, stalled or wrecked vehicle keeps its order and waits (a winch may
## free it), except that a wreck or a flooded engine drops it. One that runs
## but gets nowhere (hung on a corner, boxed in) backs off, turning, and
## plans again; after MAX_TRIES of that it gives up the order.

signal arrived(entity: Entity)

## Within this of a turn point it heads for the next; within ARRIVE_PX of the
## target it stops.
const TURN_POINT_PX := 10.0
const ARRIVE_PX := 6.0
const REPLAN_TICKS := 180
## Within this many of its radii of the target, a vehicle up against one
## standing nearer it has arrived (a group settles round one spot).
const CROWD_RADII := 8.0
## Every PROGRESS_TICKS a vehicle driving must have moved PROGRESS_PX or
## turned PROGRESS_TURN; if not it backs off for BACK_TICKS.
const PROGRESS_TICKS := 90
const PROGRESS_PX := 6.0
const PROGRESS_TURN := 0.3
const BACK_TICKS := 45
const MAX_TRIES := 3
## Treads turn in place past this heading error (radians).
const PIVOT := 0.9
## Steer per radian of heading error.
const STEER_GAIN := 2.5

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwMoveOrder, TtwDrive, TtwVehicle, KitBody])

## Orders `entity` to drive to `target`.
static func order(entity: Entity, target: Vector2) -> void:
	var o: TtwMoveOrder = entity.get_component(TtwMoveOrder)
	if o == null:
		o = TtwMoveOrder.new()
		o.target = target
		entity.add_component(o)
	o.target = target
	o.chase = false
	o.check_tick = 0
	o.tries = 0
	o.reverse_until = 0
	o.path = PackedVector2Array()
	o.next = 0
	o.replan_tick = 0

## Cancels its order and lets go of the controls.
static func stop(entity: Entity) -> void:
	if entity.has_component(TtwMoveOrder):
		entity.remove_component(TtwMoveOrder)
	var d: TtwDrive = entity.get_component(TtwDrive)
	if d != null:
		d.throttle = 0.0
		d.steer = 0.0

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var paths := TtwGround.paths_of(session)
	if paths == null:
		return
	for entity in entities.duplicate():
		_pilot(entity, paths)

func _pilot(entity: Entity, paths: TtwPathGrid) -> void:
	if entity.has_component(TtwWrecked) or entity.has_component(TtwFlooded):
		stop(entity)
		return
	var o: TtwMoveOrder = entity.get_component(TtwMoveOrder)
	var d: TtwDrive = entity.get_component(TtwDrive)
	var position := (entity.get_component(KitBody) as KitBody).node.position
	if session.tick < o.reverse_until:
		d.throttle = -0.8
		d.steer = o.reverse_steer
		return
	if not _progressing(entity, o, d, position):
		return
	if session.tick >= o.replan_tick:
		o.path = paths.find(position, o.target)
		o.next = 0
		o.replan_tick = session.tick + REPLAN_TICKS
		if o.path.is_empty():
			stop(entity)
			session.notify("No way there.")
			return
	while o.next < o.path.size() - 1 and position.distance_to(o.path[o.next]) < TURN_POINT_PX:
		o.next += 1
	var aim := o.path[o.next]
	var to := aim - position
	var last := o.next == o.path.size() - 1
	if last and to.length() < ARRIVE_PX:
		stop(entity)
		arrived.emit(entity)
		return
	# Near the spot and up against one that stands nearer: it has arrived.
	if last:
		var separation: TtwSeparationSystem = session.system(&"separation")
		var r := TtwSeparationSystem.radius_of(entity.get_component(TtwVehicle))
		if to.length() < CROWD_RADII * r and separation != null and separation.blocked_short(entity, o.target):
			stop(entity)
			arrived.emit(entity)
			return
	var error := wrapf(to.angle() - d.heading, -PI, PI)
	d.steer = clampf(error * STEER_GAIN, -1.0, 1.0)
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	var throttle := 1.0
	if v.running == TtwVehicle.Running.TREADS:
		throttle = 0.0 if absf(error) > PIVOT else 1.0
	else:
		throttle = lerpf(1.0, 0.35, clampf(absf(error) / PI, 0.0, 1.0))
	if last:
		# Ease in over the last two tiles.
		throttle *= clampf(to.length() / (2.0 * TtwTerrain.tile_px()), 0.3, 1.0)
	d.throttle = throttle

## Checks the vehicle is getting somewhere. False when it has just started
## backing off or given up (the caller leaves the controls alone).
func _progressing(entity: Entity, o: TtwMoveOrder, d: TtwDrive, position: Vector2) -> bool:
	if session.tick < o.check_tick:
		return true
	var waiting := entity.has_component(TtwStuck) or not TtwDriveSystem.engine_runs(entity)
	var moved := position.distance_to(o.check_at) >= PROGRESS_PX or absf(wrapf(d.heading - o.check_heading, -PI, PI)) >= PROGRESS_TURN
	var first := o.check_tick == 0
	o.check_tick = session.tick + PROGRESS_TICKS
	o.check_at = position
	o.check_heading = d.heading
	if first or waiting or moved:
		if moved:
			o.tries = 0
		return true
	o.tries += 1
	if o.tries > MAX_TRIES:
		stop(entity)
		session.notify("It cannot get through.")
		return false
	# Back off, turning away from where it was heading, then plan again.
	o.reverse_until = session.tick + BACK_TICKS
	o.reverse_steer = 1.0 if o.tries % 2 == 1 else -1.0
	o.replan_tick = o.reverse_until
	o.check_tick = o.reverse_until + PROGRESS_TICKS
	d.throttle = -0.8
	d.steer = o.reverse_steer
	return false
