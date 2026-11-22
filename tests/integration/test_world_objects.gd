extends GdUnitTestSuite
## Trees, logs and buildings in the running game: they block vehicles, fall
## and collapse the way they should.

const Simulation := preload("res://tests/support/simulation.gd")

var game: TtwGame

func before_test() -> void:
	game = TtwGame.new()
	add_child(game)

func after_test() -> void:
	game.queue_free()

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 2.0)
	assert_bool(result.success).is_true()

## Clear flat ground away from the test map's own props.
func _clear_ground(at: Vector2) -> void:
	var tile := game.terrain.tile_of(at)
	for y in range(tile.y - 4, tile.y + 5):
		for x in range(tile.x - 8, tile.x + 9):
			game.terrain.set_material(Vector2i(x, y), TtwMaterials.PAVEMENT)

func test_a_log_stops_a_truck_until_it_is_destroyed() -> void:
	var at := Vector2(160, 560)
	_clear_ground(at)
	var log := game.spawn_prop(&"log", at, PI / 2)
	var truck := game.spawn_unit(&"truck", at - Vector2(60, 0), 0.0)
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	# Distance to the log at full speed, plus the time to reach it.
	var drive: TtwDrive = truck.get_component(TtwDrive)
	await _ticks(ceili(60.0 / Kit2D.tiles(drive.max_speed_tiles) * 60.0) + 60)
	var body := game.session.body_of(truck)
	var v: TtwVehicle = truck.get_component(TtwVehicle)
	var reach := v.gauge_px * 0.5 + v.contact_width_px * 0.5
	assert_float(body.position.x).is_less_equal(at.x - 4.0 - reach + 0.01)
	TtwDamage.hurt(game.session, log, 1000.0, body.position)
	await _ticks(60)
	assert_float(body.position.x).is_greater(at.x + 4.0)

func test_a_tree_knocked_down_by_a_blast_lies_away_from_it() -> void:
	var at := Vector2(160, 560)
	_clear_ground(at)
	var tree := game.spawn_prop(&"tree_oak", at)
	var blast := at + Vector2(-30, 0)
	TtwDamage.blast(game.session, blast, 60.0, 500.0)
	assert_bool((tree.get_component(TtwHealth) as TtwHealth).destroyed).is_true()
	await _ticks(ceili(TtwTree2D.FALL_SECONDS * 60.0) + 4)
	var logs := game.session.view([TtwLog, KitBody])
	assert_int(logs.size()).is_equal(1)
	var lying := game.session.body_of(logs[0])
	assert_float(lying.position.x).is_greater(at.x)
	assert_float(absf(angle_difference(lying.rotation, 0.0))).is_less(0.05)

func test_a_tank_rams_a_tree_down() -> void:
	var at := Vector2(200, 560)
	_clear_ground(at)
	var tree := game.spawn_prop(&"tree_pine", at)
	# The component outlives the tree's entity (retired once it has fallen).
	var health: TtwHealth = tree.get_component(TtwHealth)
	var tank := game.spawn_unit(&"tank", at - Vector2(80, 0), 0.0)
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(180)
	assert_bool(health.destroyed).is_true()

func test_a_destroyed_building_leaves_a_crater_and_rubble() -> void:
	var at := Vector2(200, 600)
	_clear_ground(at)
	var house := game.spawn_prop(&"house", at)
	var o: TtwObstacle = house.get_component(TtwObstacle)
	var center := at + o.offset
	TtwDamage.hurt(game.session, house, 10000.0, at + Vector2(0, 40))
	assert_object(game.session.resolve(str(house.alias))).is_null()
	assert_int(game.terrain.material_at(center)).is_equal(TtwMaterials.GRAVEL)
	assert_float(game.terrain.cell_value(TtwTerrain.Layer.SCORCH, game.terrain.cell_of(center))).is_greater(0.0)

func test_a_tree_in_a_burning_tile_burns_down() -> void:
	var at := Vector2(240, 560)
	_clear_ground(at)
	var tree := game.spawn_prop(&"tree_oak", at)
	var health: TtwHealth = tree.get_component(TtwHealth)
	var field := TtwGround.fire_of(game.session)
	assert_bool(field.ignite(game.terrain.tile_of(at), 1.0)).is_true()
	# Its health at full heat, in fire steps.
	var seconds := health.max_health / TtwFireSystem.BURN_DAMAGE
	await _ticks(ceili(seconds * 60.0) + TtwFireSystem.STEP_TICKS * 4)
	assert_bool(health.destroyed).is_true()
