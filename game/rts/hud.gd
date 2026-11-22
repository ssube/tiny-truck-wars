class_name TtwHud extends CanvasLayer
## What the player reads and presses: the side's fuel, the build buttons, what
## is selected (a garage's queue and buttons to build units), messages, and
## the end of the match.

var game: TtwGame
var commander: TtwCommander
var _fuel: Label
var _info: Label
var _toast: Label
var _toast_left: float = 0.0
var _units: HBoxContainer
var _builds: HBoxContainer
var _banner: Label

func _init() -> void:
	name = "Hud"

func _ready() -> void:
	_fuel = _label(Vector2(8, 6))
	_builds = HBoxContainer.new()
	_builds.position = Vector2(8, 28)
	add_child(_builds)
	for kind in TtwProduction.STRUCTURES:
		var button := Button.new()
		button.text = "%s (%d)" % [String(kind).capitalize(), int(TtwProduction.STRUCTURES[kind])]
		button.set_meta(&"test_id", "build_" + String(kind))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): commander.begin_placing(kind))
		_builds.add_child(button)
	_info = _label(Vector2(8, 0))
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.offset_top = -76
	_units = HBoxContainer.new()
	_units.anchor_top = 1.0
	_units.anchor_bottom = 1.0
	_units.offset_top = -30
	_units.offset_left = 8
	add_child(_units)
	for kind in TtwProduction.UNITS:
		var button := Button.new()
		button.text = "%s (%d)" % [String(kind).capitalize(), int(TtwProduction.unit_fuel(kind))]
		button.set_meta(&"test_id", "make_" + String(kind))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func():
			var garage := commander.selected_structure()
			if garage != null:
				var reason := TtwGarageSystem.enqueue(garage, kind)
				if not reason.is_empty():
					game.session.notify(reason))
		_units.add_child(button)
	_toast = _label(Vector2(0, 60))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -200
	_toast.offset_right = 200
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner = _label(Vector2.ZERO)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.4
	_banner.offset_left = -200
	_banner.offset_right = 200
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 32)
	_banner.visible = false
	commander.selection_changed.connect(_show_garage)
	_show_garage()
	game.session.notified.connect(func(text: String):
		_toast.text = text
		_toast_left = 3.0)
	(game.session.system(&"match") as TtwMatchSystem).match_over.connect(func(winner: int):
		_banner.text = "Victory" if winner == commander.team else "Defeat"
		_banner.visible = true)

func _label(at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label

func _process(delta: float) -> void:
	var total := 0.0
	var depots := 0
	for depot in game.session.view([TtwDepot, TtwTeam]):
		if TtwTeam.of(depot) == commander.team and not depot.has_component(TtwDetonating):
			total += (depot.get_component(TtwDepot) as TtwDepot).level()
			depots += 1
	_fuel.text = "Fuel %d in %d depots" % [int(total), depots]
	_toast_left -= delta
	_toast.visible = _toast_left > 0.0
	_info.text = _describe()

## The unit buttons show while a structure that builds is selected: those
## for what it builds.
func _show_garage() -> void:
	var structure := commander.selected_structure()
	var queue: TtwBuildQueue = structure.get_component(TtwBuildQueue) if structure != null else null
	_units.visible = queue != null
	if queue != null:
		for button in _units.get_children():
			button.visible = queue.builds.has(StringName(String(button.get_meta(&"test_id")).trim_prefix("make_")))

func _describe() -> String:
	var structure := commander.selected_structure()
	if structure != null:
		var kind := String((structure.get_component(TtwStructure) as TtwStructure).kind).capitalize()
		var h: TtwHealth = structure.get_component(TtwHealth)
		var text := "%s   health %d / %d" % [kind, int(h.current()), int(h.max_health)]
		if structure.has_component(TtwBuildQueue):
			var g: TtwBuildQueue = structure.get_component(TtwBuildQueue)
			if not g.queue.is_empty():
				text += "\nbuilding %s %d%%   queue %s" % [g.queue[0], int(100.0 * g.progress / TtwProduction.unit_seconds(g.queue[0])), ", ".join(g.queue.slice(1).map(func(k): return String(k)))]
			if not g.status.is_empty():
				text += "\n" + g.status
		if structure.has_component(TtwDepot):
			var d: TtwDepot = structure.get_component(TtwDepot)
			text += "\nfuel %d / %d   refill %.2f/s" % [int(d.level()), int(d.capacity), (game.session.system(&"depots") as TtwDepotSystem).refill_rate(structure)]
		return text
	var units := commander.selected_units()
	if units.size() == 1:
		var unit := units[0]
		var c: TtwCondition = unit.get_component(TtwCondition)
		var f: TtwFuel = unit.get_component(TtwFuel)
		var state := "stuck" if unit.has_component(TtwStuck) else ("flooded" if unit.has_component(TtwFlooded) else ("stalled" if unit.has_component(TtwStalled) else ""))
		if unit.has_component(TtwWinch):
			state += " (winch: right-click a stuck or broken vehicle, X lets go)"
		state += _kit_line(unit)
		return "%s   health %d / %d   fuel %d / %d   %s" % [String(TtwUnits.kind_of(unit)).capitalize(), int(c.current()), int(c.max_health), int(f.level()), int(f.capacity), state]
	if units.size() > 1:
		return "%d units" % units.size()
	return ""

## What a unit's kit or special is doing, and its keys.
func _kit_line(unit: Entity) -> String:
	var out := ""
	var tanker: TtwTanker = unit.get_component(TtwTanker)
	if tanker != null:
		out += "  cargo %d / %d" % [int(tanker.level()), int(tanker.cargo_capacity)]
	var engineer: TtwEngineer = unit.get_component(TtwEngineer)
	if engineer != null:
		out += "  (R: lay road%s; builds what is placed near it)" % (", on" if engineer.paving else "")
	var water: TtwWaterTank = unit.get_component(TtwWaterTank)
	if water != null:
		out += "  water %.1f / %d (pumps beside water; F sprays at the cursor)" % [water.amount, int(water.capacity)]
	var bucket: TtwBucket = unit.get_component(TtwBucket)
	if bucket != null:
		out += "  bucket %.1f / %d (hover over water to fill; F drops at the cursor)" % [bucket.amount, int(bucket.capacity)]
	var smoke: TtwSmokeLauncher = unit.get_component(TtwSmokeLauncher)
	if smoke != null:
		var wait := smoke.ready_tick - game.session.tick
		out += "  smoke %s (F throws it at the cursor)" % ("ready" if wait <= 0 else "in %d s" % ceili(wait / 60.0))
	if unit.has_component(TtwBoss):
		out += "  (garages near it build faster)"
	if unit.has_component(TtwMedic):
		out += "  (heals ground vehicles near it)"
	return out
