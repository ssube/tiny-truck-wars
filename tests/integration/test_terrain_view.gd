extends GdUnitTestSuite
## The terrain view uploads only what is on screen; an off-screen chunk keeps
## its change until it comes into view.

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
