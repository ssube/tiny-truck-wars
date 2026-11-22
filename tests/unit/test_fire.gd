extends GdUnitTestSuite
## Fire on the map: it spreads along fuel and nowhere else, faster downwind,
## burns its fuel away, and water and rain put it out.

const Fixture := preload("res://tests/support/world.gd")

## A row of fuelled tiles along y = 2.
func _row(length: int, amount: float = 5.0) -> TtwFireField:
	var f := TtwFireField.new(Vector2i(16, 6))
	for x in length:
		f.add_fuel(Vector2i(x, 2), amount)
	return f

func _weather(wind: Vector2, rain: float = 0.0) -> TtwWeather:
	var w := TtwWeather.new()
	w.wind_now = wind
	w.rain = rain
	return w

## Seconds (in steps of 0.1) until `tile` catches, or -1.
func _time_to(f: TtwFireField, tile: Vector2i, weather: TtwWeather, limit: float = 60.0) -> float:
	var t := 0.0
	while t < limit:
		f.step(0.1, null, weather)
		t += 0.1
		if f.is_burning(tile):
			return t
	return -1.0

func test_fire_runs_along_fuel_and_not_onto_bare_ground() -> void:
	var f := _row(8)
	assert_bool(f.ignite(Vector2i(0, 2))).is_true()
	assert_float(_time_to(f, Vector2i(5, 2), _weather(Vector2.ZERO))).is_greater(0.0)
	for k in 200:
		f.step(0.1, null, _weather(Vector2.ZERO))
		assert_bool(f.is_burning(Vector2i(2, 3))).is_false()
		assert_bool(f.is_burning(Vector2i(9, 2))).is_false()

func test_nothing_to_burn_does_not_light() -> void:
	var f := TtwFireField.new(Vector2i(4, 4))
	assert_bool(f.ignite(Vector2i(1, 1))).is_false()
	assert_int(f.burning.size()).is_equal(0)

func test_a_fire_burns_its_fuel_away_and_goes_out() -> void:
	var f := _row(1, 2.0)
	f.ignite(Vector2i(0, 2))
	for k in 200:
		f.step(0.1, null, _weather(Vector2.ZERO))
	assert_int(f.burning.size()).is_equal(0)
	assert_float(f.fuel[f.index(Vector2i(0, 2))]).is_less_equal(TtwFireField.SPENT)

func test_a_following_wind_spreads_it_faster_than_a_head_wind() -> void:
	var with_wind := _row(8)
	var against := _row(8)
	with_wind.ignite(Vector2i(0, 2))
	against.ignite(Vector2i(0, 2))
	var fast := _time_to(with_wind, Vector2i(4, 2), _weather(Vector2(30, 0)))
	var slow := _time_to(against, Vector2i(4, 2), _weather(Vector2(-30, 0)))
	assert_float(fast).is_greater(0.0)
	assert_bool(slow < 0.0 or slow > fast).is_true()

func test_water_puts_a_tile_out_at_once() -> void:
	var t := Fixture.flat(Vector2i(16, 6), TtwMaterials.MUD)
	var f := _row(4)
	f.ignite(Vector2i(1, 2))
	t.water[t.tile_index(Vector2i(1, 2))] = 2.0
	f.step(0.1, t, _weather(Vector2.ZERO))
	assert_bool(f.is_burning(Vector2i(1, 2))).is_false()

func test_rain_puts_it_out() -> void:
	var f := _row(8, 50.0)
	f.ignite(Vector2i(3, 2))
	for k in 100:
		f.step(0.1, null, _weather(Vector2.ZERO, 1.0))
	assert_int(f.burning.size()).is_equal(0)
