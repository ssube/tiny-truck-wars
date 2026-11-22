class_name TtwFlightSystem extends System
## Flies aircraft (TtwFlight). They go straight to a move order's target over
## anything on the ground, at their cruise height. The wind pushes them by a
## share of itself; the pilot steers against it (the nose turns into the
## wind, so a helicopter crabs across it) and holds station when it stops.
## With no order over its side's helipad it lands. Out of fuel it can steer
## no more: it sinks and drifts downwind until it is down. A wreck falls.

signal arrived(entity: Entity)

const ARRIVE_PX := 6.0
## It slows over this last stretch to a target (px).
const SLOW_PX := 40.0
## Height it must reach before it moves off (px).
const LIFT_OFF_PX := 4.0
## How fast a wreck falls (px per second).
const FALL_PX := 40.0

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwFlight, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var weather := TtwWeatherSystem.of(session)
	var wind := weather.wind_now if weather != null else Vector2.ZERO
	var terrain := TtwGround.of(session)
	for entity in entities.duplicate():
		fly(entity, wind, terrain, delta)

func fly(entity: Entity, wind: Vector2, terrain: TtwTerrain, delta: float) -> void:
	var body := (entity.get_component(KitBody) as KitBody).node
	if not is_instance_valid(body):
		return
	var f: TtwFlight = entity.get_component(TtwFlight)
	var fuel: TtwFuel = entity.get_component(TtwFuel)
	var condition: TtwCondition = entity.get_component(TtwCondition)
	if fuel != null and fuel.amount < 0.0:
		fuel.amount = fuel.capacity
	if condition != null and condition.health < 0.0:
		condition.health = condition.max_health
	if entity.has_component(TtwWrecked):
		f.velocity = Vector2.ZERO
		f.ground_velocity = Vector2.ZERO
		f.altitude = move_toward(f.altitude, 0.0, FALL_PX * delta)
		if entity.has_component(TtwMoveOrder):
			entity.remove_component(TtwMoveOrder)
		return
	var tile := TtwTerrain.tile_px()
	var push := wind * f.drift
	var powered := fuel == null or fuel.level() > 0.0
	var order: TtwMoveOrder = entity.get_component(TtwMoveOrder)
	var at := body.position
	var cruise := f.cruise_px if f.hold_px < 0.0 else f.hold_px
	f.hold_px = -1.0
	var want_height := cruise
	var want_ground := Vector2.ZERO
	if not powered:
		want_height = 0.0
	elif order != null:
		var to := order.target - at
		if to.length() < ARRIVE_PX:
			TtwPilotSystem.stop(entity)
			arrived.emit(entity)
		elif f.altitude >= LIFT_OFF_PX:
			want_ground = to.normalized() * f.max_speed_tiles * tile * clampf(to.length() / SLOW_PX, 0.15, 1.0)
	elif _over_pad(entity, at):
		want_height = 0.0
	if powered:
		# Steer for the ground velocity it wants, against the wind's push.
		var want_air := (want_ground - (push if f.airborne() else Vector2.ZERO)).limit_length(f.max_speed_tiles * tile)
		f.velocity = f.velocity.move_toward(want_air, f.accel_tiles * tile * delta)
	else:
		f.velocity = f.velocity.move_toward(Vector2.ZERO, f.accel_tiles * tile * delta)
	f.altitude = move_toward(f.altitude, want_height, f.climb_px * delta)
	if f.airborne():
		f.ground_velocity = f.velocity + push
	else:
		f.velocity = Vector2.ZERO
		f.ground_velocity = Vector2.ZERO
	if f.velocity.length() > 2.0:
		f.heading = f.velocity.angle()
	var moved := at + f.ground_velocity * delta
	body.position = moved.clamp(Vector2.ZERO, terrain.size_px() - Vector2.ONE) if terrain != null else moved
	if fuel != null and powered and f.airborne():
		var effort := f.velocity.length() / maxf(f.max_speed_tiles * tile, 1.0)
		fuel.amount = maxf(0.0, fuel.level() - (f.hover_burn + f.speed_burn * effort) * delta)

## Whether `entity` is over one of its side's helipads.
func _over_pad(entity: Entity, at: Vector2) -> bool:
	var side := TtwTeam.of(entity)
	for pad in session.view([TtwHelipad, KitBody]):
		if TtwTeam.of(pad) != side:
			continue
		var h: TtwHelipad = pad.get_component(TtwHelipad)
		if session.body_of(pad).position.distance_to(at) <= h.service_tiles * TtwTerrain.tile_px():
			return true
	return false
