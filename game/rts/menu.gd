class_name TtwMenu extends CanvasLayer
## The skirmish's menu (Esc): resume, save, load, a new game on each map,
## quit. The game stands still while it is open.

var game: TtwSkirmish
var _panel: PanelContainer

func _init() -> void:
	name = "Menu"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -130
	_panel.offset_right = 130
	_panel.offset_top = -150
	_panel.offset_bottom = 150
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	var title := Label.new()
	title.text = "%s %s" % [ProjectSettings.get_setting("application/config/name"), ProjectSettings.get_setting("application/config/version")]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_button(column, "resume", "Resume", close)
	_button(column, "save", "Save (F5)", func():
		game.quick_save()
		close())
	_button(column, "load", "Load (F9)", func(): game.restart(game.map_name, TtwSkirmish.QUICK_SAVE))
	for map in TtwMaps.MAPS:
		_button(column, "new_" + String(map), "New game: " + TtwMaps.TITLES[map], func(): game.restart(map))
	_button(column, "quit", "Quit", func(): game.get_tree().quit())
	_panel.visible = false

func _button(parent: Control, id: String, text: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.set_meta(&"test_id", "menu_" + id)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	parent.add_child(button)

func is_open() -> bool:
	return _panel.visible

func open() -> void:
	_panel.visible = true
	game.get_tree().paused = true

func close() -> void:
	_panel.visible = false
	game.get_tree().paused = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_open():
			close()
		elif game.commander != null and not game.commander.placing.is_empty():
			game.commander.placing = &""
		else:
			open()
		get_viewport().set_input_as_handled()
