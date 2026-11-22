extends GdUnitTestSuite
## The weather: the wind is a function of the tick (the same tick, the same
## gust, on any machine), and the soil wets in rain and dries in sun.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")

func test_the_wind_at_a_tick_is_always_the_same_and_gusts_within_bounds() -> void:
	var w := TtwWeather.new()
	w.wind = Vector2(20, 0)
	for tick in [0, 17, 600, 123456]:
		var a := TtwWeatherSystem.wind_at(w, tick, 0.4)
		var b := TtwWeatherSystem.wind_at(w, tick, 0.4)
		assert_vector(a).is_equal(b)
		assert_float(a.x).is_between(20.0 * 0.15, 20.0 * 1.2)
	# It does change over time.
	assert_float(TtwWeatherSystem.wind_at(w, 0, 0.0).x).is_not_equal(TtwWeatherSystem.wind_at(w, 900, 0.0).x)

func test_rain_wets_the_soil_and_sun_dries_it() -> void:
	var w := TtwWeather.new()
	w.rain = 1.0
	var wet := TtwWeatherSystem.moisture_after(w, 0.0, 10.0)
	assert_float(wet).is_equal_approx(10.0 * TtwWeatherSystem.WETTING, 0.0001)
	w.rain = 0.0
	w.sun = 1.0
	w.temperature = 20.0
	var sunny := TtwWeatherSystem.moisture_after(w, 0.5, 60.0)
	w.sun = 0.0
	w.temperature = 0.0
	var dull := TtwWeatherSystem.moisture_after(w, 0.5, 60.0)
	assert_float(sunny).is_less(dull)
	assert_float(dull).is_less(0.5)

func test_the_system_keeps_the_maps_wind_and_moisture() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.GRASS)
	var world := Fixture.make(self, t)
	var w := TtwWeather.new()
	w.rain = 1.0
	w.wind = Vector2(10, 0)
	world.session.resolve("map").add_component(w)
	var ticks := 60
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), ticks, 3.0)
	assert_bool(result.success).is_true()
	assert_vector(w.wind_now).is_equal(TtwWeatherSystem.wind_at(w, world.session.tick, 0.0))
	assert_float(w.soil_moisture).is_equal_approx(ticks / 60.0 * TtwWeatherSystem.WETTING, 0.001)
	world.queue_free()
