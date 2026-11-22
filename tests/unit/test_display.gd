extends GdUnitTestSuite
## The picture is enlarged by whole factors only, so a world pixel covers a
## whole number of screen pixels: the largest factor at which the 1280×720
## layout still fits the window.

const Display := preload("res://game/display.gd")

func test_the_factor_is_the_largest_whole_one_that_fits() -> void:
	assert_int(Display.factor_for(Vector2i(1280, 720))).is_equal(1)
	# 1.5 times the layout: still 1, with a 1920×1080 view.
	assert_int(Display.factor_for(Vector2i(1920, 1080))).is_equal(1)
	assert_int(Display.factor_for(Vector2i(2559, 1439))).is_equal(1)
	assert_int(Display.factor_for(Vector2i(2560, 1440))).is_equal(2)
	assert_int(Display.factor_for(Vector2i(3840, 2160))).is_equal(3)
	# The tighter side decides, and a window smaller than the layout is not shrunk.
	assert_int(Display.factor_for(Vector2i(3840, 1080))).is_equal(1)
	assert_int(Display.factor_for(Vector2i(800, 600))).is_equal(1)

func test_the_view_fills_the_window_at_that_factor() -> void:
	var window := get_tree().root
	var size := window.size
	assert_vector(Vector2(window.content_scale_size)).is_equal(Vector2(size / Display.factor_for(size)))
