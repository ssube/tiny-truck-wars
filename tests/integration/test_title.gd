extends GdUnitTestSuite
## The title screen: a skirmish on the map picked, the Mud Lab, the saved
## game when there is one, and the way back from the game's menu.

const UI := preload("res://tests/support/ui.gd")
const Simulation := preload("res://tests/support/simulation.gd")

func after_test() -> void:
	for child in get_children():
		if child is TtwTitle or child is TtwGame or child is TtwMudLab:
			child.queue_free()
	get_tree().paused = false

func _title() -> TtwTitle:
	var title: TtwTitle = (load(TtwTitle.TITLE) as PackedScene).instantiate()
	add_child(title)
	return title

func _only(kind: Variant) -> Node:
	var found := get_children().filter(func(c): return is_instance_of(c, kind) and not c.is_queued_for_deletion())
	assert_int(found.size()).is_equal(1)
	return found[0] if not found.is_empty() else null

func test_a_map_button_starts_a_skirmish_on_that_map() -> void:
	var title := _title()
	assert_bool(UI.press(title, "title_play_snowfield")).is_true()
	var game: TtwSkirmish = _only(TtwSkirmish)
	assert_str(String(game.map_name)).is_equal("snowfield")
	await Simulation.physics_ticks(get_tree(), 1, 2.0)
	assert_object(game.terrain).is_not_null()
	assert_bool(is_instance_valid(title) and not title.is_queued_for_deletion()).is_false()

func test_the_mud_lab_button_opens_the_mud_lab() -> void:
	var title := _title()
	assert_bool(UI.press(title, "title_mud_lab")).is_true()
	assert_object(_only(TtwMudLab)).is_not_null()

func test_load_is_offered_only_with_a_saved_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TtwSkirmish.QUICK_SAVE))
	var title := _title()
	var button: Button = UI.find_by_test_id(title, "title_load")
	assert_bool(button.disabled).is_true()

func test_the_games_menu_goes_back_to_the_title() -> void:
	var title := _title()
	UI.press(title, "title_play_river")
	var game: TtwSkirmish = _only(TtwSkirmish)
	game.menu.open()
	assert_bool(UI.press(game.menu, "menu_title")).is_true()
	assert_object(_only(TtwTitle)).is_not_null()
	assert_bool(get_tree().paused).is_false()
