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
## How long (s) a burst counts as action, how often (frames) the director
## looks again, and how far (px) units or bursts count as one gathering.
const INTEREST_SECONDS := 4.0
const LOOK_EVERY := 30
const GATHER_PX := 128.0
## Whole zooms the camera settles on: wide in quiet spells, close on a crowd.
const ZOOM_WIDE := 2.0
const ZOOM_CLOSE := 5.0
## Room (px) kept round a gathering when fitting it on screen.
const MARGIN_PX := 48.0
## Spring smoothing (seconds to settle, about): position and zoom.
const MOVE_TIME := 1.6
const ZOOM_TIME := 2.4
## A new target is taken only past this (px): no hunting.
const MOVE_SLACK_PX := 40.0
## The director keeps its subject at least this long (s) unless another
## scores SWITCH_RATIO times better, and changes zoom only after the same
## new zoom has been wanted ZOOM_VOTES looks running, one step at a time.
const DWELL_SECONDS := 8.0
const SWITCH_RATIO := 1.5
## ...and by at least this much (scores are small numbers: a ratio alone
## swings between two quiet spots).
const SWITCH_LEAD := 2.0
## A fresh subject is kept at least this long (s), unless it is gone.
const MIN_HOLD_SECONDS := 5.0
const ZOOM_VOTES := 8
## After a zoom step, the next waits at least this long (s).
const ZOOM_HOLD_SECONDS := 6.0
## A unit with an enemy this near (px) is in the action; others count less.
const CONTACT_PX := 160.0
const IDLE_WEIGHT := 0.25
## Logs each switch and zoom change (KIT_SHOWREEL_LOG=1).
var _log := OS.get_environment("KIT_SHOWREEL_LOG") == "1"
var _chosen_tick := -100000
var _score := 0.0
var _wanted_zoom := 3.0
var _votes := 0
var _zoomed_tick := -100000

var game: TtwSkirmish
var frames := 10800
var map := &"river"
var _bursts: Array = []
var _focus := Vector2.ZERO
var _zoom_target := 3.0
var _velocity := Vector2.ZERO
var _zoom_velocity := 0.0
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
	game.camera.zoom = Vector2.ONE * 3.0
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


func _process(delta: float) -> void:
	_frame += 1
	if _frame % LOOK_EVERY == 1:
		_direct()
	var camera := game.camera
	var z := _spring_zoom(camera.zoom.x, _zoom_target, delta)
	camera.zoom = Vector2.ONE * z
	camera.position = _spring_move(camera.position, _clamped(_focus, z), delta)
	_caption.modulate.a = clampf(1.0 - (_frame - 300) / 60.0, 0.0, 1.0)
	if _frame >= frames:
		get_tree().quit()

## Critically damped springs (no overshoot), easing toward their targets.
static func _spring_step(change: float, velocity: float, dt: float, settle: float) -> Vector2:
	var omega := 4.0 / settle
	var x := omega * dt
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var temp := (velocity + omega * change) * dt
	return Vector2((change + temp) * decay, (velocity - omega * temp) * decay)

func _spring_move(at: Vector2, to: Vector2, dt: float) -> Vector2:
	var sx := _spring_step(at.x - to.x, _velocity.x, dt, MOVE_TIME)
	var sy := _spring_step(at.y - to.y, _velocity.y, dt, MOVE_TIME)
	_velocity = Vector2(sx.y, sy.y)
	return to + Vector2(sx.x, sy.x)

func _spring_zoom(at: float, to: float, dt: float) -> float:
	var s := _spring_step(at - to, _zoom_velocity, dt, ZOOM_TIME)
	_zoom_velocity = s.y
	return to + s.x

## A view at `zoom` centred on `at`, kept inside the map.
func _clamped(at: Vector2, zoom: float) -> Vector2:
	var half := get_viewport().get_visible_rect().size / zoom * 0.5
	var size := game.terrain.size_px()
	return Vector2(clampf(at.x, half.x, maxf(half.x, size.x - half.x)), clampf(at.y, half.y, maxf(half.y, size.y - half.y)))

## Scores the gathering round each point: units in contact with an enemy
## count 1, other units IDLE_WEIGHT, recent bursts 2 (fading). Returns
## [centre, score, lo, hi] of the best, or of the one round `around` when
## given (to score the subject being watched).
func _gathering(points: Array, around: Variant = null) -> Array:
	var best: Array = []
	var best_weight := -1.0
	var seeds: Array = points if around == null else [[around, 0.0]]
	for p in seeds:
		var lo: Vector2 = p[0]
		var hi: Vector2 = p[0]
		var sum := Vector2.ZERO
		var weight := 0.0
		for q in points:
			if (q[0] as Vector2).distance_to(p[0]) <= GATHER_PX:
				weight += q[1]
				sum += (q[0] as Vector2) * q[1]
				lo = lo.min(q[0])
				hi = hi.max(q[0])
		if weight > best_weight:
			best_weight = weight
			best = [sum / weight if weight > 0.0 else p[0], weight, lo, hi]
	return best

func _points() -> Array:
	var now := game.session.tick
	_bursts = _bursts.filter(func(b): return now - b[0] < INTEREST_SECONDS * 60.0)
	var units := game.session.view([TtwUnit, TtwTeam, KitBody]).filter(func(u): return not u.has_component(TtwWrecked))
	var points: Array = []
	for unit in units:
		var at := game.session.body_of(unit).position
		var contact := false
		for other in units:
			if TtwTeam.of(other) != TtwTeam.of(unit) and game.session.body_of(other).position.distance_to(at) <= CONTACT_PX:
				contact = true
				break
		points.append([at, 1.0 if contact else IDLE_WEIGHT])
	for b in _bursts:
		points.append([b[1], 2.0 * (1.0 - float(now - b[0]) / (INTEREST_SECONDS * 60.0))])
	return points

## Picks what to watch, and how close: keeps its subject for DWELL_SECONDS
## unless something scores SWITCH_RATIO times better; follows the subject as
## it moves; changes zoom only after ZOOM_VOTES looks agree, a step at a time.
func _direct() -> void:
	var points := _points()
	if points.is_empty():
		return
	var now := game.session.tick
	var best := _gathering(points)
	var current := _gathering(points, _focus)
	var dwelt := now - _chosen_tick >= DWELL_SECONDS * 60.0
	var held := now - _chosen_tick >= MIN_HOLD_SECONDS * 60.0
	var gone: bool = current.is_empty() or current[1] <= 0.0
	var subject := current
	var lead: float = best[1] - (current[1] if not current.is_empty() else 0.0)
	var much_better: bool = current.is_empty() or (best[1] > current[1] * SWITCH_RATIO and lead >= SWITCH_LEAD)
	var better_after_dwell: bool = dwelt and best[1] > current[1] * 1.25 and lead >= SWITCH_LEAD * 0.5
	if gone or (held and (much_better or better_after_dwell)):
		if current.is_empty() or (best[0] as Vector2).distance_to(current[0]) > GATHER_PX:
			# Far away: pull out to the wide view to travel, then close in again.
			var view_w := get_viewport().get_visible_rect().size.x / game.camera.zoom.x
			if not current.is_empty() and (best[0] as Vector2).distance_to(current[0]) > view_w * 0.5:
				_zoom_target = ZOOM_WIDE
				_zoomed_tick = now
				_votes = 0
			_chosen_tick = now
			if _log:
				print("SHOWREEL %6.1f s  switch to %s (score %.1f, was %.1f)" % [now / 60.0, best[0], best[1], current[1] if not current.is_empty() else 0.0])
		subject = best
	# Follow the subject (its centre moves as it does).
	if (subject[0] as Vector2).distance_to(_focus) > MOVE_SLACK_PX:
		_focus = subject[0]
	# The zoom that fits it: close when it is busy, wide when quiet.
	var fit := ZOOM_WIDE
	if subject[1] >= 3.0:
		var box: Vector2 = (subject[3] - subject[2]) + Vector2.ONE * MARGIN_PX * 2.0
		var view := get_viewport().get_visible_rect().size
		fit = clampf(floorf(minf(view.x / maxf(box.x, 1.0), view.y / maxf(box.y, 1.0))), ZOOM_WIDE, ZOOM_CLOSE)
	if fit == _wanted_zoom:
		_votes += 1
	else:
		_wanted_zoom = fit
		_votes = 1
	if _votes >= ZOOM_VOTES and fit != _zoom_target and now - _zoomed_tick >= ZOOM_HOLD_SECONDS * 60.0:
		_zoom_target += signf(fit - _zoom_target)
		_zoomed_tick = now
		_votes = 0
		if _log:
			print("SHOWREEL %6.1f s  zoom %d" % [now / 60.0, int(_zoom_target)])
