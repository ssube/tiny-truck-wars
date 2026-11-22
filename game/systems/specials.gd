class_name TtwSpecialSystem extends System
## The special units: the nurse heals its side's ground vehicles near it
## (every SERVICE_TICKS); the hippy's smoke clouds drift with the wind and
## clear when their time is up. (The boss is read by TtwGarageSystem; how
## smoke slows and hides, by TtwDriveSystem and TtwGunSystem.)

signal smoked(hippy: Entity, cloud: Entity)

const SERVICE_TICKS := 10

var session: KitSession
var fx: TtwFx

## The map's entity: one call a tick.
func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(_entities: Array[Entity], _components: Array, delta: float) -> void:
	if session.tick % SERVICE_TICKS == 0:
		for nurse in session.view([TtwMedic, KitBody]):
			_heal(nurse, delta * SERVICE_TICKS)
	var clouds := session.view([TtwSmokeCloud])
	if clouds.is_empty():
		return
	var weather := TtwWeatherSystem.of(session)
	var drift := weather.wind_now * TtwSmokeScreen.DRIFT * delta if weather != null else Vector2.ZERO
	for cloud in clouds.duplicate():
		var c: TtwSmokeCloud = cloud.get_component(TtwSmokeCloud)
		if session.tick >= c.until_tick:
			session.remove_entity(cloud)
			continue
		c.center += drift

## The hippy throws its smoke at `at` (as far as it can toward it). Empty when
## done; otherwise why not.
static func smoke(session: KitSession, hippy: Entity, at: Vector2) -> String:
	var launcher: TtwSmokeLauncher = hippy.get_component(TtwSmokeLauncher)
	if launcher == null:
		return "It has no smoke."
	if hippy.has_component(TtwWrecked):
		return "It is wrecked."
	if session.tick < launcher.ready_tick:
		return "Smoke is not ready (%d s)." % ceili((launcher.ready_tick - session.tick) / float(Engine.physics_ticks_per_second))
	var from := session.body_of(hippy).position
	var reach := launcher.throw_tiles * TtwTerrain.tile_px()
	var spot := from + (at - from).limit_length(reach)
	var c := TtwSmokeCloud.new()
	c.center = spot
	c.radius_px = launcher.radius_tiles * TtwTerrain.tile_px()
	c.slow = launcher.slow
	c.until_tick = session.tick + ceili(launcher.seconds * Engine.physics_ticks_per_second)
	launcher.ready_tick = session.tick + ceili(launcher.cooldown_seconds * Engine.physics_ticks_per_second)
	var system: TtwSpecialSystem = session.system(&"specials")
	var cloud := Entity.new()
	cloud.add_component(c)
	if not session.register(cloud):
		cloud.free()
		return "No smoke."
	if system.fx != null:
		system.fx.smoke_screen(spot, c.radius_px, launcher.seconds)
	system.smoked.emit(hippy, cloud)
	return ""

## The speed share left to a ground unit at `at` among `clouds` (1: none).
static func smoke_factor(clouds: Array, at: Vector2) -> float:
	var factor := 1.0
	for cloud in clouds:
		var c: TtwSmokeCloud = cloud.get_component(TtwSmokeCloud)
		if c.center.distance_squared_to(at) <= c.radius_px * c.radius_px:
			factor = minf(factor, c.slow)
	return factor

func _heal(nurse: Entity, dt: float) -> void:
	if nurse.has_component(TtwWrecked):
		return
	var m: TtwMedic = nurse.get_component(TtwMedic)
	var at := session.body_of(nurse).position
	var side := TtwTeam.of(nurse)
	var reach := m.reach_tiles * TtwTerrain.tile_px()
	for unit in session.view([TtwVehicle, TtwCondition, KitBody]):
		if unit == nurse or TtwTeam.of(unit) != side or unit.has_component(TtwWrecked):
			continue
		if session.body_of(unit).position.distance_to(at) > reach:
			continue
		var c: TtwCondition = unit.get_component(TtwCondition)
		c.health = minf(c.max_health, c.current() + m.rate * dt)
