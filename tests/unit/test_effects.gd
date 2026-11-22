extends GdUnitTestSuite
## Which effects a vehicle makes, and the puff pools' limits.

func _vehicle(water: float = 0.0) -> TtwVehicle:
	var v := TtwVehicle.new()
	v.water_depth = water
	return v

func _drive(speed: float, throttle: float, resistance: float = 1.0, traction: float = 6.0) -> TtwDrive:
	var d := TtwDrive.new()
	d.speed = speed
	d.throttle = throttle
	d.resistance = resistance
	d.traction = traction
	return d

func test_slipping_in_mud_throws_clods_and_rolling_on_pavement_does_not() -> void:
	var slipping := _drive(5.0, 1.0, 5.0, 6.0)
	assert_array(TtwEffectsSystem.effects_for(_vehicle(), slipping, TtwMaterials.MUD, 0.0)).contains([&"clods"])
	assert_array(TtwEffectsSystem.effects_for(_vehicle(), slipping, TtwMaterials.PAVEMENT, 0.0)).not_contains([&"clods"])

func test_dust_rises_from_dry_fast_going_and_not_from_wet() -> void:
	var fast := _drive(Kit2D.tiles(3.0), 1.0)
	assert_array(TtwEffectsSystem.effects_for(_vehicle(), fast, TtwMaterials.SAND, 0.0)).contains([&"dust"])
	assert_array(TtwEffectsSystem.effects_for(_vehicle(), fast, TtwMaterials.SAND, 0.8)).not_contains([&"dust"])
	assert_array(TtwEffectsSystem.effects_for(_vehicle(), _drive(Kit2D.tiles(1.0), 1.0), TtwMaterials.SAND, 0.0)).not_contains([&"dust"])

func test_in_water_a_moving_vehicle_throws_droplets_not_dust_or_clods() -> void:
	var effects := TtwEffectsSystem.effects_for(_vehicle(2.0), _drive(Kit2D.tiles(3.0), 1.0, 5.0), TtwMaterials.MUD, 1.0)
	assert_array(effects).contains([&"droplets"])
	assert_array(effects).not_contains([&"dust", &"clods"])

func test_a_puff_pool_never_grows_and_respects_its_budget() -> void:
	var puffs := TtwPuffs.new()
	add_child(puffs)
	var before := puffs.emitters()
	for i in 200:
		puffs.puff(TtwPuffs.Kind.PLUME, Vector2(i, 0), Vector2.UP, 40)
	assert_int(puffs.emitters()).is_equal(before)
	assert_int(puffs.live()).is_less_equal(TtwPuffs.BUDGET)
	puffs.queue_free()

func test_a_smoke_screen_that_blew_away_is_dropped_without_errors() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var fx := TtwFx.new()
	add_child(fx)
	fx.bind(holder, holder, null)
	fx.weather = TtwWeather.new()
	var screen := fx.smoke_screen(Vector2.ZERO, 20.0, 0.0)
	screen.free()
	# Passing the wind on must skip (and drop) the freed screen.
	fx._process(0.016)
	assert_int(fx._screens.size()).is_equal(0)
	fx.queue_free()
	holder.queue_free()
