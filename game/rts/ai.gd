class_name TtwAiSystem extends System
## Computer opponents (TtwAi). Every `think_ticks` each looks at its side and
## gives orders through the same calls the player's commander uses:
## - Production: keeps one unit in each garage's queue: an engineer and a
##   wrecker first, then tanks, a nurse, a hippy, a tanker, a boss when rich;
##   gunships from a helipad.
## - Expansion: its engineer builds depots beside the others (they refill
##   faster together) and a helipad, driving to the site first.
## - Capture: sends a tank to sit on the nearest neutral depot.
## - Recovery: an idle wrecker winches the nearest stuck or stranded unit.
## - Defence: enemies near its base are attacked by the whole army.
## - Waves: tanks gather at a rally point; with `attack_size` of them they go
##   for the nearest enemy garage; beaten back (under two left) they regroup
##   and the next wave is bigger. The hippy smokes enemies near it; the
##   nurse follows the army.
## - Fuel: a unit low on fuel goes to the nearest depot of its side.
## It sees what the player sees of its own side, and the enemy's positions.

signal thought(ai: TtwAi)

const LOW_FUEL := 0.25
const RALLY_SHARE := 0.3
## Within this of its post a unit is not sent again (tiles).
const NEAR_TILES := 3.0

var session: KitSession
## Builds a structure if the rules allow: func(kind, at, team) -> Entity
## (TtwGame.place_structure).
var placer: Callable

func query() -> QueryBuilder:
	return q.with_all([TtwAi])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var ai: TtwAi = entity.get_component(TtwAi)
		if session.tick >= ai.next_tick:
			ai.next_tick = session.tick + ai.think_ticks
			think(ai)

## Adds a computer opponent for `team`.
static func play(session: KitSession, team: int) -> Entity:
	var entity := Entity.new()
	entity.alias = "ai:%d" % team
	var ai := TtwAi.new()
	ai.team = team
	entity.add_component(ai)
	if not session.register(entity):
		entity.free()
		return null
	return entity

## One look at the side and the orders that follow.
func think(ai: TtwAi) -> void:
	var side := ai.team
	var mine := _units(side)
	var garages := _structures(side, TtwGarage)
	if garages.is_empty():
		return
	if ai.home == Vector2.ZERO:
		ai.home = session.body_of(garages[0]).position
		var terrain := TtwGround.of(session)
		var middle := terrain.size_px() * 0.5 if terrain != null else ai.home
		ai.rally = ai.home.lerp(middle, RALLY_SHARE)
	var fuel := _fuel(side)
	_produce(ai, garages, _structures(side, TtwHelipad), mine, fuel)
	_recover(mine)
	_expand(ai, mine, fuel)
	_capture(ai, mine)
	_army(ai, mine)
	_refuel(side, mine)
	thought.emit(ai)

#region What it has

## Its units that can still act, by kind.
func _units(side: int) -> Dictionary:
	var out := {}
	for entity in session.view([TtwUnit, TtwTeam, KitBody]):
		if TtwTeam.of(entity) != side or entity.has_component(TtwWrecked):
			continue
		var kind := TtwUnits.kind_of(entity)
		if not out.has(kind):
			out[kind] = []
		out[kind].append(entity)
	return out

func _count(mine: Dictionary, kind: StringName) -> int:
	return mine.get(kind, []).size()

func _structures(side: int, part: Script) -> Array:
	return session.view([part, TtwTeam, KitBody]).filter(func(e): return TtwTeam.of(e) == side and not e.has_component(TtwDetonating))

func _fuel(side: int) -> float:
	var total := 0.0
	for depot in _structures(side, TtwDepot):
		total += (depot.get_component(TtwDepot) as TtwDepot).level()
	return total

func _at(entity: Entity) -> Vector2:
	return session.body_of(entity).position

## Sends `unit` to `to` unless it is near there or already going.
func _send(unit: Entity, to: Vector2) -> void:
	var order: TtwMoveOrder = unit.get_component(TtwMoveOrder)
	if order != null and order.target.distance_to(to) < TtwTerrain.tile_px():
		return
	if _at(unit).distance_to(to) <= NEAR_TILES * TtwTerrain.tile_px():
		return
	TtwPilotSystem.order(unit, to)

#endregion

#region Production

func _produce(ai: TtwAi, garages: Array, helipads: Array, mine: Dictionary, fuel: float) -> void:
	for garage in garages:
		var queue: TtwBuildQueue = garage.get_component(TtwBuildQueue)
		if queue != null and queue.queue.is_empty():
			TtwGarageSystem.enqueue(garage, next_unit(ai, mine, fuel))
	for pad in helipads:
		var queue: TtwBuildQueue = pad.get_component(TtwBuildQueue)
		if queue != null and queue.queue.is_empty() and _count(mine, &"gunship") < 2 and fuel > 350.0:
			TtwGarageSystem.enqueue(pad, &"gunship")

## What a garage of this side should build next.
static func next_unit(ai: TtwAi, mine: Dictionary, fuel: float) -> StringName:
	var tanks: int = mine.get(&"tank", []).size()
	if mine.get(&"engineer", []).is_empty():
		return &"engineer"
	if mine.get(&"wrecker", []).is_empty():
		return &"wrecker"
	if tanks < 3:
		return &"tank"
	if mine.get(&"nurse", []).is_empty():
		return &"nurse"
	if mine.get(&"hippy", []).is_empty() and tanks >= ai.attack_size - 1:
		return &"hippy"
	if mine.get(&"tanker", []).is_empty() and tanks >= 4:
		return &"tanker"
	if mine.get(&"boss", []).is_empty() and fuel > 600.0:
		return &"boss"
	return &"tank"

#endregion

#region Recovery and fuel

func _recover(mine: Dictionary) -> void:
	for wrecker in mine.get(&"wrecker", []):
		if session.linked(wrecker, TtwWinching) != null or session.linked(wrecker, TtwTowing) != null:
			continue
		var best: Entity = null
		var best_d := INF
		for kind in mine:
			for unit in mine[kind]:
				if unit == wrecker or not unit.has_component(TtwDrive):
					continue
				if not unit.has_component(TtwStuck) and not TtwWinchSystem.immobile(unit):
					continue
				var d := _at(unit).distance_to(_at(wrecker))
				if d < best_d:
					best = unit
					best_d = d
		if best == null:
			continue
		var reason := TtwWinchSystem.winch(session, wrecker, best)
		if reason == "Out of reach.":
			_send(wrecker, _at(best))
		elif reason.is_empty():
			TtwPilotSystem.stop(wrecker)

func _refuel(side: int, mine: Dictionary) -> void:
	for kind in mine:
		for unit in mine[kind]:
			var tank: TtwFuel = unit.get_component(TtwFuel)
			if tank == null or tank.level() > tank.capacity * LOW_FUEL:
				continue
			var depot := TtwPlacement.nearest_depot(session, _at(unit), side)
			if depot != null:
				session.unlink(unit, TtwAttacking)
				_send(unit, _at(depot) + Vector2(0, 2.0 * TtwTerrain.tile_px()))

#endregion

#region Expansion and capture

func _expand(ai: TtwAi, mine: Dictionary, fuel: float) -> void:
	var engineers: Array = mine.get(&"engineer", [])
	if engineers.is_empty():
		ai.building = &""
		return
	var engineer: Entity = engineers[0]
	var side := ai.team
	if ai.building.is_empty():
		var depots := _structures(side, TtwDepot)
		var kind := &""
		if depots.size() < 4 and fuel >= TtwProduction.STRUCTURES[&"depot"] + 120.0:
			kind = &"depot"
		elif _structures(side, TtwHelipad).is_empty() and fuel >= TtwProduction.STRUCTURES[&"helipad"] + 150.0:
			kind = &"helipad"
		if kind.is_empty() or depots.is_empty():
			return
		var site := find_site(session, kind, _at(depots[0]), side)
		if site.x < 0.0:
			return
		ai.building = kind
		ai.site = site
		ai.build_tries = 0
	var reach := TtwPlacement.engineer_reach() * TtwTerrain.tile_px()
	if _at(engineer).distance_to(ai.site) > reach * 0.8:
		_send(engineer, ai.site + Vector2(0, TtwPlacement.footprint(ai.building).y + TtwTerrain.tile_px()))
		ai.build_tries += 1
		if ai.build_tries > 40:
			ai.building = &""
		return
	var built: Entity = placer.call(ai.building, ai.site, side) if placer.is_valid() else null
	if built == null and not session.last_error.begins_with("Not enough fuel"):
		# The site went bad (something moved there): look for another.
		ai.building = &""
	elif built != null:
		ai.building = &""

## A clear site for `kind` near `anchor` for `side` (rings out to 8 tiles),
## or (-1, -1).
static func find_site(session: KitSession, kind: StringName, anchor: Vector2, side: int) -> Vector2:
	var half := TtwPlacement.footprint(kind)
	var tile := TtwTerrain.tile_px()
	for ring in range(3, 9):
		for k in 12:
			var at := anchor + Vector2.from_angle(TAU * k / 12.0) * ring * tile
			at = (at / tile).round() * tile
			if TtwPlacement.check(session, kind, at, side, half, true, false).is_empty() and not _crowded(session, at, half):
				return at
	return Vector2(-1, -1)

## Whether a footprint at `at` would sit on a structure or a unit.
static func _crowded(session: KitSession, at: Vector2, half: Vector2) -> bool:
	var area := Rect2(at - half, half * 2.0).grow(TtwTerrain.tile_px())
	for other in session.view([TtwStructure, KitBody]):
		var o: TtwObstacle = other.get_component(TtwObstacle)
		var b := session.body_of(other).position + o.offset
		if area.intersects(Rect2(b - o.half_extents, o.half_extents * 2.0)):
			return true
	return false

func _capture(ai: TtwAi, mine: Dictionary) -> void:
	var side := ai.team
	if not ai.capture_depot.is_empty():
		var depot := session.resolve(ai.capture_depot)
		var unit := session.resolve(ai.capturer)
		if depot == null or TtwTeam.of(depot) != TtwTeam.NEUTRAL or unit == null or unit.has_component(TtwWrecked):
			ai.capture_depot = ""
			ai.capturer = ""
		else:
			_send(unit, _at(depot) + Vector2(0, 2.0 * TtwTerrain.tile_px()))
			return
	var tanks: Array = mine.get(&"tank", [])
	if tanks.size() < 2:
		return
	var best: Entity = null
	var best_d := INF
	for depot in session.view([TtwDepot, TtwTeam, KitBody]):
		if TtwTeam.of(depot) != TtwTeam.NEUTRAL or depot.has_component(TtwDetonating):
			continue
		var d := _at(depot).distance_to(ai.home)
		if d < best_d:
			best = depot
			best_d = d
	if best == null:
		return
	var sent: Entity = null
	for tank in tanks:
		if session.linked(tank, TtwAttacking) == null:
			sent = tank
			break
	if sent == null:
		return
	ai.capture_depot = String(best.alias)
	ai.capturer = String(sent.alias)
	_send(sent, _at(best) + Vector2(0, 2.0 * TtwTerrain.tile_px()))

#endregion

#region The army

func _army(ai: TtwAi, mine: Dictionary) -> void:
	var side := ai.team
	var army: Array = []
	for kind in [&"tank", &"gunship"]:
		for unit in mine.get(kind, []):
			if String(unit.alias) != ai.capturer:
				army.append(unit)
	var tile := TtwTerrain.tile_px()
	# Defence first.
	var threat := _nearest_enemy(side, ai.home, ai.defend_tiles * tile)
	if threat != null:
		for unit in army:
			if session.linked(unit, TtwAttacking) == null:
				TtwGunSystem.attack(session, unit, threat)
		_support(ai, mine, army)
		return
	var tanks := army.filter(func(u): return u.has_component(TtwDrive))
	if ai.attacking:
		if tanks.size() < 2:
			# Beaten back: regroup, and the next wave is bigger.
			ai.attacking = false
			ai.wave += 1
			ai.attack_size = mini(ai.attack_size + 1, ai.max_attack_size)
			for unit in army:
				session.unlink(unit, TtwAttacking)
				TtwPilotSystem.order(unit, ai.rally)
		else:
			var target := session.resolve(ai.target) if not ai.target.is_empty() else null
			if target == null or not TtwCombat.alive(session, target):
				target = _enemy_structure(side, ai.home)
				ai.target = String(target.alias) if target != null else ""
			if target != null:
				for unit in army:
					if session.linked(unit, TtwAttacking) == null and not unit.has_component(TtwMoveOrder):
						TtwGunSystem.attack(session, unit, target)
	else:
		for unit in army:
			if session.linked(unit, TtwAttacking) == null:
				_send(unit, ai.rally)
		if tanks.size() >= ai.attack_size:
			var target := _enemy_structure(side, ai.home)
			if target != null:
				ai.attacking = true
				ai.target = String(target.alias)
				for unit in army:
					TtwGunSystem.attack(session, unit, target)
	_support(ai, mine, army)

## The nurse follows the army; the hippy smokes enemies that come near it.
func _support(ai: TtwAi, mine: Dictionary, army: Array) -> void:
	var middle := ai.rally
	if not army.is_empty():
		middle = Vector2.ZERO
		for unit in army:
			middle += _at(unit)
		middle /= army.size()
	for nurse in mine.get(&"nurse", []):
		_send(nurse, middle)
	for hippy in mine.get(&"hippy", []):
		var near := _nearest_enemy(ai.team, _at(hippy), 6.0 * TtwTerrain.tile_px())
		if near != null:
			TtwSpecialSystem.smoke(session, hippy, _at(near))
		else:
			_send(hippy, middle)

func _nearest_enemy(side: int, at: Vector2, reach: float) -> Entity:
	var best: Entity = null
	var best_d := reach
	for other in session.view([TtwUnit, TtwTeam, KitBody]):
		var team := TtwTeam.of(other)
		if team == side or team == TtwTeam.NEUTRAL or other.has_component(TtwWrecked):
			continue
		var d := _at(other).distance_to(at)
		if d <= best_d:
			best = other
			best_d = d
	return best

## The enemy structure to go for: the nearest garage, else the nearest.
func _enemy_structure(side: int, from: Vector2) -> Entity:
	var best: Entity = null
	var best_d := INF
	for other in session.view([TtwStructure, TtwTeam, KitBody]):
		var team := TtwTeam.of(other)
		if team == side or team == TtwTeam.NEUTRAL or not TtwCombat.alive(session, other):
			continue
		var d := _at(other).distance_to(from) - (100000.0 if other.has_component(TtwGarage) else 0.0)
		if d < best_d:
			best = other
			best_d = d
	return best

#endregion
