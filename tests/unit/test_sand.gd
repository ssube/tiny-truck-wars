extends GdUnitTestSuite
## Sand: damp sand packs firm (the opposite of mud), and a strong wind drifts
## it into ruts without making or losing any.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

func test_damp_sand_sinks_less_than_dry_sand() -> void:
	var dry := Fixture.flat(Vector2i(8, 8), TtwMaterials.SAND)
	var damp := Fixture.flat(Vector2i(8, 8), TtwMaterials.SAND)
	damp.wet.fill(1.0)
	var at := Vector2(64, 64)
	TtwStamps.press(dry, at, 0.0, 2.0, 6.0, 1.6, 0.0, 0.0)
	TtwStamps.press(damp, at, 0.0, 2.0, 6.0, 1.6, 0.0, 0.0)
	assert_float(damp.relief_at(at)).is_greater(dry.relief_at(at))

## A rut across the wind, on sand, in a world with weather.
func _sand_rut(wind: Vector2) -> TtwTerrain:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.SAND)
	for y in t.size_cells.y:
		for x in range(30, 34):
			var i := y * t.size_cells.x + x
			t.deform[i] = -3.0
			t.queue_settle(i)
		for x in range(26, 30):
			var i := y * t.size_cells.x + x
			t.deform[i] = 1.5
			t.queue_settle(i)
	t.mark_cells(Rect2i(Vector2i.ZERO, t.size_cells))
	world = Fixture.make(self, t)
	var w := TtwWeather.new()
	w.wind = wind
	world.session.resolve("map").add_component(w)
	return t

func test_a_strong_wind_drifts_sand_into_a_rut_and_keeps_the_volume() -> void:
	var t := _sand_rut(Vector2(60, 0))
	var before := t.layer_total(TtwTerrain.Layer.DEFORM)
	var rut := Vector2i(31, 20)
	var depth := t.cell_value(TtwTerrain.Layer.DEFORM, rut)
	await _ticks(TtwSettleSystem.PERIOD_TICKS * 10)
	assert_float(t.cell_value(TtwTerrain.Layer.DEFORM, rut)).is_greater(depth + 0.2)
	assert_float(t.layer_total(TtwTerrain.Layer.DEFORM)).is_equal_approx(before, 0.01)

func test_wind_fills_a_rut_faster_than_slumping_alone() -> void:
	var rut := Vector2i(31, 20)
	var still := _sand_rut(Vector2.ZERO)
	await _ticks(TtwSettleSystem.PERIOD_TICKS * 10)
	var slumped := still.cell_value(TtwTerrain.Layer.DEFORM, rut)
	world.queue_free()
	world = null
	var windy := _sand_rut(Vector2(60, 0))
	await _ticks(TtwSettleSystem.PERIOD_TICKS * 10)
	assert_float(windy.cell_value(TtwTerrain.Layer.DEFORM, rut)).is_greater(slumped + 0.1)
