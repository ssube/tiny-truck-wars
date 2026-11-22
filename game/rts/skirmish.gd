class_name TtwSkirmish extends TtwGame
## A skirmish: the game on a skirmish map (TtwMaps), the player's commander
## and HUD, and a computer opponent for each side in `ai_teams`. The main
## scene.
##   Esc          the menu: resume, save, load, a new game on any map, quit
##   F5 / F9      quick save / quick load
## From the command line (after --): --map=<river|snowfield|dunes>,
## --watch (the computer plays both sides), --load=<path>.

const QUICK_SAVE := "user://saves/quick.ttwsave"
const MAIN := "res://main.tscn"

## Sides the computer plays.
@export var ai_teams: Array[int] = [2]
var commander: TtwCommander
var hud: TtwHud
var menu: TtwMenu

func _ready() -> void:
	map_kind = &"skirmish"
	_read_arguments()
	super()
	camera.make_current()
	for team in ai_teams:
		if session.resolve("ai:%d" % team) == null:
			TtwAiSystem.play(session, team)
	commander = TtwCommander.new()
	commander.game = self
	world_root.add_child(commander)
	commander.clamp_camera()
	hud = TtwHud.new()
	hud.game = self
	hud.commander = commander
	add_child(hud)
	menu = TtwMenu.new()
	menu.game = self
	add_child(menu)

func _read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			var name := StringName(argument.trim_prefix("--map="))
			if TtwMaps.knows(name):
				map_name = name
		elif argument == "--watch":
			ai_teams = [1, 2]
		elif argument.begins_with("--load=") and load_path.is_empty():
			load_path = argument.trim_prefix("--load=")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F5:
			quick_save()
		KEY_F9:
			restart(map_name, QUICK_SAVE)

## Saves to the quick slot and says so.
func quick_save() -> String:
	var error := TtwSave.save(self, QUICK_SAVE)
	session.notify("Saved." if error.is_empty() else error)
	return error

## A new skirmish in place of this one: on `map`, or from the save at
## `from`. Returns the new game.
func restart(map: StringName, from: String = "") -> TtwSkirmish:
	if not from.is_empty() and not FileAccess.file_exists(from):
		session.notify("There is no saved game.")
		return null
	var next: TtwSkirmish = (load(MAIN) as PackedScene).instantiate()
	next.map_name = map
	next.load_path = from
	next.ai_teams = ai_teams.duplicate()
	get_tree().paused = false
	var parent := get_parent()
	var index := get_index()
	parent.remove_child(self)
	queue_free()
	parent.add_child(next)
	parent.move_child(next, index)
	return next
