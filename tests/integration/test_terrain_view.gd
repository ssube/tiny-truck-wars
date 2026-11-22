extends GdUnitTestSuite
## The terrain view uploads only what is on screen; an off-screen chunk keeps
## its change until it comes into view. What it has uploaded is the ground.

const Simulation := preload("res://tests/support/simulation.gd")

func test_off_screen_changes_wait_until_the_chunk_is_in_view() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var t := TtwTerrain.new(Vector2i(80, 80))
	var view := TtwTerrainView.new()
	holder.add_child(view)
	view.show_terrain(t)
	var camera := Camera2D.new()
	camera.zoom = Vector2(3, 3)
	camera.position = Vector2(100, 100)
	holder.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var far_corner := t.size_px() - Vector2(20, 20)
	TtwBrushes.paint(t, TtwBrushes.Kind.DIG, far_corner, 6.0, 3.0)
	TtwBrushes.paint(t, TtwBrushes.Kind.DIG, Vector2(100, 100), 6.0, 3.0)
	var far_chunk := t.cell_of(far_corner) / TtwTerrain.CHUNK_CELLS
	var near_chunk := t.cell_of(Vector2(100, 100)) / TtwTerrain.CHUNK_CELLS
	view.refresh()
	assert_bool(t.is_chunk_dirty(near_chunk)).is_false()
	assert_bool(t.is_chunk_dirty(far_chunk)).is_true()
	assert_bool(view.chunk_at(far_chunk).visible).is_false()
	camera.position = far_corner
	camera.force_update_scroll()
	view.refresh()
	assert_bool(t.is_chunk_dirty(far_chunk)).is_false()
	assert_bool(view.chunk_at(far_chunk).visible).is_true()
	holder.queue_free()

## A writer that says which layers it wrote (a press, settling) has only
## those uploaded. Whoever takes just the marked layers of each chunk every
## tick, as the view does, must end each tick holding the ground as it is: a
## layer written but not marked would be left stale here.
func test_taking_only_the_marked_layers_keeps_every_layer_current() -> void:
	var game := TtwGame.new()
	add_child(game)
	game.load_ground(TtwMapGen.mud_lab(Vector2i(32, 32)))
	# The view would take the marks itself: this test is the only taker.
	game.view.set_process(false)
	var t := game.terrain
	var at := t.size_px() * 0.5
	TtwBrushes.paint(t, TtwBrushes.Kind.WET, at, 60.0, 1.0)
	TtwBrushes.paint(t, TtwBrushes.Kind.LOOSE, at + Vector2(40, 0), 12.0, 2.0)
	var tank := game.spawn_unit(&"tank", at - Vector2(60, 0), 0.4, 1)
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	TtwStamps.crater(t, at + Vector2(0, 50), &"rocket")
	TtwOil.spill(t, game.water, at + Vector2(-30, -40), 2.0, 10.0)
	var held := {}
	var stale: Array[String] = []
	var taken := [0, 0]
	var take := func() -> void:
		for cy in t.chunks.y:
			for cx in t.chunks.x:
				var chunk := Vector2i(cx, cy)
				var marked: int = t.chunk_dirty_layers(chunk) if held.has(chunk) else TtwTerrain.ALL_LAYERS
				var layers: Array = held.get_or_add(chunk, [])
				layers.resize(TtwTerrain.LAYER_COUNT)
				for layer in TtwTerrain.LAYER_COUNT:
					var now := t.chunk_image(layer, chunk).get_data()
					taken[1] += 1
					if (marked & (1 << layer)) != 0:
						layers[layer] = now
						taken[0] += 1
					elif layers[layer] != now and stale.size() < 8:
						stale.append("tick %d chunk %s layer %d" % [game.session.tick, chunk, layer])
				t.clean_chunk(chunk)
	take.call()
	# Two sweeps of the settling queue, the tank pressing ruts all the while.
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), 2 * TtwSettleSystem.PERIOD_TICKS, 10.0, take)
	assert_bool(result.success).is_true()
	assert_array(stale).is_empty()
	# And the marks do leave layers out: that is what they are for.
	assert_int(taken[0]).is_less(taken[1])
	game.queue_free()

## The view sends the water's level, current and depth once per water step
## that changed them, with no oil on the water, and not again until the
## water changes once more. Oil afloat is sent on its own flag. (Headless,
## textures cannot be read back: this checks what is sent and when.)
func test_water_maps_are_sent_when_the_water_changes() -> void:
	var game := TtwGame.new()
	add_child(game)
	game.load_ground(TtwMapGen.mud_lab(Vector2i(32, 32)))
	game.view.set_process(false)
	var t := game.terrain
	game.view.refresh()
	assert_float(game.water.slick_total).is_equal(0.0)
	game.view.refresh()
	assert_bool(t.water_dirty).is_false()
	# A pour reaches the maps on the next water step (one in STEP_TICKS).
	var at := t.size_px() * 0.5
	var i := t.tile_index(t.tile_of(at))
	game.water.pour(at, 400.0, 24.0)
	var ticked := await Simulation.physics_ticks(get_tree(), TtwWater.STEP_TICKS)
	assert_bool(ticked.success).is_true()
	assert_bool(t.water_dirty).is_true()
	assert_float(t.water[i]).is_greater(TtwTerrain.NO_WATER)
	var depth := game.water.depth_image()
	assert_float(depth.get_pixelv(t.tile_of(at)).r).is_equal_approx(game.water.depth[i], 0.001)
	assert_float(game.water.depth[i]).is_greater(0.0)
	game.view.refresh()
	# Sent once and done: with no oil afloat, the flag no longer stays up.
	assert_bool(t.water_dirty).is_false()
	# Oil afloat is sent on its own flag, the same frame it is spilt, and
	# leaves the water's flag alone.
	game.water.add_slick(i, 1.5)
	assert_bool(game.water.slick_dirty).is_true()
	game.view.refresh()
	assert_bool(game.water.slick_dirty).is_false()
	assert_bool(t.water_dirty).is_false()
	game.queue_free()
