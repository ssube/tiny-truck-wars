class_name TtwGarageSystem extends System
## Garages and helipads: build the queue's first unit (TtwBuildQueue) once
## its fuel is taken from the supplying depot (or, when that one is short,
## another of the side's within reach that has it) (linked once, to the nearest depot of the side within
## SUPPLY_TILES), repair their side's ground vehicles nearby (a flooded engine
## is dried out once half its health is back), and break wrecks towed in up
## for fuel. Helipads serve their side's aircraft the same way.

signal produced(garage: Entity, unit: Entity)

const SERVICE_TICKS := 10
## How far a garage or helipad reaches for a depot to draw on (tiles).
const SUPPLY_TILES := 12.0
## A flooded engine runs again once repaired to this share.
const DRY_SHARE := 0.5

var session: KitSession
## Puts a unit on the map: func(kind, at, heading, team) -> Entity.
var spawner: Callable

func query() -> QueryBuilder:
	return q.with_all([TtwStructure, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var service := session.tick % SERVICE_TICKS == 0
	for entity in entities:
		var builds: TtwBuildQueue = entity.get_component(TtwBuildQueue)
		if builds != null:
			_build(entity, builds, delta)
		if entity.has_component(TtwGarage):
			if service:
				_repair(entity, entity.get_component(TtwGarage), delta * SERVICE_TICKS)
		elif entity.has_component(TtwHelipad) and service:
			_land(entity, entity.get_component(TtwHelipad), delta * SERVICE_TICKS)

## The depot `entity` draws on, linked if it was not.
func supply(entity: Entity) -> Entity:
	var depot := session.linked(entity, TtwSuppliedBy)
	if depot != null and not depot.has_component(TtwDetonating) and TtwTeam.of(depot) == TtwTeam.of(entity):
		return depot
	var reach := _reach(entity)
	depot = TtwPlacement.nearest_depot(session, session.body_of(entity).position, TtwTeam.of(entity), reach * TtwTerrain.tile_px())
	if depot != null:
		session.link(entity, TtwSuppliedBy, depot)
	else:
		session.unlink(entity, TtwSuppliedBy)
	return depot

## Adds `kind` to the queue of `structure`. Empty when done; otherwise why not.
static func enqueue(structure: Entity, kind: StringName) -> String:
	var g: TtwBuildQueue = structure.get_component(TtwBuildQueue)
	if g == null:
		return "That builds nothing."
	if not g.builds.has(kind) or not TtwProduction.UNITS.has(kind):
		var what: TtwStructure = structure.get_component(TtwStructure)
		return "A %s cannot build %s." % [what.kind if what != null else &"structure", kind]
	g.queue.append(kind)
	return ""

func _build(entity: Entity, g: TtwBuildQueue, delta: float) -> void:
	if g.queue.is_empty():
		g.status = ""
		return
	var kind := g.queue[0]
	if not g.paid:
		var depot := supply(entity)
		if depot == null:
			g.status = "No fuel depot within %d tiles." % int(_reach(entity))
			return
		var d: TtwDepot = depot.get_component(TtwDepot)
		var cost := TtwProduction.unit_fuel(kind)
		if d.level() < cost:
			# Another depot of the side in reach that has it, if any.
			var other := TtwPlacement.nearest_depot(session, session.body_of(entity).position, TtwTeam.of(entity), _reach(entity) * TtwTerrain.tile_px(), cost)
			if other == null:
				g.status = "Waiting for fuel (%d of %d)." % [int(d.level()), int(cost)]
				return
			session.link(entity, TtwSuppliedBy, other)
			d = other.get_component(TtwDepot)
		d.stock = d.level() - cost
		g.paid = true
		g.progress = 0.0
	g.status = ""
	g.progress += delta * build_rate(entity)
	if g.progress < TtwProduction.unit_seconds(kind) - 0.0001:
		return
	g.queue.pop_front()
	g.paid = false
	g.progress = 0.0
	if not spawner.is_valid():
		return
	var body := session.body_of(entity)
	var o: TtwObstacle = entity.get_component(TtwObstacle)
	# Vehicles drive out of the door; helicopters start on the pad.
	var door := body.position if entity.has_component(TtwHelipad) else body.position + Vector2(0, o.half_extents.y + TtwTerrain.tile_px())
	var unit: Entity = spawner.call(kind, door, PI / 2.0, TtwTeam.of(entity))
	if unit != null:
		if not entity.has_component(TtwHelipad):
			TtwPilotSystem.order(unit, door + Vector2(0, 2.0 * TtwTerrain.tile_px()))
		produced.emit(entity, unit)

## How fast a structure builds (seconds of progress per second): faster
## with a boss of its side near (the best one; bosses do not add up).
func build_rate(entity: Entity) -> float:
	var bosses := session.view([TtwBoss, KitBody])
	if bosses.is_empty():
		return 1.0
	var at := session.body_of(entity).position
	var side := TtwTeam.of(entity)
	var best := 0.0
	for boss in bosses:
		if TtwTeam.of(boss) != side or boss.has_component(TtwWrecked):
			continue
		var b: TtwBoss = boss.get_component(TtwBoss)
		if session.body_of(boss).position.distance_to(at) <= b.reach_tiles * TtwTerrain.tile_px():
			best = maxf(best, b.speedup)
	return 1.0 + best

func _reach(entity: Entity) -> float:
	if entity.has_component(TtwHelipad):
		return (entity.get_component(TtwHelipad) as TtwHelipad).depot_tiles
	return SUPPLY_TILES

func _repair(entity: Entity, g: TtwGarage, dt: float) -> void:
	var at := session.body_of(entity).position
	var reach := g.repair_tiles * TtwTerrain.tile_px()
	var side := TtwTeam.of(entity)
	var depot := supply(entity)
	for unit in session.view([TtwCondition, TtwVehicle, KitBody]).duplicate():
		if TtwTeam.of(unit) != side:
			continue
		var body := session.body_of(unit)
		if body == null or body.position.distance_to(at) > reach:
			continue
		if unit.has_component(TtwWrecked):
			# Broken up for fuel.
			if depot != null:
				var d: TtwDepot = depot.get_component(TtwDepot)
				var kind := TtwUnits.kind_of(unit)
				d.stock = minf(d.capacity, d.level() + TtwProduction.unit_fuel(kind) * TtwProduction.SCRAP_SHARE)
			session.retire(unit)
			continue
		var c: TtwCondition = unit.get_component(TtwCondition)
		var heal := minf(g.repair_rate * dt, c.max_health - c.current())
		if depot != null and g.repair_fuel > 0.0:
			var d: TtwDepot = depot.get_component(TtwDepot)
			heal = minf(heal, d.level() / g.repair_fuel)
			d.stock = d.level() - heal * g.repair_fuel
		elif g.repair_fuel > 0.0:
			heal = 0.0
		if heal > 0.0:
			c.health = c.current() + heal
		if unit.has_component(TtwFlooded) and c.share() >= DRY_SHARE:
			unit.remove_component(TtwFlooded)

func _land(entity: Entity, pad: TtwHelipad, dt: float) -> void:
	var depot := supply(entity)
	if depot == null:
		return
	var d: TtwDepot = depot.get_component(TtwDepot)
	var at := session.body_of(entity).position
	var side := TtwTeam.of(entity)
	for unit in session.view([TtwAircraft, KitBody]):
		if TtwTeam.of(unit) != side or session.body_of(unit).position.distance_to(at) > pad.service_tiles * TtwTerrain.tile_px():
			continue
		# Landed on it.
		if TtwCombat.flying(unit):
			continue
		var tank: TtwFuel = unit.get_component(TtwFuel)
		if tank != null:
			var give := minf(minf(pad.refuel_rate * dt, tank.capacity - tank.level()), d.level())
			tank.amount = tank.level() + give
			d.stock = d.level() - give
		var c: TtwCondition = unit.get_component(TtwCondition)
		if c != null:
			c.health = minf(c.max_health, c.current() + pad.repair_rate * dt)
