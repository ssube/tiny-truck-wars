extends GdUnitTestSuite
## What wheels, treads and explosions do to the ground.

const Fixture := preload("res://tests/support/world.gd")

func _volume(t: TtwTerrain) -> float:
	return t.layer_total(TtwTerrain.Layer.DEFORM) + t.layer_total(TtwTerrain.Layer.LOOSE)

## One pass of a tread over a row: a press per cell, like a vehicle driving.
func _pass(t: TtwTerrain, y: float, from_x: float, to_x: float, sink: float, carried: float = 0.0) -> float:
	var step := TtwTerrain.cell_px()
	var x := from_x
	while x < to_x:
		carried = TtwStamps.press(t, Vector2(x + step * 0.5, y), 0.0, step, 6.0, sink, 0.0, carried)
		x += step
	return carried

func test_a_press_on_mud_moves_volume_and_makes_none() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var carried := 0.0
	for i in 10:
		carried = _pass(t, 64.0, 40.0, 200.0, 1.6, carried)
		assert_float(_volume(t) + carried).is_equal_approx(0.0, 0.001)
	assert_float(t.relief_at(Vector2(120, 64))).is_less(-2.0)

func test_passes_deepen_a_mud_rut_up_to_what_mud_holds() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var at := Vector2(121, 64)
	var cell := t.cell_of(at)
	var last := 0.0
	for i in 10:
		_pass(t, 64.0, 40.0, 200.0, 1.6)
		var depth := -t.cell_value(TtwTerrain.Layer.DEFORM, cell)
		assert_float(depth).is_greater_equal(last)
		last = depth
	assert_float(last).is_equal_approx(TtwMaterials.MAX_DEPTH[TtwMaterials.MUD], 0.001)

func test_pavement_does_not_sink_and_wears_slowly() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.PAVEMENT)
	var cell := t.cell_of(Vector2(121, 64))
	for i in 10:
		_pass(t, 64.0, 40.0, 200.0, 1.6)
	assert_float(t.cell_value(TtwTerrain.Layer.DEFORM, cell)).is_equal(0.0)
	var wear := t.cell_value(TtwTerrain.Layer.WEAR, cell)
	assert_float(wear).is_equal_approx(10 * 1.6 * TtwMaterials.WEAR_RATE[TtwMaterials.PAVEMENT], 0.0001)
	assert_int(t.effective_material(cell)).is_equal(TtwMaterials.PAVEMENT)

func test_grass_is_torn_into_mud_on_the_pass_that_wears_it_through() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.GRASS)
	var cell := t.cell_of(Vector2(121, 64))
	var per_pass: float = 1.6 * TtwMaterials.WEAR_RATE[TtwMaterials.GRASS]
	var passes := ceili(1.0 / per_pass)
	for i in passes - 1:
		_pass(t, 64.0, 40.0, 200.0, 1.6)
	assert_int(t.effective_material(cell)).is_equal(TtwMaterials.GRASS)
	_pass(t, 64.0, 40.0, 200.0, 1.6)
	assert_int(t.effective_material(cell)).is_equal(TtwMaterials.MUD)
	# Torn up, it gives like mud: the next pass sinks further than grass would.
	var before := t.cell_value(TtwTerrain.Layer.DEFORM, cell)
	_pass(t, 64.0, 40.0, 200.0, 1.6)
	var sunk := before - t.cell_value(TtwTerrain.Layer.DEFORM, cell)
	assert_float(sunk).is_greater(1.6 * TtwMaterials.SOFTNESS[TtwMaterials.GRASS])

func test_a_heavier_or_wetter_pass_sinks_deeper() -> void:
	var light := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var heavy := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var wet := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	wet.wet.fill(1.0)
	_pass(light, 64.0, 40.0, 200.0, 0.7)
	_pass(heavy, 64.0, 40.0, 200.0, 1.6)
	_pass(wet, 64.0, 40.0, 200.0, 0.7)
	var at := Vector2(121, 64)
	assert_float(heavy.relief_at(at)).is_less(light.relief_at(at))
	assert_float(wet.relief_at(at)).is_less(light.relief_at(at))

func test_mud_carried_onto_pavement_thins_out_with_distance() -> void:
	var t := Fixture.flat(Vector2i(32, 8), TtwMaterials.PAVEMENT)
	for y in 8:
		for x in 8:
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
	var carried := _pass(t, 64.0, 8.0, 128.0, 1.6)
	assert_float(carried).is_greater(0.0)
	carried = _pass(t, 64.0, 128.0, 500.0, 1.6, carried)
	var near := 0.0
	var far := 0.0
	for x in range(140, 200, 2):
		near += t.cell_value(TtwTerrain.Layer.LOOSE, t.cell_of(Vector2(x, 64)))
	for x in range(400, 460, 2):
		far += t.cell_value(TtwTerrain.Layer.LOOSE, t.cell_of(Vector2(x, 64)))
	assert_float(near).is_greater(far)
	assert_float(far).is_greater(0.0)

func test_a_crater_throws_out_what_it_digs() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.GRASS)
	TtwStamps.crater(t, Vector2(128, 128), &"vehicle")
	assert_float(_volume(t)).is_equal_approx(0.0, 0.001)
	var center := t.cell_of(Vector2(128, 128))
	assert_float(t.cell_value(TtwTerrain.Layer.DEFORM, center)).is_less(-4.0)
	assert_float(t.cell_value(TtwTerrain.Layer.SCORCH, center)).is_greater(0.5)
	assert_int(t.effective_material(center)).is_equal(TtwMaterials.MUD)

func test_craters_grow_from_shell_to_rocket_to_vehicle_to_building() -> void:
	var dug: Array[float] = []
	for cause in [&"shell", &"rocket", &"vehicle", &"building"]:
		var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.MUD)
		TtwStamps.crater(t, Vector2(128, 128), cause)
		var below := 0.0
		for value in t.deform:
			below += minf(value, 0.0)
		dug.append(-below)
	for i in range(1, dug.size()):
		assert_float(dug[i]).is_greater(dug[i - 1])

func test_a_crater_breaks_pavement() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	TtwStamps.crater(t, Vector2(128, 128), &"shell")
	assert_int(t.effective_material(t.cell_of(Vector2(128, 128)))).is_equal(TtwMaterials.GRAVEL)

func test_a_steep_heap_of_mud_slumps_to_its_repose_and_keeps_its_volume() -> void:
	var t := Fixture.flat(Vector2i(4, 4), TtwMaterials.MUD)
	var top := Vector2i(16, 16)
	t.set_cell(TtwTerrain.Layer.DEFORM, top, 8.0)
	t.queue_settle(t.cell_index(top))
	for sweep in 200:
		for i in t.settling.duplicate():
			if i >= 0:
				TtwSettleSystem.slump(t, i)
	assert_float(t.layer_total(TtwTerrain.Layer.DEFORM)).is_equal_approx(8.0, 0.0001)
	var repose: float = TtwMaterials.REPOSE[TtwMaterials.MUD]
	var steepest := 0.0
	for y in range(8, 24):
		for x in range(8, 24):
			var here := t.cell_value(TtwTerrain.Layer.DEFORM, Vector2i(x, y))
			steepest = maxf(steepest, here - t.cell_value(TtwTerrain.Layer.DEFORM, Vector2i(x + 1, y)))
			steepest = maxf(steepest, here - t.cell_value(TtwTerrain.Layer.DEFORM, Vector2i(x, y + 1)))
	assert_float(steepest).is_less_equal(repose + 0.05)

func test_pavement_does_not_slump() -> void:
	var t := Fixture.flat(Vector2i(4, 4), TtwMaterials.PAVEMENT)
	var at := t.cell_index(Vector2i(16, 16))
	t.set_cell(TtwTerrain.Layer.DEFORM, Vector2i(16, 16), 3.0)
	assert_bool(TtwSettleSystem.slump(t, at)).is_false()
	assert_float(t.cell_value(TtwTerrain.Layer.DEFORM, Vector2i(16, 16))).is_equal(3.0)

## Where a cell centre lies around a patch at `center` along `heading`
## (length `l`, width `w`): &"foot", &"berm", &"bow", &"spray" or &"outside",
## or &"edge" within `margin` px of a boundary (left out of the checks).
func _region(p: Vector2, center: Vector2, heading: float, l: float, w: float, margin: float = 0.2) -> StringName:
	var d := p - center
	var u := d.dot(Vector2.from_angle(heading))
	var v := absf(d.dot(Vector2.from_angle(heading).orthogonal()))
	var hl := l * 0.5
	var hw := w * 0.5
	var across := hw + TtwStamps.BERM_PX
	for edge in [absf(u - hl), absf(u + hl), absf(u - hl - TtwStamps.BOW_PX), absf(u + hl + TtwStamps.SPRAY_PX), absf(v - hw), absf(v - across)]:
		if edge < margin:
			return &"edge"
	if v > across:
		return &"outside"
	if u < -hl:
		return &"spray" if u >= -hl - TtwStamps.SPRAY_PX else &"outside"
	if u <= hl:
		return &"foot" if v <= hw else &"berm"
	if u <= hl + TtwStamps.BOW_PX and v <= hw:
		return &"bow"
	return &"outside"

## Patches at every 15° and at several places within a cell, for the
## checks that every cell a patch reaches gets its share and no other cell
## anything.
func _patches() -> Array:
	var out := []
	for k in 24:
		for offset in [Vector2(0.0, 0.0), Vector2(0.7, 0.3), Vector2(1.3, 1.9), Vector2(0.95, 1.05)]:
			out.append([Vector2(48, 48) + offset, k * PI / 12.0])
	return out

func test_a_press_sinks_its_footprint_and_throws_berms_bow_and_spray_and_touches_nothing_else() -> void:
	var wrong: PackedStringArray = []
	var seen := {}
	for patch in _patches():
		var center: Vector2 = patch[0]
		var heading: float = patch[1]
		var t := Fixture.flat(Vector2i(6, 6), TtwMaterials.MUD)
		var carried := TtwStamps.press(t, center, heading, 6.0, 4.0, 1.2, 0.0, 0.0)
		for y in t.size_cells.y:
			for x in t.size_cells.x:
				var i := y * t.size_cells.x + x
				var region := _region((Vector2(x, y) + Vector2(0.5, 0.5)) * t.cell_size_px, center, heading, 6.0, 4.0)
				seen[region] = seen.get(region, 0) + 1
				var ok := true
				match region:
					&"foot":
						ok = t.deform[i] < 0.0 and t.track[i] == 1.0 and is_equal_approx(t.track_angle[i], heading)
					&"berm":
						ok = t.deform[i] > 0.0 and t.loose[i] == 0.0
					&"bow", &"spray":
						ok = t.loose[i] > 0.0 and t.deform[i] == 0.0
					&"outside":
						ok = t.deform[i] == 0.0 and t.loose[i] == 0.0 and t.wear[i] == 0.0 and t.track[i] == 0.0
				if not ok:
					wrong.append("%s at %s heading %.2f: cell %s" % [region, center, heading, Vector2i(x, y)])
		# What did not go aside stuck to the tyre.
		assert_float(_volume(t) + carried).is_equal_approx(0.0, 0.0001)
	assert_array(Array(wrong)).is_empty()
	for region in [&"foot", &"berm", &"bow", &"spray"]:
		assert_int(seen.get(region, 0)).is_greater(0)

func test_a_press_over_two_materials_gives_each_cell_its_own() -> void:
	# Mud west of x = 128 px, pavement east: a press across the line.
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	for y in 16:
		for x in 8:
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
	var carried := TtwStamps.press(t, Vector2(128, 128), 0.0, 12.0, 4.0, 1.0, 0.0, 0.0)
	var mud := t.cell_index(t.cell_of(Vector2(123, 128)))
	var pavement := t.cell_index(t.cell_of(Vector2(133, 128)))
	assert_float(t.deform[mud]).is_less(0.0)
	assert_float(t.wear[mud]).is_equal_approx(TtwMaterials.WEAR_RATE[TtwMaterials.MUD], 0.0001)
	assert_float(t.deform[pavement]).is_equal(0.0)
	assert_float(t.wear[pavement]).is_equal_approx(TtwMaterials.WEAR_RATE[TtwMaterials.PAVEMENT], 0.0001)
	assert_float(_volume(t) + carried).is_equal_approx(0.0, 0.0001)
