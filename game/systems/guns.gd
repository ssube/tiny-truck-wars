class_name TtwGunSystem extends System
## Units with guns pick a target and fire when loaded. An ordered target
## (TtwAttacking) comes first: out of range the unit closes in, in range it
## stops and shoots. Otherwise every SCAN_TICKS ticks (staggered per unit) it
## looks for the nearest enemy in range, units before structures, never into
## smoke, aircraft only if its gun can reach them. A shot becomes an entity
## with a TtwShell (TtwBallisticsSystem flies it).

signal fired(shooter: Entity, shell: Entity)

const SCAN_TICKS := 10
## Inside smoke a target can still be made out this close (tiles).
const SMOKE_SIGHT_TILES := 2.0
## Shots at an aircraft that miss pass this many burst radii to one side.
const MISS_SPREAD := 2.5

var session: KitSession
## The global switch for leading moving targets (each gun has its own too).
var leading: bool = true

func query() -> QueryBuilder:
	return q.with_all([TtwGun, KitBody])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var shots: Array = []
	for entity in entities:
		var gun: TtwGun = entity.get_component(TtwGun)
		if entity.has_component(TtwWrecked):
			continue
		var body := (entity.get_component(KitBody) as KitBody).node
		if not is_instance_valid(body):
			continue
		# The ordered target is followed (or let go) while reloading too.
		var target := _ordered(entity, gun, body.position)
		if session.tick < gun.ready_tick:
			continue
		# Aircraft fire only in the air.
		if entity.has_component(TtwFlight) and not TtwCombat.flying(entity):
			continue
		if target == null and (session.tick + entity.get_instance_id()) % SCAN_TICKS == 0:
			target = pick(entity, gun, body.position)
		if target != null:
			shots.append([entity, target])
	for shot in shots:
		fire(shot[0], shot[1])

## Orders `entity` to attack `target`: it closes in and fires until the
## target is gone or another order replaces this one.
static func attack(session: KitSession, entity: Entity, target: Entity) -> void:
	session.link(entity, TtwAttacking, target)
	var gun: TtwGun = entity.get_component(TtwGun)
	var a := session.body_of(entity)
	var b := session.body_of(target)
	if gun != null and a != null and b != null and a.position.distance_to(b.position) > gun.range_px():
		TtwPilotSystem.order(entity, b.position)
		(entity.get_component(TtwMoveOrder) as TtwMoveOrder).chase = true

## The ordered target if it is in range (closing in on it if not), or null.
func _ordered(entity: Entity, gun: TtwGun, at: Vector2) -> Entity:
	var target := session.linked(entity, TtwAttacking)
	if target == null:
		return null
	if not TtwCombat.alive(session, target) or (TtwCombat.flying(target) and not gun.hits_air):
		session.unlink(entity, TtwAttacking)
		return null
	var there := session.body_of(target).position
	var order: TtwMoveOrder = entity.get_component(TtwMoveOrder)
	if at.distance_to(there) <= gun.range_px():
		if order != null and order.chase:
			TtwPilotSystem.stop(entity)
		return target
	# Out of range: keep after it (the route is planned again as it moves).
	if order == null or (order.chase and order.target.distance_to(there) > TtwTerrain.tile_px()):
		TtwPilotSystem.order(entity, there)
		(entity.get_component(TtwMoveOrder) as TtwMoveOrder).chase = true
	return null

## The nearest enemy `entity` can shoot from `at`: units before structures.
func pick(entity: Entity, gun: TtwGun, at: Vector2) -> Entity:
	var side := TtwTeam.of(entity)
	var reach := gun.range_px()
	var clouds := session.view([TtwSmokeCloud])
	var best: Entity = null
	var best_score := INF
	for other in session.view([TtwTeam, KitBody]):
		var team := TtwTeam.of(other)
		if team == side or team == TtwTeam.NEUTRAL:
			continue
		if not (other.has_component(TtwCondition) or other.has_component(TtwHealth)):
			continue
		var there := session.body_of(other)
		if there == null:
			continue
		var d := at.distance_to(there.position)
		if d > reach or not TtwCombat.alive(session, other):
			continue
		if TtwCombat.flying(other) and not gun.hits_air:
			continue
		if not clouds.is_empty() and d > SMOKE_SIGHT_TILES * TtwTerrain.tile_px() and _in_smoke(clouds, there.position):
			continue
		var score := d + (reach if other.has_component(TtwStructure) else 0.0)
		if score < best_score:
			best = other
			best_score = score
	return best

static func _in_smoke(clouds: Array, at: Vector2) -> bool:
	for cloud in clouds:
		var c: TtwSmokeCloud = cloud.get_component(TtwSmokeCloud)
		if c.center.distance_to(at) <= c.radius_px:
			return true
	return false

## Fires `entity`'s gun at `target` now: a shell entity on its way to where
## the target will be (unless leading is off), reloaded after.
func fire(entity: Entity, target: Entity) -> Entity:
	var gun: TtwGun = entity.get_component(TtwGun)
	var terrain := TtwGround.of(session)
	var from := session.body_of(entity).position
	var there := session.body_of(target).position
	var aim := TtwCombat.aim_point(gun, from, there, TtwCombat.velocity_of(target), gun.lead and leading)
	var s := TtwShell.new()
	s.ammo = gun.ammo
	s.damage = gun.damage
	s.splash_px = gun.splash_tiles * TtwTerrain.tile_px()
	s.team = TtwTeam.of(entity)
	var own_flight: TtwFlight = entity.get_component(TtwFlight)
	s.from = from
	s.from_h = TtwCombat.ground_height(terrain, from) + gun.muzzle_px + (own_flight.altitude if own_flight != null else 0.0)
	if TtwCombat.flying(target):
		s.air = true
		gun.air_shots += 1
		s.hit = floori(gun.air_shots * gun.air_accuracy) > floori((gun.air_shots - 1) * gun.air_accuracy)
		if not s.hit:
			aim += (aim - from).normalized().orthogonal() * s.splash_px * MISS_SPREAD * (1.0 if gun.air_shots % 2 == 0 else -1.0)
		s.to_h = TtwCombat.ground_height(terrain, aim) + (target.get_component(TtwFlight) as TtwFlight).altitude
	else:
		s.to_h = TtwCombat.ground_height(terrain, aim)
	s.to = aim
	s.apex = gun.arc * from.distance_to(aim)
	s.fired_tick = session.tick
	s.flight_ticks = TtwCombat.flight_ticks(gun, from, aim)
	gun.ready_tick = session.tick + ceili(gun.reload_seconds * Engine.physics_ticks_per_second)
	var shell := Entity.new()
	# No alias: the session gives it a unique one (a loaded game's shells
	# keep theirs).
	shell.add_component(s)
	if not session.register(shell):
		shell.free()
		return null
	fired.emit(entity, shell)
	return shell
