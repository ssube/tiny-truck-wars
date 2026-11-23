extends RefCounted
## The stress scene of the perf probe, shared with the hash tool
## (tools/hash_run.gd): 100 units of every kind, two sides, driving and flying
## over a 128×128-tile map with its river, a third on routes, a rocket crater
## every CRATER_EVERY ticks. Everything comes from fixed seeds and the session's
## tick, so two runs of the same source on fixed ticks end the same.
## `winter` lays snow over the whole map and spills oil about, so the snow
## and oil presses run too.

const VEHICLES := 100
const KINDS := [&"tank", &"wrecker", &"hippy", &"boss", &"nurse", &"tank", &"gunship", &"tanker", &"engineer", &"water_tanker", &"bucket_heli", &"tank"]
const CRATER_EVERY := 30
## Winter: snow on every tile (px), and oil spills (count, amount, radius px).
const WINTER_SNOW := 3.0
const SPILLS := 40
const SPILL_AMOUNT := 4.0
const SPILL_RADIUS_PX := 40.0

var game: TtwGame
var size: Vector2
## Crater places, apart from the units' seed so either can change alone.
var _craters := RandomNumberGenerator.new()
var _tree: SceneTree

## Builds the scene under `parent` (the game is its child; free it with
## free_game()). Craters go off from the next physics tick on.
func _init(parent: Node, winter: bool = false) -> void:
	game = TtwGame.new()
	parent.add_child(game)
	var terrain := TtwMapGen.mud_lab(Vector2i(128, 128))
	if winter:
		terrain.snow_base.fill(WINTER_SNOW)
	game.load_ground(terrain)
	size = game.terrain.size_px()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if winter:
		var water := TtwGround.water_of(game.session)
		for k in SPILLS:
			TtwOil.spill(game.terrain, water, Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y), SPILL_AMOUNT, SPILL_RADIUS_PX)
	for k in VEHICLES:
		var at := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y)
		var unit := game.spawn_unit(KINDS[k % KINDS.size()], at, rng.randf() * TAU, 1 + k % 2)
		var drive: TtwDrive = unit.get_component(TtwDrive)
		if drive != null:
			drive.throttle = 1.0
			drive.steer = rng.randf_range(-0.4, 0.4)
		if k % 3 == 0 or drive == null:
			# A third drive routes the path grid finds.
			TtwPilotSystem.order(unit, Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y))
	_craters.seed = 29
	_tree = parent.get_tree()
	_tree.physics_frame.connect(_on_tick)

## Stops the craters and frees the game.
func free_game() -> void:
	if _tree.physics_frame.is_connected(_on_tick):
		_tree.physics_frame.disconnect(_on_tick)
	game.queue_free()

## Before each physics tick: a crater on every CRATER_EVERY-th.
func _on_tick() -> void:
	if not is_instance_valid(game):
		return
	if game.session.tick % CRATER_EVERY == 0:
		var at := Vector2(_craters.randf() * size.x, _craters.randf() * size.y)
		TtwStamps.crater(game.terrain, at, &"rocket")
		game.fx.explode(at, &"rocket")
