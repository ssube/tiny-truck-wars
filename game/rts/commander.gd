class_name TtwCommander extends Node2D
## The player's hands on the game: selection, orders, the camera and placing
## structures. Drawn in the world (selection rings, the drag box, the ghost of
## a structure being placed).
##   LMB / drag      select (own units; or one own structure)
##   RMB             orders: move; on an enemy, attack it (units with guns);
##                   on a stuck or broken vehicle, a selected wrecker winches
##                   it (tows it if it cannot drive and is close)
##   X               the selected wreckers let go
##   S               stop
##   R               the selected engineers start or stop laying road
##   F               the special at the cursor: Water tankers spray it,
##                   bucket helicopters drop on it, hippies smoke it
##   WASD / arrows / screen edge   pan        wheel   zoom
##   Esc / RMB       cancel placing (Esc otherwise opens the menu: TtwMenu)
## Probes and tests call the same functions the input does.

signal selection_changed
signal rejected(reason: String)

const PAN_SPEED := 480.0
const EDGE_PX := 6.0
const PICK_PX := 12.0
## Formation spacing for a group move (px).
const SPACING := 30.0
const DRAG_PX := 4.0

var game: TtwGame
var team: int = 1
var selected: Array[Entity] = []
## A structure kind being placed, or empty.
var placing: StringName = &""
var _drag_from: Vector2
var _dragging: bool = false
var _pressed: bool = false
var _zoom := TtwZoom.new(PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0]))

func _init() -> void:
	name = "Commander"
	z_index = 10

func session() -> KitSession:
	return game.session

func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): pan.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): pan.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): pan.y += 1
	var screen := get_viewport().get_mouse_position()
	var view := get_viewport_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, view).has_point(screen):
		if screen.x < EDGE_PX: pan.x -= 1
		if screen.x > view.x - EDGE_PX: pan.x += 1
		if screen.y < EDGE_PX: pan.y -= 1
		if screen.y > view.y - EDGE_PX: pan.y += 1
	if pan != Vector2.ZERO:
		var camera := game.camera
		camera.position += pan.normalized() * PAN_SPEED * delta / camera.zoom.x
		var half := view / camera.zoom * 0.5
		var size := game.terrain.size_px()
		camera.position = camera.position.clamp(half.min(size * 0.5), (size - half).max(size * 0.5))
	# Untyped: a freed entity cannot be passed as an Entity, so a typed
	# lambda would fail on the very ones this drops.
	selected.assign(selected.filter(func(e): return is_instance_valid(e) and session().body_of(e) != null))
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	var at := get_global_mouse_position()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.camera.zoom = Vector2.ONE * _zoom.apply(event, game.camera.zoom.x)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not placing.is_empty():
					place(at)
					return
				_pressed = true
				_dragging = false
				_drag_from = at
			elif _pressed:
				_pressed = false
				if _dragging:
					select_rect(Rect2(_drag_from, at - _drag_from).abs(), event.shift_pressed)
				else:
					select_at(at, event.shift_pressed)
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not placing.is_empty():
				placing = &""
			else:
				order_at(at)
	elif event is InputEventMouseMotion and _pressed:
		if at.distance_to(_drag_from) > DRAG_PX / game.camera.zoom.x:
			_dragging = true
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_X: release()
			KEY_S: stop()
			KEY_R: toggle_paving()
			KEY_F: special_at(at)

#region Selection

## Own units inside `rect` (world px); none there selects nothing.
func select_rect(rect: Rect2, add: bool = false) -> void:
	if not add:
		selected.clear()
	for entity in session().view([TtwUnit, TtwTeam, KitBody]):
		if TtwTeam.of(entity) == team and not entity.has_component(TtwWrecked) and rect.has_point(session().body_of(entity).position) and not selected.has(entity):
			selected.append(entity)
	selection_changed.emit()

## The own unit or structure nearest `at` within reach.
func select_at(at: Vector2, add: bool = false) -> void:
	if not add:
		selected.clear()
	var hit := pick(at, true)
	if hit != null and TtwTeam.of(hit) == team and not selected.has(hit):
		if hit.has_component(TtwStructure):
			selected.clear()
		selected.append(hit)
	selection_changed.emit()

## The unit (or, failing that, the structure) under `at`; `own_only` limits
## it to this side. Null if none.
func pick(at: Vector2, own_only: bool = false) -> Entity:
	var best: Entity = null
	var best_d := PICK_PX
	for entity in session().view([TtwUnit, KitBody]):
		if own_only and TtwTeam.of(entity) != team:
			continue
		var d := session().body_of(entity).position.distance_to(at)
		if d < best_d:
			best = entity
			best_d = d
	if best != null:
		return best
	for entity in session().view([TtwStructure, TtwObstacle, KitBody]):
		if own_only and TtwTeam.of(entity) != team:
			continue
		var body := session().body_of(entity)
		var o: TtwObstacle = entity.get_component(TtwObstacle)
		if Rect2(body.position + o.offset - o.half_extents, o.half_extents * 2.0).has_point(at):
			return entity
	return null

func selected_units() -> Array[Entity]:
	var out: Array[Entity] = []
	for entity in selected:
		if is_instance_valid(entity) and entity.has_component(TtwUnit):
			out.append(entity)
	return out

func selected_structure() -> Entity:
	for entity in selected:
		if is_instance_valid(entity) and entity.has_component(TtwStructure):
			return entity
	return null

#endregion

#region Orders

## The right click: on an enemy, the selected units with guns attack it; a
## wrecker hooks a stuck or broken vehicle under `at`; otherwise the selected
## units go there, spread in a block.
func order_at(at: Vector2) -> void:
	var units := selected_units()
	if units.is_empty():
		return
	var target := pick(at)
	var side := TtwTeam.of(target) if target != null else TtwTeam.NEUTRAL
	if target != null and side != team and side != TtwTeam.NEUTRAL and TtwCombat.alive(session(), target):
		var gunners := units.filter(func(u): return u.has_component(TtwGun))
		if not gunners.is_empty():
			for unit in gunners:
				TtwGunSystem.attack(session(), unit, target)
			return
	if target != null and target.has_component(TtwDrive) and not units.has(target) and (target.has_component(TtwStuck) or TtwWinchSystem.immobile(target)):
		for unit in units:
			if unit.has_component(TtwWinch):
				_hook(unit, target)
				return
	var columns := ceili(sqrt(units.size()))
	for k in units.size():
		session().unlink(units[k], TtwAttacking)
		var offset := Vector2(k % columns - (columns - 1) * 0.5, k / columns - (ceili(float(units.size()) / columns) - 1) * 0.5) * SPACING
		TtwPilotSystem.order(units[k], at + offset)

func _hook(wrecker: Entity, target: Entity) -> void:
	var winch: TtwWinch = wrecker.get_component(TtwWinch)
	var close := session().body_of(wrecker).position.distance_to(session().body_of(target).position) <= (winch.tow_tiles + 1.0) * TtwTerrain.tile_px()
	var reason := ""
	if TtwWinchSystem.immobile(target) and close:
		reason = TtwWinchSystem.tow(session(), wrecker, target)
	else:
		reason = TtwWinchSystem.winch(session(), wrecker, target)
	if reason == "Out of reach.":
		# Drive up to it first; the player hooks it when there.
		TtwPilotSystem.order(wrecker, session().body_of(target).position)
		reason = "Out of reach: driving closer."
	if not reason.is_empty():
		_reject(reason)
	else:
		TtwPilotSystem.stop(wrecker)

func release() -> void:
	for unit in selected_units():
		if unit.has_component(TtwWinch):
			TtwWinchSystem.release(session(), unit)

func stop() -> void:
	for unit in selected_units():
		session().unlink(unit, TtwAttacking)
		TtwPilotSystem.stop(unit)

## Engineers lay road, or stop (all of the selected follow the first).
func toggle_paving() -> void:
	var engineers := selected_units().filter(func(u): return u.has_component(TtwEngineer))
	if engineers.is_empty():
		return
	var on := not (engineers[0].get_component(TtwEngineer) as TtwEngineer).paving
	for unit in engineers:
		TtwKitSystem.set_paving(unit, on)
	session().notify("Laying road." if on else "Stopped laying road.")

## The selected units' specials at `at`; the first refusal is said.
func special_at(at: Vector2) -> void:
	var reason := ""
	var used := false
	for unit in selected_units():
		var why := ""
		if unit.has_component(TtwWaterTank):
			why = TtwKitSystem.spray(unit, at)
		elif unit.has_component(TtwBucket):
			why = TtwKitSystem.drop(unit, at)
		elif unit.has_component(TtwSmokeLauncher):
			why = TtwSpecialSystem.smoke(session(), unit, at)
		else:
			continue
		if why.is_empty():
			used = true
		elif reason.is_empty():
			reason = why
	if not used and not reason.is_empty():
		_reject(reason)

#endregion

#region Building

## Starts placing `kind`; the next left click puts it down.
func begin_placing(kind: StringName) -> void:
	placing = kind

## Puts the structure being placed at `at`, if the rules allow.
func place(at: Vector2) -> Entity:
	if placing.is_empty():
		return null
	var built := game.place_structure(placing, at, team)
	if built == null:
		_reject(session().last_error)
	else:
		placing = &""
	return built

## Why the structure being placed cannot go at `at` ("" if it can).
func placing_reason(at: Vector2) -> String:
	if placing.is_empty():
		return ""
	return TtwPlacement.check(session(), placing, at, team, game.footprint_of(placing))

func _reject(reason: String) -> void:
	rejected.emit(reason)
	session().notify(reason)

#endregion

func _draw() -> void:
	for entity in selected:
		var body := session().body_of(entity)
		if body == null:
			continue
		if entity.has_component(TtwStructure):
			var o: TtwObstacle = entity.get_component(TtwObstacle)
			draw_rect(Rect2(body.position + o.offset - o.half_extents - Vector2(2, 2), o.half_extents * 2.0 + Vector2(4, 4)), Color(1, 1, 1, 0.9), false, 1.0)
		else:
			draw_arc(body.position, 11.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.0)
			var c: TtwCondition = entity.get_component(TtwCondition)
			if c != null:
				draw_rect(Rect2(body.position + Vector2(-8, 12), Vector2(16, 2)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(body.position + Vector2(-8, 12), Vector2(16.0 * c.share(), 2)), Color(0.3, 0.9, 0.3).lerp(Color(0.9, 0.2, 0.2), 1.0 - c.share()))
	# Every unit's side, as a small mark at its feet.
	for entity in session().view([TtwUnit, TtwTeam, KitBody]):
		var body := session().body_of(entity)
		draw_rect(Rect2(body.position + Vector2(-1, 8), Vector2(3, 2)), TtwTeam.color(TtwTeam.of(entity)))
		if entity.has_component(TtwStuck):
			draw_string(ThemeDB.fallback_font, body.position + Vector2(-3, -14), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.85, 0.2))
	if _dragging:
		var at := get_global_mouse_position()
		draw_rect(Rect2(_drag_from, at - _drag_from).abs(), Color(1, 1, 1, 0.8), false, 1.0)
	if not placing.is_empty():
		var at := get_global_mouse_position()
		var half := game.footprint_of(placing)
		var ok := placing_reason(at).is_empty()
		draw_rect(Rect2(at - half, half * 2.0), Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.3, 0.3, 0.35))
		if placing == &"helipad":
			draw_arc(at, TtwPlacement.helipad_reach() * TtwTerrain.tile_px(), 0.0, TAU, 48, Color(1, 1, 1, 0.3), 1.0)
