class_name TtwKitSystem extends System
## What the truck kits and the helicopter bucket do each tick:
## - Tanker: fills its cargo at its side's depots (TtwDepotSystem), gives fuel
##   to its side's units near it (ground ones, and aircraft on the ground).
## - Engineer: while paving, lays gravel on each tile it drives onto, filling
##   the ruts and clearing loose mud, for fuel.
## - Water tanker: pumps from water near it; on a spray order drives within
##   reach and sprays the spot until empty.
## - Bucket: dips low over water to fill; on a drop order flies to the spot
##   and lets it all go.

signal sprayed(entity: Entity, at: Vector2, volume: float)
signal dropped(entity: Entity, at: Vector2, volume: float)

const SERVICE_TICKS := 10
## Within this of a drop spot (px) the bucket lets go.
const DROP_PX := 8.0
## How high an aircraft can be and still take fuel from a tanker (px).
const TANKER_AIR_PX := 1.0

var session: KitSession
var fx: TtwFx

## The map's entity: one call a tick (a query matching several archetypes
## would call process() once for each).
func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(_entities: Array[Entity], _components: Array, delta: float) -> void:
	if session.tick % SERVICE_TICKS == 0:
		for tanker in session.view([TtwTanker, KitBody]):
			_serve(tanker, delta * SERVICE_TICKS)
	for engineer in session.view([TtwEngineer, TtwDrive, KitBody]):
		_pave(engineer)
	for truck in session.view([TtwWaterTank, KitBody]).duplicate():
		_water_tanker(truck, delta)
	for heli in session.view([TtwBucket, TtwFlight, KitBody]).duplicate():
		_bucket(heli, delta)

#region Orders

## Orders a Water tanker to spray `target`. Empty when done; otherwise why not.
static func spray(entity: Entity, target: Vector2) -> String:
	var tank: TtwWaterTank = entity.get_component(TtwWaterTank)
	if tank == null:
		return "It carries no water."
	if tank.amount <= 0.0:
		return "Its tank is empty: drive it to water to pump."
	var o: TtwSprayOrder = entity.get_component(TtwSprayOrder)
	if o == null:
		o = TtwSprayOrder.new()
		entity.add_component(o)
	o.target = target
	o.driving = false
	return ""

## Orders a bucket helicopter to drop on `target`. Empty when done; otherwise why not.
static func drop(entity: Entity, target: Vector2) -> String:
	var bucket: TtwBucket = entity.get_component(TtwBucket)
	if bucket == null:
		return "It has no bucket."
	if bucket.amount <= 0.0:
		return "Its bucket is empty: hover it over water to fill."
	var o: TtwDropOrder = entity.get_component(TtwDropOrder)
	if o == null:
		o = TtwDropOrder.new()
		entity.add_component(o)
	o.target = target
	TtwPilotSystem.order(entity, target)
	return ""

## Starts or stops an engineer laying road.
static func set_paving(entity: Entity, on: bool) -> void:
	var e: TtwEngineer = entity.get_component(TtwEngineer)
	if e != null:
		e.paving = on
		e.last_tile = -1

#endregion

func _serve(tanker: Entity, dt: float) -> void:
	if tanker.has_component(TtwWrecked):
		return
	var t: TtwTanker = tanker.get_component(TtwTanker)
	var at := session.body_of(tanker).position
	var side := TtwTeam.of(tanker)
	var reach := t.reach_tiles * TtwTerrain.tile_px()
	for unit in session.view([TtwFuel, TtwTeam, KitBody]):
		if unit == tanker or TtwTeam.of(unit) != side or unit.has_component(TtwWrecked):
			continue
		var f: TtwFlight = unit.get_component(TtwFlight)
		if f != null and f.altitude > TANKER_AIR_PX:
			continue
		if session.body_of(unit).position.distance_to(at) > reach:
			continue
		var tank: TtwFuel = unit.get_component(TtwFuel)
		var give := minf(minf(t.rate * dt, tank.capacity - tank.level()), t.level())
		if give > 0.0:
			tank.amount = tank.level() + give
			t.cargo = t.level() - give

func _pave(entity: Entity) -> void:
	var e: TtwEngineer = entity.get_component(TtwEngineer)
	if not e.paving or entity.has_component(TtwWrecked):
		return
	var d: TtwDrive = entity.get_component(TtwDrive)
	if absf(d.speed) < 1.0:
		return
	var terrain := TtwGround.of(session)
	var at := session.body_of(entity).position
	var tile := terrain.tile_of(at)
	if not terrain.has_tile(tile):
		return
	var i := terrain.tile_index(tile)
	if i == e.last_tile:
		return
	e.last_tile = i
	var material := terrain.material_at_tile(tile)
	if material == TtwMaterials.PAVEMENT or material == TtwMaterials.GRAVEL:
		return
	var fuel: TtwFuel = entity.get_component(TtwFuel)
	if fuel != null:
		if fuel.level() < e.pave_fuel:
			e.paving = false
			session.notify("The engineer is out of fuel for road.")
			return
		fuel.amount = fuel.level() - e.pave_fuel
	lay_road(terrain, tile)

## Gravel on `tile`: its ruts filled, loose mud cleared, the wear gone.
static func lay_road(terrain: TtwTerrain, tile: Vector2i) -> void:
	terrain.set_material(tile, TtwMaterials.GRAVEL)
	var n := TtwTerrain.CELLS_PER_TILE
	for cy in range(tile.y * n, (tile.y + 1) * n):
		for cx in range(tile.x * n, (tile.x + 1) * n):
			var ci := cy * terrain.size_cells.x + cx
			terrain.deform[ci] = maxf(terrain.deform[ci], 0.0)
			terrain.loose[ci] = 0.0
			terrain.wear[ci] = 0.0
	terrain.mark_cells(Rect2i(tile * n, Vector2i(n, n)))

func _water_tanker(entity: Entity, delta: float) -> void:
	if entity.has_component(TtwWrecked):
		return
	var tank: TtwWaterTank = entity.get_component(TtwWaterTank)
	var at := session.body_of(entity).position
	var o: TtwSprayOrder = entity.get_component(TtwSprayOrder)
	if o == null:
		if tank.amount < tank.capacity:
			var water := TtwGround.water_of(session)
			if water != null:
				tank.amount += water.draw(at, minf(tank.pump_rate * delta, tank.capacity - tank.amount), tank.pump_reach_px)
		return
	var reach := tank.spray_tiles * TtwTerrain.tile_px()
	if at.distance_to(o.target) > reach:
		if entity.has_component(TtwMoveOrder):
			return
		if o.driving:
			# It got as near as the ground lets it, and that is not near enough.
			entity.remove_component(TtwSprayOrder)
			session.notify("The water tanker cannot get within reach.")
			return
		o.driving = true
		TtwPilotSystem.order(entity, o.target)
		return
	if entity.has_component(TtwMoveOrder):
		TtwPilotSystem.stop(entity)
	var volume := minf(tank.spray_rate * delta, tank.amount)
	# Swept across the spot, a cone's width.
	var across := (o.target - at).normalized().orthogonal() * sin(session.tick * 0.2) * tank.spray_px * 0.6
	var spot := o.target + across
	TtwSpray.pour(session, null, spot, volume, tank.spray_px)
	tank.amount -= volume
	if fx != null and session.tick % 3 == 0:
		fx.debris.throw(TtwDebris.Kind.DROPLET, Vector3(at.x, at.y, 6.0), (spot - at).normalized(), at.distance_to(spot) * 1.2, 0.25, 40.0, 3)
		if session.tick % 12 == 0:
			fx.water.splash(spot, tank.spray_px, 0.4, 0.05, 0.8)
	sprayed.emit(entity, spot, volume)
	if tank.amount <= 0.0:
		tank.amount = 0.0
		entity.remove_component(TtwSprayOrder)

func _bucket(entity: Entity, delta: float) -> void:
	if entity.has_component(TtwWrecked):
		return
	var b: TtwBucket = entity.get_component(TtwBucket)
	var f: TtwFlight = entity.get_component(TtwFlight)
	var at := session.body_of(entity).position
	var o: TtwDropOrder = entity.get_component(TtwDropOrder)
	if o != null:
		if at.distance_to(o.target) <= DROP_PX and f.airborne():
			var volume := b.amount
			b.amount = 0.0
			entity.remove_component(TtwDropOrder)
			TtwSpray.pour(session, fx, o.target, volume, b.drop_px)
			dropped.emit(entity, o.target, volume)
		elif not entity.has_component(TtwMoveOrder):
			TtwPilotSystem.order(entity, o.target)
		return
	if b.amount >= b.capacity or entity.has_component(TtwMoveOrder):
		return
	var terrain := TtwGround.of(session)
	var water := TtwGround.water_of(session)
	if terrain == null or water == null or terrain.water_depth_at(at) < b.min_depth_px:
		return
	f.hold_px = b.dip_px
	if f.altitude <= b.dip_px + 0.5:
		b.amount += water.draw(at, minf(b.fill_rate * delta, b.capacity - b.amount), TtwTerrain.tile_px())
