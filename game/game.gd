class_name TtwGame extends Node
## The running game: one session, the map's ground and what is on it.

const MAP_ALIAS := "map"
const PROP_SCENES := {
	&"tree_oak": "res://prefabs/world/tree_oak.tscn",
	&"tree_oak_b": "res://prefabs/world/tree_oak_b.tscn",
	&"tree_pine": "res://prefabs/world/tree_pine.tscn",
	&"log": "res://prefabs/world/log.tscn",
	&"house": "res://prefabs/world/house.tscn",
	&"house_b": "res://prefabs/world/house_b.tscn",
	&"house_c": "res://prefabs/world/house_c.tscn",
	&"house_d": "res://prefabs/world/house_d.tscn",
	&"shed": "res://prefabs/world/shed.tscn",
	&"barracks": "res://prefabs/world/barracks.tscn",
}
const UNIT_SCENES := TtwUnits.SCENES

## Which generated map to start on: &"mud_lab" or &"skirmish".
@export var map_kind: StringName = &"mud_lab"
## The skirmish map (TtwMaps), when map_kind is &"skirmish".
@export var map_name: StringName = &"river"
## A saved game to start from instead (TtwSave), or empty.
var load_path: String = ""
var session: KitSession
var terrain: TtwTerrain
var world_root: Node2D
var view: TtwTerrainView
var water: TtwWater:
	get:
		return TtwGround.water_of(session)
var units: Node2D
var water_fx: TtwWaterFx
var fx: TtwFx
var camera: Camera2D
var _spawned: int = 0
var _props: int = 0

func _init() -> void:
	name = "Game"
	add_to_group(&"ttw_game")
	session = KitSession.new()
	session.installer = TtwSystems.install

func _ready() -> void:
	add_child(session)
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	view = TtwTerrainView.new()
	view.name = "Terrain"
	world_root.add_child(view)
	var ground_fx := Node2D.new()
	ground_fx.name = "GroundFx"
	world_root.add_child(ground_fx)
	units = Node2D.new()
	units.name = "Units"
	units.y_sort_enabled = true
	world_root.add_child(units)
	var air_fx := Node2D.new()
	air_fx.name = "AirFx"
	world_root.add_child(air_fx)
	var cables := TtwCables.new()
	cables.name = "Cables"
	cables.session = session
	air_fx.add_child(cables)
	water_fx = TtwWaterFx.new()
	add_child(water_fx)
	fx = TtwFx.new()
	add_child(fx)
	fx.bind(ground_fx, air_fx, water_fx)
	(session.system(&"wakes") as TtwWakeSystem).fx = water_fx
	(session.system(&"effects") as TtwEffectsSystem).fx = fx
	(session.system(&"fire") as TtwFireSystem).fx = fx
	(session.system(&"garages") as TtwGarageSystem).spawner = spawn_unit
	(session.system(&"ballistics") as TtwBallisticsSystem).fx = fx
	(session.system(&"kits") as TtwKitSystem).fx = fx
	(session.system(&"specials") as TtwSpecialSystem).fx = fx
	var shells := TtwShellsView.new()
	shells.session = session
	air_fx.add_child(shells)
	(session.system(&"guns") as TtwGunSystem).fired.connect(func(shooter: Entity, _shell: Entity):
		var body := session.body_of(shooter)
		if body != null:
			fx.puffs.puff(TtwPuffs.Kind.EXHAUST, body.position + Vector2(0, -6), Vector2(0, -8), 2, 0.9))
	var drive: TtwDriveSystem = session.system(&"drive")
	drive.destroyed.connect(func(entity: Entity):
		var body := session.body_of(entity)
		if body != null:
			fx.explode(body.position, &"vehicle")
			# The wreck burns.
			var field := TtwGround.fire_of(session)
			if field != null:
				field.add_fuel(terrain.tile_of(body.position), TtwFireSystem.WRECK_FUEL)
				field.ignite(terrain.tile_of(body.position)))
	camera = Camera2D.new()
	# The whole zoom that shows about what zoom 3 does at 1280×720 (TtwZoom).
	camera.zoom = Vector2.ONE * TtwZoom.start(get_viewport().get_visible_rect().size)
	world_root.add_child(camera)
	(session.system(&"ai") as TtwAiSystem).placer = place_structure
	if not load_path.is_empty():
		var error := TtwSave.restore(self, load_path)
		if error.is_empty():
			return
		push_warning("Could not load %s: %s" % [load_path, error])
	if map_kind == &"skirmish":
		TtwMaps.build(self, map_name)
		return
	load_ground(TtwMapGen.mud_lab())
	for prop in TtwMapGen.mud_lab_props(terrain.size_tiles):
		spawn_prop(prop.kind, prop.at, prop.get("angle", 0.0))

## Puts a ground in play: the map entity carries it, the view draws it.
func load_ground(value: TtwTerrain) -> void:
	terrain = value
	var map := session.resolve(MAP_ALIAS)
	if map == null:
		map = Entity.new()
		map.alias = MAP_ALIAS
		map.add_component(TtwGround.new())
		map.add_component(TtwWeather.new())
		session.register(map)
	var ground: TtwGround = map.get_component(TtwGround)
	ground.terrain = terrain
	ground.water = TtwWater.new(terrain)
	ground.fire = TtwFireField.new(terrain.size_tiles)
	view.water_sim = ground.water
	view.show_terrain(terrain)
	water_fx.show_terrain(terrain, view)
	fx.show_terrain(terrain)
	fx.weather = map.get_component(TtwWeather)
	fx.view = view
	if fx.precipitation == null:
		fx.precipitation = TtwPrecipitation.new()
		fx.precipitation.name = "Precipitation"
		fx.air.add_child(fx.precipitation)
	fx.precipitation.weather = fx.weather
	fx.precipitation.camera = camera
	camera.position = terrain.size_px() * 0.5

## Puts a unit of `kind` (a chassis or a kit: TtwUnits) on the map. Null,
## with session.last_error, if it cannot.
func spawn_unit(kind: StringName, position: Vector2, heading: float = 0.0, team: int = 1) -> Entity:
	_spawned += 1
	return TtwUnits.spawn(session, units, kind, position, heading, team, "unit:%s:%d" % [kind, _spawned])

## Puts a structure of `kind` (TtwPlacement.SCENES) for `team` at `position`,
## with no checks and no cost (maps; place_structure checks and pays).
func spawn_structure(kind: StringName, position: Vector2, team: int, facing: String = "south") -> Entity:
	if not TtwPlacement.SCENES.has(kind):
		session.last_error = "No structure kind %s." % kind
		return null
	var body: TtwStructure2D = (load(TtwPlacement.SCENES[kind]) as PackedScene).instantiate()
	body.position = position
	body.team = team
	body.facing = facing
	units.add_child(body)
	_props += 1
	var entity := session.bind_body(body, "structure:%s:%d" % [kind, _props])
	if entity == null:
		body.queue_free()
	return entity

## Builds a structure of `kind` for `team` at `position` if the rules allow
## (TtwPlacement), paying its fuel from the side's depots (all of them
## together; the nearest first). Null, with session.last_error saying why, if not.
func place_structure(kind: StringName, position: Vector2, team: int) -> Entity:
	var reason := TtwPlacement.check(session, kind, position, team, footprint_of(kind))
	if not reason.is_empty():
		session.last_error = reason
		return null
	TtwPlacement.draw_fuel(session, team, TtwProduction.STRUCTURES[kind], position)
	var entity := spawn_structure(kind, position, team)
	# A new depot starts empty: fuel is not made by building tanks for it.
	if entity != null and entity.has_component(TtwDepot):
		(entity.get_component(TtwDepot) as TtwDepot).stock = 0.0
	if entity != null and kind == &"helipad":
		(session.system(&"garages") as TtwGarageSystem).supply(entity)
	return entity

## Half the footprint of a structure kind, as its prefab says.
func footprint_of(kind: StringName) -> Vector2:
	return TtwPlacement.footprint(kind)

## Puts a world object of `kind` (PROP_SCENES) on the map, turned `angle`.
func spawn_prop(kind: StringName, position: Vector2, angle: float = 0.0) -> Entity:
	if not PROP_SCENES.has(kind):
		session.last_error = "No prop kind %s." % kind
		return null
	var body: Node2D = (load(PROP_SCENES[kind]) as PackedScene).instantiate()
	body.position = position
	body.rotation = angle
	if kind == &"log":
		body.rotation = angle
	units.add_child(body)
	_props += 1
	var entity := session.bind_body(body, "prop:%s:%d" % [kind, _props])
	if entity == null:
		body.queue_free()
	return entity

## An explosion of `cause` (TtwStamps.CRATERS) at `at`: its crater, its look,
## its damage to everything in reach, and fire where there is fuel.
func explode(at: Vector2, cause: StringName) -> void:
	var size: Vector2 = TtwStamps.CRATERS.get(cause, TtwStamps.CRATERS[&"shell"])
	TtwCombat.burst(session, fx, at, cause, size.x * 4.0, size.y * 30.0)
	var field := TtwGround.fire_of(session)
	if field != null:
		var tile := terrain.tile_of(at)
		for y in range(-1, 2):
			for x in range(-1, 2):
				field.ignite(tile + Vector2i(x, y), 0.7)

## Water poured at `at` (a tanker's spray, a bucket's drop): TtwSpray.pour.
func pour(at: Vector2, volume: float, radius_px: float) -> void:
	TtwSpray.pour(session, fx, at, volume, radius_px)
