class_name TtwEffectsSystem extends System
## What vehicles throw up as they drive (drawing only, TtwFx): mud clods from
## slipping wheels on soft ground, dust on dry ground, droplets off a bow
## wave, and exhaust (thicker and darker under strain). Each effect has its
## own cadence in ticks, staggered per vehicle so a column doesn't puff in step.

const CLOD_EVERY := 6
const DUST_EVERY := 8
const SPLASH_EVERY := 4
const EXHAUST_EVERY := 12
const STRAINED_EXHAUST_EVERY := 5
## Slip past which wheels throw mud; speed (tiles/s) past which dust rises.
const SLIP_CLODS := 0.3
const DUST_SPEED := 1.5

var session: KitSession
var fx: TtwFx

func query() -> QueryBuilder:
	return q.with_all([TtwVehicle, TtwDrive, KitBody]).iterate([TtwVehicle, TtwDrive, KitBody])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	if fx == null or fx.debris == null:
		return
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	_rotor_wash(terrain)
	# The matches' components, in step with `entities` (nothing here adds or
	# removes one).
	var vehicles: Array = components[0]
	var drives: Array = components[1]
	var bodies: Array = components[2]
	for k in entities.size():
		var entity := entities[k]
		var tick := session.tick + (entity.get_instance_id() % 7)
		# Nothing is made on a tick that is on none of the cadences.
		if tick % CLOD_EVERY != 0 and tick % DUST_EVERY != 0 and tick % SPLASH_EVERY != 0 and tick % EXHAUST_EVERY != 0 and tick % STRAINED_EXHAUST_EVERY != 0:
			continue
		if entity.has_component(TtwWrecked):
			continue
		var body := (bodies[k] as KitBody).node
		if is_instance_valid(body):
			_vehicle(vehicles[k], drives[k], body.position, terrain, tick)

func _vehicle(v: TtwVehicle, d: TtwDrive, at: Vector2, terrain: TtwTerrain, tick: int) -> void:
	var along := Vector2.from_angle(d.heading)
	var reach := maxf(v.tread_length_px * 0.5, absf(v.axles_px[0]) if not v.axles_px.is_empty() else 8.0)
	var rear := at - along * reach * signf(d.speed if d.speed != 0.0 else 1.0)
	var moving := absf(d.speed)
	var for_effects := effects_for(v, d, terrain.effective_material_at(at), terrain.cell_value(TtwTerrain.Layer.WET, terrain.cell_of(at)))
	# Snow covers the ground: no mud thrown, no dust raised.
	if TtwSnow.depth(terrain, at) > 0.5:
		for_effects.erase(&"clods")
		for_effects.erase(&"dust")
	if for_effects.has(&"clods") and tick % CLOD_EVERY == 0:
		var slip := clampf(d.resistance / maxf(d.grip_traction(), 0.1), 0.0, 1.0) * absf(d.throttle)
		# One wheel at a time, alternating.
		for side in [-1.0 if (tick / CLOD_EVERY) % 2 == 0 else 1.0]:
			var wheel: Vector2 = rear + along.orthogonal() * side * v.gauge_px * 0.5
			fx.debris.throw(TtwDebris.Kind.CLOD, Vector3(wheel.x, wheel.y, 1.0), -along * signf(d.speed if d.speed != 0.0 else 1.0), 30.0 + 50.0 * slip, 0.8, 45.0 + 30.0 * slip, 1)
	if for_effects.has(&"dust") and tick % DUST_EVERY == 0:
		fx.puffs.puff(TtwPuffs.Kind.DUST, rear, -along * moving * 0.2, 2, 0.6 + moving / Kit2D.tiles(6.0))
	if for_effects.has(&"droplets") and tick % SPLASH_EVERY == 0:
		var bow := at + along * reach * signf(d.speed)
		for side in [-1.0, 1.0]:
			fx.debris.throw(TtwDebris.Kind.DROPLET, Vector3(bow.x, bow.y, 1.0), along.orthogonal() * side + along * 0.5, 20.0 + moving * 0.4, 0.9, 40.0, 2)
	if for_effects.has(&"exhaust"):
		var strained := d.stall_meter > 0.05 or d.resistance > d.grip_traction() * 0.6
		if tick % (STRAINED_EXHAUST_EVERY if strained else EXHAUST_EVERY) == 0:
			fx.puffs.puff(TtwPuffs.Kind.EXHAUST, rear + Vector2(0, -6), -along * 6.0 + Vector2(0, -6), 3 if strained else 1, 1.4 if strained else 0.8)

## Which effects a vehicle makes this tick, from how it is going and what it
## is on: any of &"clods", &"dust", &"droplets", &"exhaust".
static func effects_for(v: TtwVehicle, d: TtwDrive, material: int, wetness: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var speed := absf(d.speed)
	var slip := clampf(d.resistance / maxf(d.grip_traction(), 0.1), 0.0, 1.0) * absf(d.throttle)
	var in_water := v.water_depth > TtwWakeSystem.MIN_DEPTH
	if in_water:
		if speed > TtwWakeSystem.MIN_SPEED:
			out.append(&"droplets")
	else:
		if slip > SLIP_CLODS and TtwMaterials.SOFTNESS[material] >= 0.4 and absf(d.throttle) > 0.0:
			out.append(&"clods")
		if speed > Kit2D.tiles(DUST_SPEED) and wetness < 0.15 and material != TtwMaterials.MUD:
			out.append(&"dust")
	if d.throttle != 0.0 and speed + absf(d.throttle) > 0.0:
		out.append(&"exhaust")
	return out

## Rotor wash under a low helicopter: rings on water, dust off dry ground
## and snow, stronger the lower it hovers.
const WASH_EVERY := 6
const WASH_PX := 30.0

var _washed_tick: int = -1

func _rotor_wash(terrain: TtwTerrain) -> void:
	# process() runs once per archetype of vehicles: the wash once a tick.
	if _washed_tick == session.tick:
		return
	_washed_tick = session.tick
	for entity in session.view([TtwFlight, KitBody]):
		var tick: int = session.tick + (entity.get_instance_id() % 5)
		if tick % WASH_EVERY != 0:
			continue
		var f: TtwFlight = entity.get_component(TtwFlight)
		if not f.airborne() or f.altitude >= WASH_PX or entity.has_component(TtwWrecked):
			continue
		var at := session.body_of(entity).position
		var strength := 1.0 - f.altitude / WASH_PX
		if terrain.water_depth_at(at) > 0.3:
			fx.water.splash(at, 8.0 + 10.0 * strength, 0.3 * strength, 0.0, 0.8 * strength)
			continue
		var cell := terrain.cell_of(at)
		var snowy := TtwSnow.depth(terrain, at) > 0.5
		if snowy or (terrain.cell_value(TtwTerrain.Layer.WET, cell) < 0.2 and terrain.effective_material_at(at) != TtwMaterials.MUD):
			var k: int = (tick / WASH_EVERY) % 4
			var out := Vector2.from_angle(TAU * k / 4.0 + 0.4)
			fx.puffs.puff(TtwPuffs.Kind.DUST, at + out * 10.0, out * 30.0 * strength, 2, 0.6 + 0.6 * strength)
