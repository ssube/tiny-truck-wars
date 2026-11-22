class_name TtwPlacement extends RefCounted
## Whether a structure may go somewhere, and the depot that pays for it or
## supplies it. Every rejection says why.

const SCENES := {
	&"garage": "res://prefabs/structure/garage.tscn",
	&"depot": "res://prefabs/structure/depot.tscn",
	&"helipad": "res://prefabs/structure/helipad.tscn",
}

## The depot of `team` nearest `at` within `reach_px` (any distance if INF),
## not about to explode; with at least `stock` fuel. Null if none.
static func nearest_depot(session: KitSession, at: Vector2, team: int, reach_px: float = INF, stock: float = 0.0) -> Entity:
	var best: Entity = null
	var best_d := reach_px
	for entity in session.view([TtwDepot, TtwTeam, KitBody]):
		if TtwTeam.of(entity) != team or entity.has_component(TtwDetonating):
			continue
		if (entity.get_component(TtwDepot) as TtwDepot).level() < stock:
			continue
		var d := session.body_of(entity).position.distance_to(at)
		if d <= best_d:
			best = entity
			best_d = d
	return best

## Why `kind` cannot be placed at `at` for `team` ("" if it can). `half` is
## the footprint's half size; `paid`: whether it costs fuel; `built`: whether
## an engineer of the side must be near to build it.
static func check(session: KitSession, kind: StringName, at: Vector2, team: int, half: Vector2, paid: bool = true, built: bool = true) -> String:
	if not SCENES.has(kind):
		return "Nothing called %s can be built." % kind
	var terrain := TtwGround.of(session)
	if terrain == null:
		return "There is no ground."
	var area := Rect2(at - half, half * 2.0)
	if not Rect2(Vector2.ZERO, terrain.size_px()).encloses(area):
		return "That is off the map."
	for garage in session.view([TtwGarage, TtwObstacle, KitBody]):
		if area.intersects(door_of(session, garage)):
			return "That would block a garage's door."
	var paths := TtwGround.paths_of(session)
	if paths != null:
		var lo := terrain.tile_of(area.position)
		var hi := terrain.tile_of(area.end - Vector2.ONE)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if not paths.is_open((Vector2(x, y) + Vector2(0.5, 0.5)) * terrain.tile_size_px):
					return "The ground there is not clear."
	if kind == &"helipad":
		var reach := helipad_reach()
		if nearest_depot(session, at, team, reach * TtwTerrain.tile_px()) == null:
			return "A helipad needs a fuel depot within %d tiles." % int(reach)
	if built and engineer_near(session, at, team) == null:
		return "An engineer must be within %d tiles." % int(engineer_reach())
	if paid and nearest_depot(session, at, team, INF, TtwProduction.STRUCTURES[kind]) == null:
		return "Not enough fuel: it costs %d." % int(TtwProduction.STRUCTURES[kind])
	return ""

## The ground in front of a garage's door that units come out onto and drive
## away over: its width, DOOR_TILES deep.
static func door_of(session: KitSession, garage: Entity) -> Rect2:
	var o: TtwObstacle = garage.get_component(TtwObstacle)
	var at := session.body_of(garage).position + o.offset
	var tile := TtwTerrain.tile_px()
	return Rect2(at + Vector2(-o.half_extents.x - tile, o.half_extents.y), Vector2(o.half_extents.x * 2.0 + 2.0 * tile, DOOR_TILES * tile))

const DOOR_TILES := 4.0

## The engineer of `team` nearest `at` within its build reach, or null.
static func engineer_near(session: KitSession, at: Vector2, team: int) -> Entity:
	var best: Entity = null
	var best_d := INF
	for entity in session.view([TtwEngineer, TtwTeam, KitBody]):
		if TtwTeam.of(entity) != team or entity.has_component(TtwWrecked):
			continue
		var e: TtwEngineer = entity.get_component(TtwEngineer)
		var d := session.body_of(entity).position.distance_to(at)
		if d <= e.build_tiles * TtwTerrain.tile_px() and d < best_d:
			best = entity
			best_d = d
	return best

## How near a site an engineer must be (tiles).
static func engineer_reach() -> float:
	return TtwEngineer.new().build_tiles

## How near a depot a helipad must be (tiles), as its prefab says.
static func helipad_reach() -> float:
	if _helipad_reach < 0.0:
		var scene: PackedScene = load(SCENES[&"helipad"])
		var pad: TtwStructure2D = scene.instantiate()
		_helipad_reach = pad.helipad.depot_tiles
		pad.free()
	return _helipad_reach

static var _helipad_reach: float = -1.0

## Half the footprint of a structure kind, as its prefab says (worked out once).
static func footprint(kind: StringName) -> Vector2:
	if not _footprints.has(kind):
		var body: TtwStructure2D = (load(SCENES[kind]) as PackedScene).instantiate()
		_footprints[kind] = body.obstacle.half_extents
		body.free()
	return _footprints[kind]

static var _footprints: Dictionary = {}
