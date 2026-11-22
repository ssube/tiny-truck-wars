class_name TtwCrowdSystem extends System
## Tells the path grid where vehicles stand (TtwPathGrid.set_crowd) every
## EVERY_TICKS: wrecks, stuck or stranded vehicles, and idle ones (no order,
## barely moving). Each covers the tiles its circle, with a vehicle's
## clearance, reaches. Moving vehicles are not counted: they will be gone.

const EVERY_TICKS := 30
const IDLE_SPEED := 2.0

var session: KitSession

## The map's entity: one call a tick.
func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	if session.tick % EVERY_TICKS != 0:
		return
	var paths := TtwGround.paths_of(session)
	if paths == null:
		return
	paths.set_crowd(standing(session, paths.terrain))

## Tile index -> how many standing vehicles cover it.
static func standing(session: KitSession, terrain: TtwTerrain) -> Dictionary:
	var counts := {}
	var tile := terrain.tile_size_px
	for entity in session.view([TtwVehicle, TtwDrive, KitBody]):
		var body := session.body_of(entity)
		if body == null:
			continue
		var d: TtwDrive = entity.get_component(TtwDrive)
		var stands: bool = entity.has_component(TtwWrecked) or entity.has_component(TtwStuck) or TtwWinchSystem.immobile(entity)
		if not stands and not entity.has_component(TtwMoveOrder) and absf(d.speed) < IDLE_SPEED:
			stands = true
		if not stands:
			continue
		var reach := TtwSeparationSystem.radius_of(entity.get_component(TtwVehicle)) + TtwPathGrid.OBSTACLE_GROW
		var lo := terrain.tile_of(body.position - Vector2(reach, reach))
		var hi := terrain.tile_of(body.position + Vector2(reach, reach))
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var t := Vector2i(x, y)
				if not terrain.has_tile(t):
					continue
				if ((Vector2(t) + Vector2(0.5, 0.5)) * tile).distance_to(body.position) <= reach:
					var i := terrain.tile_index(t)
					counts[i] = counts.get(i, 0) + 1
	return counts
