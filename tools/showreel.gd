extends Node
## A gameplay clip for the store page: the computer playing both sides of a
## skirmish, the camera following the fighting. Each side starts with a few
## more tanks and full depots, so the first wave sets out within the minute.
## Recorded with Godot's movie maker (every frame rendered, 60 fps, however
## slow the machine):
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path . --audio-driver Dummy \
##     --resolution 1920x1080 --fixed-fps 60 --write-movie clip.avi \
##     res://tools/showreel.tscn -- --map=river --seconds=180

const EXTRA_TANKS := 3
## How long (s) a burst keeps the camera's interest, how fast the camera
## follows, and how often it looks for the action again.
const INTEREST_SECONDS := 6.0
const FOLLOW := 0.012
const LOOK_EVERY := 120

var game: TtwSkirmish
var frames := 10800
var map := &"river"
var _bursts: Array = []
var _focus := Vector2.ZERO
var _frame := 0
var _caption: Label

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			map = StringName(argument.trim_prefix("--map="))
		elif argument.begins_with("--seconds="):
			frames = int(float(argument.trim_prefix("--seconds=")) * 60.0)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.map_name = map
	game.ai_teams = [1, 2]
	add_child(game)
	game.hud.visible = false
	var tile := TtwTerrain.tile_px()
	for side in [1, 2]:
		var garage: Entity = game.session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == side)[0]
		var home := game.session.body_of(garage).position
		var toward := 1.0 if side == 1 else -1.0
		for k in EXTRA_TANKS:
			game.spawn_unit(&"tank", home + Vector2(toward * 8.0, -3.0 + k * 2.0) * tile, 0.0 if side == 1 else PI, side)
	for depot in game.session.view([TtwDepot, TtwTeam]):
		if TtwTeam.of(depot) != TtwTeam.NEUTRAL:
			var d: TtwDepot = depot.get_component(TtwDepot)
			d.stock = d.capacity
	(game.session.system(&"ballistics") as TtwBallisticsSystem).burst.connect(func(_s, at: Vector2, _on): _bursts.append([game.session.tick, at]))
	(game.session.system(&"depots") as TtwDepotSystem).detonated.connect(func(_d, at: Vector2, _r): _bursts.append([game.session.tick, at]))
	game.camera.zoom = Vector2(4, 4)
	_focus = game.terrain.size_px() * 0.5
	game.camera.position = _focus
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.text = "Tiny Truck Wars: the computer against itself, %s" % TtwMaps.TITLES.get(map, String(map))
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame % LOOK_EVERY == 1:
		_focus = _action()
	game.camera.position = game.camera.position.lerp(_focus, FOLLOW)
	_caption.modulate.a = clampf(1.0 - (_frame - 300) / 60.0, 0.0, 1.0)
	if _frame >= frames:
		get_tree().quit()

## Where the fighting is: the middle of recent bursts, else the middle of the
## units nearest the map's middle (the armies meet there).
func _action() -> Vector2:
	var now := game.session.tick
	_bursts = _bursts.filter(func(b): return now - b[0] < INTEREST_SECONDS * 60.0)
	if not _bursts.is_empty():
		var sum := Vector2.ZERO
		for b in _bursts:
			sum += b[1]
		return sum / _bursts.size()
	var middle := game.terrain.size_px() * 0.5
	var units := game.session.view([TtwUnit, KitBody]).filter(func(u): return not u.has_component(TtwWrecked))
	if units.is_empty():
		return middle
	units.sort_custom(func(a, b): return game.session.body_of(a).position.distance_to(middle) < game.session.body_of(b).position.distance_to(middle))
	var sum := Vector2.ZERO
	var count := mini(6, units.size())
	for k in count:
		sum += game.session.body_of(units[k]).position
	return sum / count
