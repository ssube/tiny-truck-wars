extends GdUnitTestSuite
## Trees, logs and buildings in the running game: they block vehicles, fall
## and collapse the way they should.

const Simulation := preload("res://tests/support/simulation.gd")
const UI := preload("res://tests/support/ui.gd")

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
	# A heap stands on the footprint's front edge, its foot there whatever
	# picture it got, and a save brings the same heap back.
	var heaps := get_tree().get_nodes_in_group(TtwSave.RUBBLE_GROUP)
	assert_int(heaps.size()).is_equal(1)
	var heap: Sprite2D = heaps[0]
	var used := heap.texture.get_image().get_used_rect()
	var foot := heap.position + Vector2(used.get_center().x, used.end.y - 1)
	assert_vector(foot).is_equal_approx(center + Vector2(0, o.half_extents.y), Vector2(1, 1))
	var again := TtwRubble.restore(game.units, TtwRubble.record(heap))
	assert_vector(again.position).is_equal(heap.position)
	assert_object(again.texture).is_same(heap.texture)

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

## Every building's footprint (what blocks vehicles and shells) lies within
## its picture, standing on the picture's foot: a new sprite of another size
## with the old footprint would block ground that shows nothing, or let
## vehicles drive through walls.
func test_every_building_stands_inside_its_picture() -> void:
	for kind in TtwGame.PROP_SCENES:
		var body := (load(TtwGame.PROP_SCENES[kind]) as PackedScene).instantiate()
		if body is TtwBuilding2D:
			var b := body as TtwBuilding2D
			var pictures: Array[Texture2D] = [b.art]
			pictures.append_array(b.variants)
			# The narrowest of its pictures.
			var used := Rect2i(0, 0, 1 << 20, 1 << 20)
			for picture in pictures:
				var r := picture.get_image().get_used_rect()
				used.size = Vector2i(mini(used.size.x, r.size.x), mini(used.size.y, r.size.y))
			var o: TtwObstacle = b.obstacle
			assert_float(o.half_extents.x * 2.0).override_failure_message("%s: footprint %s wider than its picture %s" % [kind, o.half_extents.x * 2.0, used.size.x]).is_less_equal(used.size.x)
			# The footprint's front edge is the picture's foot (origin).
			assert_float(o.offset.y + o.half_extents.y).override_failure_message("%s: footprint not on its foot" % kind).is_equal_approx(0.0, 0.01)
			assert_float(o.half_extents.y * 2.0).is_less_equal(used.size.y)
		body.free()

## A tree with several pictures shows one of them chosen by where it stands
## (a loaded save, which puts it back on its spot, shows the same tree), its
## trunk's foot on that spot.
func test_a_tree_picks_its_picture_by_its_spot() -> void:
	var seen := {}
	for k in 12:
		var at := Vector2(100 + k * 37, 300)
		var tree := game.session.body_of(game.spawn_prop(&"tree_pine", at)) as TtwTree2D
		assert_bool(tree.variants.has(tree.art)).is_true()
		seen[tree.art] = true
		var again := game.session.body_of(game.spawn_prop(&"tree_pine", at)) as TtwTree2D
		assert_object(again.art).is_same(tree.art)
		var sprite: Sprite2D = tree.get_child(0).get_child(0)
		var used := tree.art.get_image().get_used_rect()
		assert_float(sprite.position.y + used.end.y - 1).is_equal(1.0)
	assert_int(seen.size()).is_greater(1)

## A wrecker's beacon lights the ground and water around it: a light on the
## ground effects layer (under the units, over the terrain and its water),
## flashing with the beacon (the same phase), carried along as it moves,
## and dark, with the beacon, once it is destroyed.
func test_a_wreckers_beacon_lights_the_ground_around_it() -> void:
	var at := Vector2(300, 400)
	var wrecker := game.spawn_unit(&"wrecker", at, 0.0, 1)
	var tanker := game.spawn_unit(&"tanker", at + Vector2(80, 0), 0.0, 1)
	# Each body's frame update, called here: a physics tick ends before the
	# frame's _process runs.
	var body := game.session.body_of(wrecker) as TtwVehicle2D
	var tanker_body := game.session.body_of(tanker) as TtwVehicle2D
	body._process(0.0)
	tanker_body._process(0.0)
	var light := body.get("_glow") as Sprite2D
	assert_object(light).is_not_null()
	assert_object(light.get_parent()).is_same(game.fx.ground)
	assert_bool(light.visible).is_true()
	assert_float(light.material.get_shader_parameter("beacon_phase")).is_equal(body.sprite.material.get_shader_parameter("beacon_phase"))
	assert_object(tanker_body.get("_glow")).is_null()
	# The engine carries it along as the wrecker moves: a RemoteTransform2D
	# on the wrecker drives it (position only, no script each frame).
	var carriers := body.get_children().filter(func(n): return n is RemoteTransform2D)
	assert_int(carriers.size()).is_equal(1)
	var carry: RemoteTransform2D = carriers[0]
	assert_object(carry.get_node(carry.remote_path)).is_same(light)
	assert_bool(carry.update_position).is_true()
	assert_bool(carry.update_rotation).is_false()
	assert_bool(carry.update_scale).is_false()
	# Destroyed by a shot: it goes up, stays as a wreck, and its beacon stops
	# flashing (the sprite's pixels and the light both).
	TtwDamage.hurt(game.session, wrecker, 1.0e6, at - Vector2(40, 0))
	assert_bool(wrecker.has_component(TtwWrecked)).is_true()
	body._process(0.0)
	assert_float(body.sprite.material.get_shader_parameter("beacon")).is_equal(0.0)
	assert_bool(light.visible).is_false()
	# Gone with the wrecker, as its body leaves the tree.
	var gone := UI.observe(body.tree_exited)
	game.session.retire(wrecker)
	var left: Dictionary = await gone.wait(get_tree(), 1.0)
	assert_bool(left.received).is_true()
	assert_bool(not is_instance_valid(light) or light.is_queued_for_deletion()).is_true()
