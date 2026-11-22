class_name TtwTitle extends Control
## The title screen (the game's first scene): a skirmish on any map, the
## saved game, the Mud Lab, or quit. With --map=, --watch or --load= on the
## command line (after --) it starts the skirmish at once.

const SKIRMISH := "res://main.tscn"
const MUD_LAB := "res://tools/mud_lab.tscn"
const TITLE := "res://game/rts/title.tscn"

func _ready() -> void:
	if _wants_game():
		start.call_deferred(&"river")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.11, 0.1, 0.08)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	var title := Label.new()
	title.text = "Tiny Truck Wars"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.modulate = Color(1, 1, 1, 0.6)
	column.add_child(version)
	column.add_child(HSeparator.new())
	for map in TtwMaps.MAPS:
		_button(column, "play_" + String(map), "Play: " + TtwMaps.TITLES[map], start.bind(map))
	var load_button := _button(column, "load", "Load saved game", load_saved)
	load_button.disabled = not FileAccess.file_exists(TtwSkirmish.QUICK_SAVE)
	_button(column, "mud_lab", "Mud Lab (ground sandbox)", open_mud_lab)
	# A browser tab is closed by the browser.
	if not OS.has_feature("web"):
		column.add_child(HSeparator.new())
		_button(column, "quit", "Quit", func(): get_tree().quit())

func _button(parent: Control, id: String, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 36)
	button.set_meta(&"test_id", "title_" + id)
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button

func _wants_game() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map=") or argument == "--watch" or argument.begins_with("--load="):
			return true
	return false

## A skirmish on `map` in place of the title (the command line may pick
## another map, or a save, as TtwSkirmish reads it).
func start(map: StringName) -> TtwSkirmish:
	var game: TtwSkirmish = (load(SKIRMISH) as PackedScene).instantiate()
	game.map_name = map
	_replace_with(game)
	return game

## The quick-saved game in place of the title.
func load_saved() -> TtwSkirmish:
	var game: TtwSkirmish = (load(SKIRMISH) as PackedScene).instantiate()
	game.load_path = TtwSkirmish.QUICK_SAVE
	_replace_with(game)
	return game

func open_mud_lab() -> Node:
	var lab: Node = (load(MUD_LAB) as PackedScene).instantiate()
	_replace_with(lab)
	return lab

func _replace_with(next: Node) -> void:
	var tree := get_tree()
	var parent := get_parent()
	parent.remove_child(self)
	parent.add_child(next)
	if tree.current_scene == self:
		tree.current_scene = next
	queue_free()

## Back to the title from anywhere: `from` (a game or the Mud Lab) is
## replaced by a fresh title screen.
static func back_to_title(from: Node) -> Node:
	var tree := from.get_tree()
	tree.paused = false
	var title: Node = (load(TITLE) as PackedScene).instantiate()
	var parent := from.get_parent()
	parent.remove_child(from)
	parent.add_child(title)
	if tree.current_scene == from:
		tree.current_scene = title
	from.queue_free()
	return title
