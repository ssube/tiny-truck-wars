class_name TtwCombat extends RefCounted
## What shooting needs to know: where a shot must go to meet a moving target,
## how long it flies, how high the ground is under it, and what a burst does.

const TILT_K := 0.6

## The height of what a shot can hit at `at` (px): the ground (elevation and
## relief) or the water over it.
static func ground_height(terrain: TtwTerrain, at: Vector2) -> float:
	var p := at.clamp(Vector2.ZERO, terrain.size_px() - Vector2.ONE)
	var base := terrain.elevation_at(p)
	var relief := terrain.relief_at(p)
	var level := terrain.water_at(p)
	return base + maxf(relief, level)

## Ticks a shot from `gun` takes from `from` to `to`.
static func flight_ticks(gun: TtwGun, from: Vector2, to: Vector2) -> int:
	return maxi(1, ceili(from.distance_to(to) / gun.speed_px() * Engine.physics_ticks_per_second))

## How fast `entity` is going over the ground (px per second).
static func velocity_of(entity: Entity) -> Vector2:
	var f: TtwFlight = entity.get_component(TtwFlight)
	if f != null:
		return f.ground_velocity
	var d: TtwDrive = entity.get_component(TtwDrive)
	if d != null and not entity.has_component(TtwWrecked):
		return Vector2.from_angle(d.heading) * d.speed
	return Vector2.ZERO

## Where to aim from `from` to meet `target` (at `at`, going `velocity`):
## where it will be when the shot lands, found by a few rounds of "how long
## would the shot take to there". `at` itself when not leading.
static func aim_point(gun: TtwGun, from: Vector2, at: Vector2, velocity: Vector2, lead: bool) -> Vector2:
	if not lead or velocity == Vector2.ZERO:
		return at
	var aim := at
	for k in 4:
		aim = at + velocity * flight_ticks(gun, from, aim) / float(Engine.physics_ticks_per_second)
	return aim

## Whether `entity` can still be shot at.
static func alive(session: KitSession, entity: Entity) -> bool:
	if not is_instance_valid(entity) or session.body_of(entity) == null or entity.has_component(TtwWrecked):
		return false
	var h: TtwHealth = entity.get_component(TtwHealth)
	return h == null or not h.destroyed

## Whether `entity` is up in the air.
static func flying(entity: Entity) -> bool:
	var f: TtwFlight = entity.get_component(TtwFlight)
	return f != null and f.airborne()

## A shot bursting on the ground at `at`: its crater, snow blown off, the
## look, damage to everything within `radius_px` (falling off from the
## middle), and a fire where there is something to burn.
static func burst(session: KitSession, fx: TtwFx, at: Vector2, ammo: StringName, radius_px: float, damage: float) -> void:
	var terrain := TtwGround.of(session)
	if terrain != null:
		var size: Vector2 = TtwStamps.CRATERS.get(ammo, TtwStamps.CRATERS[&"shell"])
		TtwStamps.crater(terrain, at, ammo)
		TtwSnow.blast(terrain, at, size.x * 2.0)
		var field := TtwGround.fire_of(session)
		if field != null:
			field.ignite(terrain.tile_of(at), 0.5)
	if fx != null:
		fx.explode(at, ammo)
	TtwDamage.blast(session, at, radius_px, damage)
