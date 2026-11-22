extends RefCounted
## A bare game world for tests: a session with the game's systems, a ground of
## the test's own making, and units spawned from the real prefabs.

class TestWorld extends Node2D:
	var session: KitSession
	var terrain: TtwTerrain
	var units: Node2D
	var _count := 0

	func spawn(kind: StringName, at: Vector2, heading: float = 0.0, team: int = 1) -> Entity:
		_count += 1
		return TtwUnits.spawn(session, units, kind, at, heading, team, "unit:%d" % _count)

	## A structure of `kind` for `team`, unchecked and free.
	func structure(kind: StringName, at: Vector2, team: int = 1) -> Entity:
		var body: TtwStructure2D = (load(TtwPlacement.SCENES[kind]) as PackedScene).instantiate()
		body.position = at
		body.team = team
		units.add_child(body)
		_count += 1
		return session.bind_body(body, "structure:%d" % _count)

## A world on `terrain`, added under `parent`. Free it with queue_free().
static func make(parent: Node, terrain: TtwTerrain, with_water: bool = false, with_fire: bool = false) -> TestWorld:
	var world := TestWorld.new()
	world.session = KitSession.new()
	world.session.installer = TtwSystems.install
	world.add_child(world.session)
	world.units = Node2D.new()
	world.add_child(world.units)
	world.terrain = terrain
	parent.add_child(world)
	var map := Entity.new()
	map.alias = "map"
	var ground := TtwGround.new()
	ground.terrain = terrain
	if with_water:
		ground.water = TtwWater.new(terrain)
	if with_fire:
		ground.fire = TtwFireField.new(terrain.size_tiles)
	map.add_component(ground)
	world.session.register(map)
	(world.session.system(&"garages") as TtwGarageSystem).spawner = world.spawn
	return world

## A ground all of one material.
static func flat(tiles: Vector2i, material: int) -> TtwTerrain:
	var terrain := TtwTerrain.new(tiles)
	terrain.surface.fill(material)
	terrain.tiles_dirty = true
	return terrain
