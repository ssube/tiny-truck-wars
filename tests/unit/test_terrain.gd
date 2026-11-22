extends GdUnitTestSuite
## The ground's layers: addressing, chunk images with their apron, dirty
## marks, and the brushes' effect on the values gameplay reads.

func test_a_chunk_image_carries_its_cells_and_the_apron_around_them() -> void:
	var t := TtwTerrain.new(Vector2i(48, 32))
	var inside := Vector2i(TtwTerrain.CHUNK_CELLS + 5, 9)  # in chunk (1, 0)
	var neighbour := Vector2i(TtwTerrain.CHUNK_CELLS - 3, 9)  # in chunk (0, 0), in (1, 0)'s apron
	t.set_cell(TtwTerrain.Layer.DEFORM, inside, -4.0)
	t.set_cell(TtwTerrain.Layer.DEFORM, neighbour, 2.5)
	var image := t.chunk_image(TtwTerrain.Layer.DEFORM, Vector2i(1, 0))
	assert_int(image.get_width()).is_equal(TtwTerrain.CHUNK_TEXELS)
	var origin := Vector2i(1, 0) * TtwTerrain.CHUNK_CELLS - Vector2i(TtwTerrain.APRON, TtwTerrain.APRON)
	assert_float(image.get_pixelv(inside - origin).r).is_equal(-4.0)
	assert_float(image.get_pixelv(neighbour - origin).r).is_equal(2.5)

func test_outside_the_map_a_chunk_repeats_the_edge_cells() -> void:
	var t := TtwTerrain.new(Vector2i(16, 16))
	t.set_cell(TtwTerrain.Layer.WET, Vector2i(0, 0), 0.75)
	var image := t.chunk_image(TtwTerrain.Layer.WET, Vector2i.ZERO)
	# Texel (0, 0) is APRON cells up and left of the map's corner.
	assert_float(image.get_pixel(0, 0).r).is_equal(0.75)
	assert_float(image.get_pixel(TtwTerrain.APRON, TtwTerrain.APRON).r).is_equal(0.75)

func test_a_change_marks_every_chunk_that_shows_it() -> void:
	var t := TtwTerrain.new(Vector2i(48, 48))
	for y in t.chunks.y:
		for x in t.chunks.x:
			t.clean_chunk(Vector2i(x, y))
	# A cell within APRON of chunk (1, 0)'s left edge is in both chunks' images.
	t.set_cell(TtwTerrain.Layer.DEFORM, Vector2i(TtwTerrain.CHUNK_CELLS - 2, 3), -1.0)
	assert_bool(t.is_chunk_dirty(Vector2i(0, 0))).is_true()
	assert_bool(t.is_chunk_dirty(Vector2i(1, 0))).is_true()
	assert_bool(t.is_chunk_dirty(Vector2i(2, 0))).is_false()
	assert_bool(t.is_chunk_dirty(Vector2i(0, 1))).is_false()

func test_elevation_is_bilinear_between_tile_centres() -> void:
	var t := TtwTerrain.new(Vector2i(4, 1))
	t.set_elevation(Vector2i(1, 0), 0.0)
	t.set_elevation(Vector2i(2, 0), 10.0)
	var tile := TtwTerrain.tile_px()
	assert_float(t.elevation_at(Vector2(1.5 * tile, 0.5 * tile))).is_equal_approx(0.0, 0.001)
	assert_float(t.elevation_at(Vector2(2.0 * tile, 0.5 * tile))).is_equal_approx(5.0, 0.001)
	assert_float(t.elevation_at(Vector2(2.5 * tile, 0.5 * tile))).is_equal_approx(10.0, 0.001)

func test_water_painted_to_a_level_fills_ruts_and_leaves_flat_ground_dry() -> void:
	var t := TtwTerrain.new(Vector2i(8, 8))
	var rut := Vector2(40, 40)
	var flat := Vector2(56, 40)
	TtwBrushes.paint(t, TtwBrushes.Kind.DIG, rut, 3.0, 6.0)
	assert_float(t.relief_at(rut)).is_less(-3.0)
	assert_float(t.water_depth_at(rut)).is_equal(0.0)
	TtwBrushes.paint(t, TtwBrushes.Kind.WATER, Vector2(48, 40), 24.0, -1.0)
	assert_float(t.water_depth_at(rut)).is_greater(2.0)
	assert_float(t.water_depth_at(flat)).is_equal(0.0)

func test_brushes_keep_wetness_and_tracks_in_range() -> void:
	var t := TtwTerrain.new(Vector2i(8, 8))
	var at := Vector2(64, 64)
	for i in 20:
		TtwBrushes.paint(t, TtwBrushes.Kind.WET, at, 8.0, 0.4)
		TtwBrushes.paint(t, TtwBrushes.Kind.TRACK, at, 8.0, 0.4, 1.25)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, t.cell_of(at))).is_equal(1.0)
	assert_float(t.cell_value(TtwTerrain.Layer.TRACK, t.cell_of(at))).is_equal(1.0)
	assert_float(t.cell_value(TtwTerrain.Layer.TRACK_ANGLE, t.cell_of(at))).is_equal_approx(1.25, 0.0001)
	for i in 20:
		TtwBrushes.paint(t, TtwBrushes.Kind.DRY, at, 8.0, 0.4)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, t.cell_of(at))).is_equal(0.0)

func test_lod_tier_holds_at_a_band_edge_and_switches_past_it() -> void:
	var edge: float = TtwTerrainView.BANDS[0]
	var h := TtwTerrainView.HYSTERESIS
	var zoom := 3.0
	# Leaving FULL needs the edge plus the hysteresis.
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, edge, zoom)).is_equal(TtwTerrainView.Tier.FULL)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, edge + h * 0.9, zoom)).is_equal(TtwTerrainView.Tier.FULL)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, edge + h * 1.1, zoom)).is_equal(TtwTerrainView.Tier.MID)
	# Coming back needs the edge minus the hysteresis.
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.MID, edge, zoom)).is_equal(TtwTerrainView.Tier.MID)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.MID, edge - h * 0.9, zoom)).is_equal(TtwTerrainView.Tier.MID)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.MID, edge - h * 1.1, zoom)).is_equal(TtwTerrainView.Tier.FULL)

func test_zooming_out_makes_every_tier_cheaper() -> void:
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, 0.0, TtwTerrainView.ZOOM_MID)).is_equal(TtwTerrainView.Tier.FULL)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, 0.0, TtwTerrainView.ZOOM_MID - 0.01)).is_equal(TtwTerrainView.Tier.MID)
	assert_int(TtwTerrainView.tier_for(TtwTerrainView.Tier.FULL, 0.0, TtwTerrainView.ZOOM_FAR - 0.01)).is_equal(TtwTerrainView.Tier.FAR)

## Water has no colour of its own unless a map gives it one (alpha 0: the
## shader's own clear-water colours), on a new ground and on the river map;
## the snowfield's lake has its own.
func test_water_has_no_colour_of_its_own_unless_a_map_gives_it() -> void:
	var plain := TtwTerrain.new(Vector2i(4, 4))
	for c in plain.water_color:
		assert_float(c.a).is_equal(0.0)
	var river := TtwSkirmishMap.terrain()
	for c in river.water_color:
		assert_float(c.a).is_equal(0.0)
	var snow := TtwSnowfieldMap.terrain()
	var lake := 0
	for c in snow.water_color:
		if c.a > 0.0:
			lake += 1
			assert_float(c.b).is_greater(c.r)
	assert_int(lake).is_greater(0)

## A save from 0.2.2 or 0.2.3, made when every tile's water colour started as
## opaque black, loads with none; one with a colour of its own keeps it.
func test_a_save_with_the_old_black_water_loads_with_none() -> void:
	var t := TtwTerrain.new(Vector2i(4, 4))
	t.water_color.fill(Color(0, 0, 0, 1))
	TtwSave._clear_unset_water_color(t)
	for c in t.water_color:
		assert_float(c.a).is_equal(0.0)
	t.water_color.fill(Color(0, 0, 0, 1))
	t.water_color[3] = Color(0.4, 0.6, 0.7, 0.7)
	TtwSave._clear_unset_water_color(t)
	assert_float(t.water_color[0].a).is_equal(1.0)
	assert_float(t.water_color[3].a).is_equal_approx(0.7, 0.001)
