extends GdUnitTestSuite
## The real entry scene starts a session that ticks.

const Simulation := preload("res://tests/support/simulation.gd")

func test_main_scene_starts_a_ticking_session() -> void:
	var game: TtwGame = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	var start := game.session.tick
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), 2, 1.0)
	assert_bool(result.success).is_true()
	assert_int(game.session.tick - start).is_equal(2)
	game.queue_free()
