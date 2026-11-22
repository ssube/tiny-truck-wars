class_name TtwWakeSystem extends System
## Vehicles moving through water: a bow wave of foam and ripples, and silt
## stirred up from a soft bottom. Drawing only (TtwWaterFx); nothing reads it.

## Below this speed (px/s) or depth (px) a vehicle leaves no wake.
const MIN_SPEED := 4.0
const MIN_DEPTH := 0.3

var session: KitSession
var fx: TtwWaterFx

func query() -> QueryBuilder:
	return q.with_all([TtwVehicle, TtwDrive, KitBody]).iterate([TtwVehicle, TtwDrive, KitBody])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	if fx == null:
		return
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	# The matches' components, in step with `entities` (nothing here adds or
	# removes one). Most vehicles are on dry ground and are passed over at once.
	var vehicles: Array = components[0]
	var drives: Array = components[1]
	var bodies: Array = components[2]
	for k in entities.size():
		var v: TtwVehicle = vehicles[k]
		if v.water_depth < MIN_DEPTH:
			continue
		var d: TtwDrive = drives[k]
		var body := (bodies[k] as KitBody).node
		if not is_instance_valid(body):
			continue
		var wake := wake_of(v, d, terrain.effective_material_at(body.position))
		if wake == Vector3.ZERO:
			continue
		var along := Vector2.from_angle(d.heading) * signf(d.speed)
		var reach := maxf(v.tread_length_px * 0.5, absf(v.axles_px[0]) if not v.axles_px.is_empty() else 8.0)
		fx.splash(body.position + along * reach, v.gauge_px * 0.7, wake.x, wake.y * 0.4, wake.z)
		fx.splash(body.position - along * reach * 0.6, v.gauge_px * 0.6, wake.x * 0.4, wake.y, wake.z * 0.3)

## Foam, silt and ripple a vehicle stirs per tick: more with speed and depth,
## silt from a bottom that is soft.
static func wake_of(v: TtwVehicle, d: TtwDrive, bottom: int) -> Vector3:
	var speed := absf(d.speed)
	if speed < MIN_SPEED or v.water_depth < MIN_DEPTH:
		return Vector3.ZERO
	var pace := clampf(speed / Kit2D.tiles(4.0), 0.0, 1.5)
	var deep := clampf(v.water_depth / maxf(v.wading_depth_px, 0.1), 0.0, 1.5)
	var soft: float = TtwMaterials.SOFTNESS[bottom]
	return Vector3(0.05 * pace * deep, (0.02 + 0.08 * soft) * (0.5 + pace), 0.35 * pace * deep)
