class_name TtwMudLab extends Node2D
## The Mud Lab: a test ground to drive on and to tune how mud, ruts and water
## look. It runs the real game (session, systems, prefabs).
##   WASD            pan               wheel         zoom (whole steps)
##   arrows          drive the selected vehicle      Q  select the next
##   T Y U I K       spawn tank, truck, hippy, boss, nurse at the mouse
##   C / V / B       shell / rocket / vehicle crater at the mouse
##   R               rain on/off (ripples)
##   F / G           a fire / the hippy's smoke screen at the mouse
##   H               spill oil at the mouse
##   N               winter (snow and frost) / the thaw
##   P / Shift+P     pour water (a bucket's drop) / draw water at the mouse
##   1..7            brush: dig, raise, loose mud, wet, dry, water, track
##   [ ]             brush size        LMB / RMB     paint / paint the opposite
##   O / Shift+O     next / previous debug overlay (wear, wetness, LOD...)
##   Tab             look sliders      L             LOD on/off
##   M               send the selected vehicle to the mouse (a route)
##   X / Shift+X     winch / tow the vehicle nearest the mouse with the selected one
##   J               path weights on/off
## Run: godot --path . res://tools/mud_lab.tscn

const BRUSH_NAMES := ["dig", "raise", "loose mud", "wet", "dry", "water", "track"]
const OPPOSITE := {TtwBrushes.Kind.DIG: TtwBrushes.Kind.RAISE, TtwBrushes.Kind.RAISE: TtwBrushes.Kind.DIG, TtwBrushes.Kind.WET: TtwBrushes.Kind.DRY, TtwBrushes.Kind.DRY: TtwBrushes.Kind.WET}
const SPAWN_KEYS := {KEY_T: &"tank", KEY_Y: &"truck", KEY_U: &"hippy", KEY_I: &"boss", KEY_K: &"nurse"}
const CRATER_KEYS := {KEY_C: &"shell", KEY_V: &"rocket", KEY_B: &"vehicle"}
const PAN_SPEED := 420.0

var game: TtwGame
var terrain: TtwTerrain
var view: TtwTerrainView
var camera: Camera2D
var brush: int = TtwBrushes.Kind.DIG
var radius_px: float = 6.0
var vehicles: Array[Entity] = []
var selected: int = -1
var _help: Label
var _status: Label
var _sliders: Control
var _last_mouse: Vector2
var _heading: float = 0.0
var _paths: TtwPathView

func _ready() -> void:
	game = TtwGame.new()
	add_child(game)
	terrain = game.terrain
	view = game.view
	camera = game.camera
	camera.position = terrain.size_px() * Vector2(0.4, 0.5)
	camera.make_current()
	_paths = TtwPathView.new()
	_paths.session = game.session
	_paths.camera = camera
	game.world_root.add_child(_paths)
	var layer := CanvasLayer.new()
	add_child(layer)
	_help = _label(Vector2(8, 6))
	layer.add_child(_help)
	_status = _label(Vector2(8, 640))
	layer.add_child(_status)
	_sliders = _build_sliders()
	_sliders.visible = false
	layer.add_child(_sliders)
	_update_help()

func _label(at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label

## Paints like the mouse does (probes and tests drive the lab through this).
func paint(kind: int, world: Vector2, radius: float, amount: float, heading: float = 0.0) -> void:
	TtwBrushes.paint(terrain, kind, world, radius, amount, heading, game.water)

## An explosion: its crater, and in water a burst of silt, foam and rings.
func blast(at: Vector2, cause: StringName) -> void:
	game.explode(at, cause)

## Winter: snow over the land (not the river) and frost; or the thaw.
func winter(on: bool) -> void:
	var weather := game.fx.weather
	if on:
		for i in terrain.snow_base.size():
			terrain.snow_base[i] = 0.0 if terrain.water[i] > TtwTerrain.NO_WATER else 5.0
		terrain.snow_level = 0.0
		terrain.snow_gone.fill(0.0)
		terrain.tiles_dirty = true
		terrain.mark_all()
		weather.temperature = -4.0
		weather.snowfall = 0.3
	else:
		weather.temperature = 12.0
		weather.sun = 0.9
		weather.snowfall = 0.0

func spawn(kind: StringName, at: Vector2, heading: float = 0.0) -> Entity:
	var entity := game.spawn_unit(kind, at, heading)
	if entity != null:
		vehicles.append(entity)
		selected = vehicles.size() - 1
	return entity

## Gives `wrecker` a winch if it has none and hooks the vehicle nearest `at`
## (winching it, or towing it); the reason in the status line if it cannot.
func hook(wrecker: Entity, at: Vector2, towing: bool) -> String:
	if not wrecker.has_component(TtwWinch):
		wrecker.add_component(TtwWinch.new())
	var nearest: Entity = null
	for other in vehicles:
		if other != wrecker and is_instance_valid(other) and (nearest == null or game.session.body_of(other).position.distance_to(at) < game.session.body_of(nearest).position.distance_to(at)):
			nearest = other
	var reason := TtwWinchSystem.tow(game.session, wrecker, nearest) if towing else TtwWinchSystem.winch(game.session, wrecker, nearest)
	if not reason.is_empty():
		game.session.notify(reason)
	return reason

func selected_vehicle() -> Entity:
	return vehicles[selected] if selected >= 0 and selected < vehicles.size() else null

func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D): pan.x += 1
	if Input.is_physical_key_pressed(KEY_W): pan.y -= 1
	if Input.is_physical_key_pressed(KEY_S): pan.y += 1
	camera.position += pan.limit_length(1.0) * PAN_SPEED * delta / camera.zoom.x
	var vehicle := selected_vehicle()
	if vehicle != null:
		var drive: TtwDrive = vehicle.get_component(TtwDrive)
		drive.throttle = Input.get_axis("ui_down", "ui_up")
		drive.steer = Input.get_axis("ui_left", "ui_right")
	var mouse := get_global_mouse_position()
	if mouse.distance_to(_last_mouse) > 0.5:
		_heading = (mouse - _last_mouse).angle()
	_last_mouse = mouse
	var amount := 0.6 if brush in [TtwBrushes.Kind.DIG, TtwBrushes.Kind.RAISE, TtwBrushes.Kind.LOOSE] else 0.15
	if brush == TtwBrushes.Kind.WATER:
		amount = 1.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _over_ui():
		paint(brush, mouse, radius_px, amount, _heading)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _over_ui():
		if brush == TtwBrushes.Kind.WATER:
			paint(brush, mouse, radius_px, TtwTerrain.NO_WATER)
		elif OPPOSITE.has(brush):
			paint(OPPOSITE[brush], mouse, radius_px, amount, _heading)
		else:
			paint(brush, mouse, radius_px, -amount, _heading)
	_update_status()
	_update_help()

func _over_ui() -> bool:
	return _sliders.visible and _sliders.get_global_rect().has_point(get_viewport().get_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = Vector2.ONE * minf(camera.zoom.x + 1, 8) if camera.zoom.x >= 1 else Vector2.ONE
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * maxf(camera.zoom.x - 1, 1) if camera.zoom.x > 1 else Vector2.ONE * 0.5
		_update_help()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			TtwTitle.back_to_title(self)
			return
		var mouse := get_global_mouse_position()
		if event.keycode >= KEY_1 and event.keycode <= KEY_7:
			brush = event.keycode - KEY_1
		elif SPAWN_KEYS.has(event.keycode):
			spawn(SPAWN_KEYS[event.keycode], mouse)
		elif CRATER_KEYS.has(event.keycode):
			blast(mouse, CRATER_KEYS[event.keycode])
		elif event.keycode == KEY_F:
			# Fuel and a light: a spill that burns.
			var field := TtwGround.fire_of(game.session)
			field.add_fuel(terrain.tile_of(mouse), 20.0)
			field.ignite(terrain.tile_of(mouse))
		elif event.keycode == KEY_G:
			game.fx.smoke_screen(mouse)
		elif event.keycode == KEY_N:
			winter(game.fx.weather.temperature > 0.0)
		elif event.keycode == KEY_H:
			TtwOilSystem.spill(game.session.resolve(TtwGame.MAP_ALIAS).get_component(TtwGround), mouse, 2.0, 10.0)
		elif event.keycode == KEY_P:
			if event.shift_pressed:
				game.water.draw(mouse, 60.0)
			else:
				game.pour(mouse, 60.0, 24.0)
		elif event.keycode == KEY_R:
			game.water_fx.rain = 0.0 if game.water_fx.rain > 0.0 else 1.0
		elif event.keycode == KEY_Q and not vehicles.is_empty():
			selected = (selected + 1) % vehicles.size()
		elif event.keycode == KEY_BRACKETLEFT:
			radius_px = maxf(2.0, radius_px - 2.0)
		elif event.keycode == KEY_BRACKETRIGHT:
			radius_px = minf(64.0, radius_px + 2.0)
		elif event.keycode == KEY_TAB:
			_sliders.visible = not _sliders.visible
		elif event.keycode == KEY_O:
			view.overlay += -1 if event.shift_pressed else 1
		elif event.keycode == KEY_L:
			view.lod_enabled = not view.lod_enabled
		elif event.keycode == KEY_J:
			_paths.show_costs = not _paths.show_costs
		elif event.keycode == KEY_M and selected_vehicle() != null:
			TtwPilotSystem.order(selected_vehicle(), mouse)
		elif event.keycode == KEY_X and selected_vehicle() != null:
			hook(selected_vehicle(), mouse, event.shift_pressed)
		_update_help()

func _update_help() -> void:
	_help.text = "Mud Lab   brush: %s  size %d px   zoom %s   LOD %s   overlay: %s\narrows drive  Q next vehicle  T Y U I K spawn  C V B crater  F fire  G smoke  H oil  N winter  P pour  R rain  1-7 brush  [ ] size  LMB/RMB paint  O overlay  Tab sliders  L LOD  M move  X winch  Shift+X tow  J path weights  Esc main menu" % [
		BRUSH_NAMES[brush], int(radius_px), str(camera.zoom.x), "on" if view.lod_enabled else "off", view.overlay_name()]

func _update_status() -> void:
	var vehicle := selected_vehicle()
	if vehicle == null:
		_status.text = ""
		return
	var d: TtwDrive = vehicle.get_component(TtwDrive)
	var v: TtwVehicle = vehicle.get_component(TtwVehicle)
	var fuel: TtwFuel = vehicle.get_component(TtwFuel)
	var condition: TtwCondition = vehicle.get_component(TtwCondition)
	var state := "running"
	if vehicle.has_component(TtwWrecked): state = "wrecked"
	elif vehicle.has_component(TtwFlooded): state = "flooded"
	elif vehicle.has_component(TtwStalled): state = "stalled" + ("" if TtwDriveSystem.can_restart(condition) else " (too worn to restart)")
	elif fuel.level() <= 0.0: state = "out of fuel"
	elif vehicle.has_component(TtwStuck): state = "stuck"
	_status.text = "%s  %s   speed %.1f t/s   resistance %.2f   grade %+.2f   stall %.0f%%\nfuel %.1f / %.0f   health %.0f / %.0f   sink %.1f px   water %.1f px   grime %.0f%%   carried mud %.1f" % [
		v.kind, state, d.speed / Kit2D.tile_size(), d.resistance, d.grade, d.stall_meter * 100.0,
		fuel.level(), fuel.capacity, condition.current(), condition.max_health, v.sink, v.water_depth, v.grime * 100.0, v.carried_mud]

## A slider for every ranged float the terrain shader exposes.
func _build_sliders() -> Control:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 52)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 560)
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	# The weather first: temperature, sun, wind, rain and snowfall.
	var weather: TtwWeather = game.fx.weather
	for spec in [["temperature", -20.0, 30.0], ["sun", 0.0, 1.0], ["wind x", -60.0, 60.0], ["wind y", -60.0, 60.0], ["rain", 0.0, 1.0], ["snowfall", 0.0, 1.0]]:
		var field: String = spec[0]
		var current: float = weather.wind.x if field == "wind x" else (weather.wind.y if field == "wind y" else float(weather.get(field)))
		rows.add_child(_slider_row("weather: " + field, spec[1], spec[2], current, func(v: float):
			if field == "wind x":
				weather.wind.x = v
			elif field == "wind y":
				weather.wind.y = v
			else:
				weather.set(field, v)))
	for uniform in TtwTerrainView.SHADER.get_shader_uniform_list():
		if uniform.type != TYPE_FLOAT or uniform.hint != PROPERTY_HINT_RANGE:
			continue
		var limits: PackedStringArray = str(uniform.hint_string).split(",")
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(130, 0)
		label.text = uniform.name
		var slider := HSlider.new()
		slider.min_value = float(limits[0])
		slider.max_value = float(limits[1])
		slider.step = (slider.max_value - slider.min_value) / 200.0
		slider.custom_minimum_size = Vector2(140, 0)
		var current: Variant = view.look(uniform.name)
		if current == null:
			current = RenderingServer.shader_get_parameter_default(TtwTerrainView.SHADER.get_rid(), uniform.name)
		slider.value = float(current) if current != null else slider.min_value
		var value_label := Label.new()
		value_label.text = "%.2f" % slider.value
		var parameter: StringName = uniform.name
		slider.value_changed.connect(func(v: float):
			view.set_look(parameter, v)
			value_label.text = "%.2f" % v)
		row.add_child(label)
		row.add_child(slider)
		row.add_child(value_label)
		rows.add_child(row)
	return panel

func _slider_row(text: String, low: float, high: float, value: float, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(130, 0)
	label.text = text
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 200.0
	slider.custom_minimum_size = Vector2(140, 0)
	slider.value = value
	var value_label := Label.new()
	value_label.text = "%.2f" % value
	slider.value_changed.connect(func(v: float):
		changed.call(v)
		value_label.text = "%.2f" % v)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	return row
