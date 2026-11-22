class_name TtwMaps extends RefCounted
## The skirmish maps by name, and what every one of them shares: two
## mirrored bases (a garage, two depots, two tanks, a wrecker and an
## engineer), neutral depots to take, and the match.
##
## A map is a script with `const SIZE`, `static func terrain() -> TtwTerrain`,
## `static func layout() -> Array[Dictionary]` ({kind, at, team?, structure?},
## world px), `static func road_tiles() -> Dictionary` (a set of tiles) and
## `static func weather(w: TtwWeather)`. Props and neutral structures are
## moved off the roads, with a vehicle's clearance, as they are put down.

const MAPS := {
	&"river": preload("res://game/rts/skirmish_map.gd"),
	&"snowfield": preload("res://game/rts/snowfield_map.gd"),
	&"dunes": preload("res://game/rts/dunes_map.gd"),
}
const TITLES := {&"river": "River crossing", &"snowfield": "Snowfield", &"dunes": "Dunes"}

static func knows(name: StringName) -> bool:
	return MAPS.has(name)

## Puts map `name` in play on `game`: its ground, its weather, what stands on
## it and the match; the camera on side 1's base.
static func build(game: TtwGame, name: StringName) -> void:
	var map: Script = MAPS.get(name, MAPS[&"river"])
	game.load_ground(map.terrain())
	var entity := game.session.resolve(TtwGame.MAP_ALIAS)
	map.weather(entity.get_component(TtwWeather))
	var roads: Dictionary = map.road_tiles()
	for item in map.layout():
		var at: Vector2 = item.at
		if not TtwUnits.knows(item.kind) and item.get("team", TtwTeam.NEUTRAL) == TtwTeam.NEUTRAL:
			var box := box_of(item.kind)
			at = off_roads(roads, at + box.position, box.size, map.SIZE.x) - box.position
		if item.get("structure", false):
			game.spawn_structure(item.kind, at, item.team)
		elif TtwUnits.knows(item.kind):
			game.spawn_unit(item.kind, at, 0.0 if item.team == 1 else PI, item.team)
		else:
			game.spawn_prop(item.kind, at, item.get("angle", 0.0))
	if not entity.has_component(TtwMatch):
		entity.add_component(TtwMatch.new())
	var size: Vector2i = map.SIZE
	game.camera.position = Vector2(16, size.y / 2.0) * TtwTerrain.tile_px()

## What a prop or structure of `kind` stands on: the box's offset from the
## origin (position) and its half size (size), px.
static func box_of(kind: StringName) -> Rect2:
	if TtwPlacement.SCENES.has(kind):
		return Rect2(Vector2.ZERO, TtwPlacement.footprint(kind))
	if not _halves.has(kind):
		var body: TtwProp2D = (load(TtwGame.PROP_SCENES[kind]) as PackedScene).instantiate()
		var o := body.obstacle
		_halves[kind] = Rect2(o.offset, o.half_extents if o.shape == TtwObstacle.Shape.BOX else Vector2(o.radius, o.radius))
		body.free()
	return _halves[kind]

static var _halves: Dictionary = {}

## `at`, or the nearest spot a whole number of tiles up, down or (away from
## the map's middle) aside where a footprint of `half`, with a vehicle's
## clearance, is off every road tile.
static func off_roads(roads: Dictionary, at: Vector2, half: Vector2, width: int) -> Vector2:
	var tile := TtwTerrain.tile_px()
	var outward := -1.0 if at.x < width * tile * 0.5 else 1.0
	# Rings out to 10 tiles, nearest first; across the map's middle line the
	# sideways steps mirror, so mirrored items move alike.
	var tries: Array[Vector2] = []
	for y in range(-10, 11):
		for x in range(-10, 11):
			tries.append(Vector2(x * outward, y))
	tries.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.length_squared() < b.length_squared() or (a.length_squared() == b.length_squared() and (a.y < b.y or (a.y == b.y and a.x * outward < b.x * outward))))
	for step in tries:
		var spot := at + step * tile
		if _clear(roads, spot, half + Vector2.ONE * TtwPathGrid.OBSTACLE_GROW):
			return spot
	return at

static func _clear(roads: Dictionary, at: Vector2, half: Vector2) -> bool:
	var tile := TtwTerrain.tile_px()
	var lo := Vector2i(((at - half) / tile).floor())
	var hi := Vector2i(((at + half) / tile).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if roads.has(Vector2i(x, y)):
				return false
	return true

## A side's base, west (side 1) or east (side 2) of a map `width` tiles wide,
## around row `mid`: appended to `out`.
static func base(out: Array[Dictionary], side: int, width: int, mid: float, inset: float = 8.0) -> void:
	var tile := TtwTerrain.tile_px()
	var x := inset if side == 1 else width - inset
	var toward := 1.0 if side == 1 else -1.0
	out.append({"kind": &"garage", "at": Vector2(x, mid - 3.0) * tile, "team": side, "structure": true})
	out.append({"kind": &"depot", "at": Vector2(x, mid + 3.0) * tile, "team": side, "structure": true})
	out.append({"kind": &"depot", "at": Vector2(x - toward * 4.0, mid + 3.0) * tile, "team": side, "structure": true})
	out.append({"kind": &"tank", "at": Vector2(x + toward * 5.0, mid - 1.0) * tile, "team": side})
	out.append({"kind": &"tank", "at": Vector2(x + toward * 5.0, mid + 1.5) * tile, "team": side})
	out.append({"kind": &"engineer", "at": Vector2(x + toward * 5.0, mid + 5.0) * tile, "team": side})
	out.append({"kind": &"wrecker", "at": Vector2(x + toward * 3.0, mid + 6.5) * tile, "team": side})

## A neutral depot at tile `at`.
static func neutral_depot(out: Array[Dictionary], at: Vector2) -> void:
	out.append({"kind": &"depot", "at": at * TtwTerrain.tile_px(), "team": TtwTeam.NEUTRAL, "structure": true})

## Mirrors x for side 2 (tile units).
static func mirror(x: float, width: int) -> float:
	return width - x
