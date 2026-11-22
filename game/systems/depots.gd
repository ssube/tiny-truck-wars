class_name TtwDepotSystem extends System
## Fuel depots: refill (faster in clusters, up to the cap), refuel their side's
## units nearby, fall to a side that holds them uncontested while neutral,
## and explode CHAIN_TICKS after they are destroyed. The blast grows with the
## fuel inside: its crater, burning fuel, and damage to everything in reach,
## so a depot it destroys goes up in turn, CHAIN_TICKS later again.

signal detonated(entity: Entity, at: Vector2, radius_px: float)
signal captured(entity: Entity, team: int)

## Refill, refuel and capture run every SERVICE_TICKS ticks.
const SERVICE_TICKS := 10
const CHAIN_TICKS := 20
## Blast radius (tiles) and damage: empty, and added when full.
const BLAST_TILES := 2.5
const BLAST_TILES_FULL := 4.5
const BLAST_DAMAGE := 120.0
const BLAST_DAMAGE_FULL := 380.0
## Fuel left burning on each tile under the blast, per unit of fuel share.
const FIRE_FUEL := 40.0
const CAPTURE_SECONDS := 5.0

var session: KitSession
var _served_tick: int = -1

func query() -> QueryBuilder:
	return q.with_all([TtwDepot, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for depot in entities.duplicate():
		var fuse: TtwDetonating = depot.get_component(TtwDetonating)
		if fuse != null and session.tick >= fuse.at_tick:
			detonate(depot)
	# process() runs once per archetype of depots (one about to explode is
	# another): the service is once a tick.
	if session.tick % SERVICE_TICKS != 0 or _served_tick == session.tick:
		return
	_served_tick = session.tick
	var dt := delta * SERVICE_TICKS
	var units := session.view([TtwFuel, KitBody])
	for depot in session.view([TtwDepot, KitBody]):
		if depot.has_component(TtwDetonating):
			continue
		var d: TtwDepot = depot.get_component(TtwDepot)
		var body := session.body_of(depot)
		d.stock = minf(d.capacity, d.level() + refill_rate(depot) * dt)
		_serve(depot, d, body.position, units, dt)

## Fuel per second now: the base rate times the cluster bonus, capped.
func refill_rate(depot: Entity) -> float:
	var d: TtwDepot = depot.get_component(TtwDepot)
	var body := session.body_of(depot)
	var near: int = body.call("neighbours") if body != null and body.has_method("neighbours") else 0
	return d.refill * cluster_factor(d, near)

static func cluster_factor(d: TtwDepot, neighbours: int) -> float:
	return minf(d.cluster_cap, 1.0 + d.cluster_bonus * neighbours)

static func blast_radius_px(d: TtwDepot) -> float:
	return (BLAST_TILES + BLAST_TILES_FULL * clampf(d.share(), 0.0, 1.0)) * TtwTerrain.tile_px()

static func blast_damage(d: TtwDepot) -> float:
	return BLAST_DAMAGE + BLAST_DAMAGE_FULL * clampf(d.share(), 0.0, 1.0)

func _serve(depot: Entity, d: TtwDepot, at: Vector2, units: Array, dt: float) -> void:
	var side := TtwTeam.of(depot)
	var reach := d.refuel_tiles * TtwTerrain.tile_px()
	var present := {}
	for unit in units:
		if unit.has_component(TtwWrecked):
			continue
		var body := session.body_of(unit)
		if body == null or body.position.distance_to(at) > reach:
			continue
		var unit_side := TtwTeam.of(unit)
		present[unit_side] = true
		if unit_side != side or side == TtwTeam.NEUTRAL:
			continue
		var tank: TtwFuel = unit.get_component(TtwFuel)
		var give := minf(minf(d.refuel_rate * dt, tank.capacity - tank.level()), d.level())
		if give > 0.0:
			tank.amount = tank.level() + give
			d.stock = d.level() - give
		# A Tanker's cargo is filled too.
		var cargo: TtwTanker = unit.get_component(TtwTanker)
		if cargo != null:
			var load := minf(minf(d.refuel_rate * dt, cargo.cargo_capacity - cargo.level()), d.level())
			if load > 0.0:
				cargo.cargo = cargo.level() + load
				d.stock = d.level() - load
	if side != TtwTeam.NEUTRAL:
		return
	present.erase(TtwTeam.NEUTRAL)
	if present.size() == 1:
		var holder: int = present.keys()[0]
		if holder != d.capture_team:
			d.capture_team = holder
			d.capture = 0.0
		d.capture += dt
		if d.capture >= CAPTURE_SECONDS - 0.0001:
			(depot.get_component(TtwTeam) as TtwTeam).team = holder
			d.capture = 0.0
			var body := session.body_of(depot)
			if body != null:
				body.queue_redraw()
			captured.emit(depot, holder)
	else:
		d.capture = 0.0

## The depot explodes now.
func detonate(depot: Entity) -> void:
	var body := session.body_of(depot)
	if body == null:
		return
	var d: TtwDepot = depot.get_component(TtwDepot)
	var at := body.position
	var radius := blast_radius_px(d)
	var damage := blast_damage(d)
	var share := clampf(d.share(), 0.0, 1.0)
	depot.remove_component(TtwDetonating)
	var h: TtwHealth = depot.get_component(TtwHealth)
	if h != null:
		h.destroyed = true
	var terrain := TtwGround.of(session)
	if terrain != null:
		TtwSnow.blast(terrain, at, radius * 0.5)
	var field := TtwGround.fire_of(session)
	if field != null and terrain != null:
		var lo := terrain.tile_of(at - Vector2(radius, radius) * 0.5)
		var hi := terrain.tile_of(at + Vector2(radius, radius) * 0.5)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				field.add_fuel(Vector2i(x, y), FIRE_FUEL * share)
				field.ignite(Vector2i(x, y), 0.8)
	d.stock = 0.0
	detonated.emit(depot, at, radius)
	if body.has_method("collapse"):
		body.call("collapse", &"depot")
	else:
		session.retire(depot)
	TtwDamage.blast(session, at, radius, damage)
