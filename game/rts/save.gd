class_name TtwSave extends RefCounted
## Saving and loading a game: everything the simulation reads, so a loaded
## game goes on as the saved one would have.
## - The ground: every layer of the terrain, the water (depths, fluxes, the
##   slick, what the ground took in, the books), the fire field and the
##   settling queue.
## - Every entity but the session's own: its alias, its body's scene and
##   place (a structure's side and facing), each component's fields (script
##   variables of plain types) and its links (by the target's alias). Shots,
##   smoke clouds and the computer opponents are entities too.
## - The map's weather and match, the tick, and rubble left where buildings
##   fell. (Paths are worked out again from the ground on the first tick.)
## Written as one Variant, ZSTD-compressed.

const VERSION := 1
const LAYERS := ["surface", "elevation", "water", "flow", "snow_base", "water_color", "deform", "loose", "wet", "track", "track_angle", "wear", "scorch", "oil", "snow_gone"]
const WATER_ARRAYS := ["depth", "slick", "flux_w", "flux_e", "flux_n", "flux_s", "absorbed", "_soaked"]
const WATER_BOOKS := ["added", "drained", "poured", "drawn", "infiltrated", "slick_total", "slick_drained"]
const PLAIN := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I,
	TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_COLOR, TYPE_ARRAY, TYPE_DICTIONARY,
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_COLOR_ARRAY]
const RUBBLE_GROUP := &"ttw_rubble"

## Saves `game` to `path`. Empty when done; otherwise why not.
static func save(game: TtwGame, path: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_var(capture(game))
	file.close()
	return ""

## Reads a save. Empty dictionary, with `error` set, if it cannot.
static func read(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {"error": "Cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())]}
	var data: Variant = file.get_var()
	file.close()
	if not data is Dictionary or data.get("version", -1) != VERSION:
		return {"error": "%s is not a save this game can read." % path}
	return data

#region Saving

## The whole game as one dictionary.
static func capture(game: TtwGame) -> Dictionary:
	var session := game.session
	var t := game.terrain
	var layers := {}
	for name in LAYERS:
		layers[name] = t.get(name).duplicate()
	var data := {
		"version": VERSION,
		"map_kind": game.map_kind,
		"map_name": game.map_name,
		"tick": session.tick,
		"spawned": game.get("_spawned"),
		"props": game.get("_props"),
		"terrain": {
			"size": t.size_tiles,
			"layers": layers,
			"snow_level": t.snow_level,
			"sources": t.water_sources.duplicate(true),
			"sinks": t.water_sinks.duplicate(true),
			"settling": t.settling.duplicate(),
		},
	}
	var water := TtwGround.water_of(session)
	if water != null:
		var w := {}
		for name in WATER_ARRAYS + WATER_BOOKS:
			var value: Variant = water.get(name)
			w[name] = value.duplicate() if value is PackedFloat32Array or value is PackedByteArray else value
		data["water"] = w
	var fire := TtwGround.fire_of(session)
	if fire != null:
		data["fire"] = {"fuel": fire.fuel.duplicate(), "heat": fire.heat.duplicate(), "exposure": fire.exposure.duplicate(), "burning": fire.burning.duplicate()}
	var map := session.resolve(TtwGame.MAP_ALIAS)
	data["map"] = _components(map, [TtwGround])
	var entities: Array = []
	for entity in session.world.entities:
		if entity == map or entity.has_component(KitPersistent):
			continue
		entities.append(_entity(session, entity))
	data["entities"] = entities
	var rubble: Array = []
	for heap in game.get_tree().get_nodes_in_group(RUBBLE_GROUP):
		if game.is_ancestor_of(heap):
			rubble.append({"at": (heap as Node2D).position, "scale": (heap as Node2D).scale})
	data["rubble"] = rubble
	return data

static func _entity(session: KitSession, entity: Entity) -> Dictionary:
	var out := {"alias": String(entity.alias), "components": _components(entity, [KitBody]), "links": []}
	var body := session.body_of(entity)
	if body != null:
		var node := {"scene": body.scene_file_path, "position": body.position, "rotation": body.rotation}
		if body is TtwStructure2D:
			node["team"] = (body as TtwStructure2D).team
			node["facing"] = (body as TtwStructure2D).facing
		out["body"] = node
	for link in entity.relationships:
		if link.target is Entity and is_instance_valid(link.target):
			out["links"].append({"relation": link.relation.get_script().resource_path, "target": String((link.target as Entity).alias)})
	return out

## Each component's script and plain fields, except the kinds in `skip`.
static func _components(entity: Entity, skip: Array) -> Array:
	var out: Array = []
	for component in entity.components.values():
		if skip.any(func(kind): return is_instance_of(component, kind)):
			continue
		out.append({"script": component.get_script().resource_path, "fields": fields_of(component)})
	return out

## The plain script variables of `object`.
static func fields_of(object: Object) -> Dictionary:
	var out := {}
	for property in object.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value: Variant = object.get(property.name)
		if typeof(value) in PLAIN:
			out[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	return out

#endregion

#region Loading

## Loads the save at `path` into a fresh `game` (in place of its map).
## Empty when done; otherwise why not.
static func restore(game: TtwGame, path: String) -> String:
	var data := read(path)
	if data.has("error"):
		return data.error
	apply(game, data)
	return ""

static func apply(game: TtwGame, data: Dictionary) -> void:
	var session := game.session
	game.map_kind = data.map_kind
	game.map_name = data.map_name
	session.tick = data.tick
	var saved: Dictionary = data.terrain
	var t := TtwTerrain.new(saved.size)
	# Copies: packed arrays are shared, and loading writes into the terrain's.
	for name in LAYERS:
		# A save from before a layer existed keeps the new terrain's default.
		if saved.layers.has(name):
			t.set(name, saved.layers[name].duplicate())
	t.snow_level = saved.snow_level
	t.water_sources.assign(saved.sources)
	t.water_sinks.assign(saved.sinks)
	t.mark_all()
	game.load_ground(t)
	var water := TtwGround.water_of(session)
	if water != null and data.has("water"):
		for name in data.water:
			water.set(name, data.water[name])
		water.find_wet()
	# Making the water soaked the ground it found and queued it to settle:
	# the saved layers and queue are the truth.
	for name in LAYERS:
		# A save from before a layer existed keeps the new terrain's default.
		if saved.layers.has(name):
			t.set(name, saved.layers[name].duplicate())
	for i in t.settling:
		t.unqueue_settle(i)
	t.set_settling(PackedInt32Array())
	t.queue_settle_cells(saved.settling)
	t.mark_all()
	var fire := TtwGround.fire_of(session)
	if fire != null and data.has("fire"):
		fire.restore(data.fire.fuel, data.fire.heat, data.fire.exposure, data.fire.burning)
	_reconcile(session.resolve(TtwGame.MAP_ALIAS), data.map, [TtwGround])
	var made := {}
	for record in data.entities:
		var entity := _make(game, record)
		if entity != null:
			made[record.alias] = entity
	for record in data.entities:
		var entity: Entity = made.get(record.alias)
		if entity == null:
			continue
		for link in record.links:
			var target := session.resolve(link.target)
			if target != null:
				session.link(entity, load(link.relation), target)
	for heap in data.rubble:
		var sprite := Sprite2D.new()
		sprite.texture = TtwStructure2D.RUBBLE
		sprite.position = heap.at
		sprite.scale = heap.scale
		sprite.add_to_group(RUBBLE_GROUP)
		game.units.add_child(sprite)
	game.set("_spawned", data.spawned)
	game.set("_props", data.props)

static func _make(game: TtwGame, record: Dictionary) -> Entity:
	var session := game.session
	if not record.has("body"):
		var entity := Entity.new()
		entity.alias = record.alias
		_reconcile(entity, record.components, [])
		if not session.register(entity):
			entity.free()
			return null
		return entity
	var node: Dictionary = record.body
	var body: Node2D = (load(node.scene) as PackedScene).instantiate()
	body.position = node.position
	body.rotation = node.rotation
	if body is TtwStructure2D:
		(body as TtwStructure2D).team = node.team
		(body as TtwStructure2D).facing = node.facing
	game.units.add_child(body)
	var entity := session.bind_body(body, record.alias)
	if entity == null:
		body.queue_free()
		return null
	_reconcile(entity, record.components, [KitBody])
	var h: TtwHealth = entity.get_component(TtwHealth)
	if h != null and h.current() < h.max_health and body.has_method("hurt"):
		body.call("hurt", h.current() / h.max_health)
	return entity

## Makes `entity`'s components those `saved`: each saved one set to its
## fields (added if missing), any other removed (but the kinds in `keep`).
static func _reconcile(entity: Entity, saved: Array, keep: Array) -> void:
	var wanted := {}
	for record in saved:
		wanted[record.script] = record
	for component in entity.components.values().duplicate():
		var path: String = component.get_script().resource_path
		if not wanted.has(path) and not keep.any(func(kind): return is_instance_of(component, kind)):
			entity.remove_component(component.get_script())
	for path in wanted:
		var script: Script = load(path)
		var component: Component = entity.get_component(script)
		var fresh := component == null
		if fresh:
			component = script.new()
		set_fields(component, wanted[path].fields)
		if fresh:
			entity.add_component(component)

## Sets `object`'s script variables from `fields` (typed arrays assigned).
static func set_fields(object: Object, fields: Dictionary) -> void:
	for name in fields:
		var current: Variant = object.get(name)
		if current is Array:
			(current as Array).assign(fields[name])
		elif current is Dictionary:
			(current as Dictionary).assign(fields[name])
		else:
			object.set(name, fields[name])

#endregion
