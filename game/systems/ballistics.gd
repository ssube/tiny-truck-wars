class_name TtwBallisticsSystem extends System
## Flies shots (TtwShell). Each tick a shot's path is walked in short steps
## from where it was to where it is now; it bursts where it first meets the
## ground (elevation, relief or water: a ridge can stop a shot short) or an
## obstacle taller than it is over the ground there (a building, a tree),
## and otherwise at its end. A shot at an aircraft bursts in the air there,
## hurting it if it hit.

signal burst(shell: Entity, at: Vector2, on: StringName)

## Longest step (px over the ground) between the checks along a path.
const STEP_PX := 3.0
## Share of the flight near the muzzle where nothing is checked.
const MUZZLE_SHARE := 0.04

var session: KitSession
var fx: TtwFx
var _point := PhysicsPointQueryParameters2D.new()

func _init() -> void:
	_point.collision_mask = Kit2D.LAYER_STRUCTURES

func query() -> QueryBuilder:
	return q.with_all([TtwShell])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	var space := session.get_viewport().world_2d.direct_space_state
	var landed: Array = []
	for entity in entities:
		var s: TtwShell = entity.get_component(TtwShell)
		var now := clampf(float(session.tick - s.fired_tick) / s.flight_ticks, 0.0, 1.0)
		var hit := _walk(s, terrain, space, now)
		if not hit.is_empty() or now >= 1.0:
			landed.append([entity, hit])
	for item in landed:
		_land(item[0], item[1])

## Where the shot meets something between `done` and `now` (shares of its
## flight): {at, on, obstacle?}; empty if nothing.
func _walk(s: TtwShell, terrain: TtwTerrain, space: PhysicsDirectSpaceState2D, now: float) -> Dictionary:
	var length := s.from.distance_to(s.to)
	var steps := maxi(1, ceili((now - s.done) * length / STEP_PX))
	var start := s.done
	for k in steps:
		var t := lerpf(start, now, float(k + 1) / steps)
		s.done = t
		if t < MUZZLE_SHARE:
			continue
		var p := s.at(t)
		var at := Vector2(p.x, p.y)
		if not Rect2(Vector2.ZERO, terrain.size_px()).has_point(at):
			return {"at": at.clamp(Vector2.ZERO, terrain.size_px() - Vector2.ONE), "on": &"edge"}
		var ground := TtwCombat.ground_height(terrain, at)
		if p.z <= ground:
			return {"at": at, "on": &"ground"}
		_point.position = at
		for found in space.intersect_point(_point, 4):
			var owner: Node = found.collider.get_parent() if found.collider is StaticBody2D else found.collider
			var other := session.entity_for(owner)
			if other == null or not other.has_component(TtwObstacle):
				continue
			var tall := (other.get_component(TtwObstacle) as TtwObstacle).height_px
			if other.has_component(TtwTree):
				tall = (other.get_component(TtwTree) as TtwTree).height_px
			if p.z - ground < tall:
				return {"at": at, "on": &"obstacle"}
	return {}

func _land(entity: Entity, hit: Dictionary) -> void:
	var s: TtwShell = entity.get_component(TtwShell)
	session.remove_entity(entity)
	if hit.is_empty() and s.air:
		_air_burst(s)
		burst.emit(entity, s.to, &"air")
		return
	var at: Vector2 = hit.get("at", s.to)
	TtwCombat.burst(session, fx, at, s.ammo, s.splash_px, s.damage)
	burst.emit(entity, at, hit.get("on", &"ground"))

func _air_burst(s: TtwShell) -> void:
	if fx != null:
		fx.puffs.puff(TtwPuffs.Kind.PLUME, s.to + Vector2(0, -s.to_h * TtwCombat.TILT_K), Vector2.ZERO, 4, 0.5, 1.0)
	if not s.hit:
		return
	for other in session.view([TtwFlight, TtwCondition, KitBody]).duplicate():
		if TtwTeam.of(other) == s.team or not TtwCombat.flying(other):
			continue
		var d := session.body_of(other).position.distance_to(s.to)
		if d <= s.splash_px:
			TtwDamage.hurt(session, other, s.damage * (1.0 - 0.5 * d / s.splash_px), s.from)
