extends GdUnitTestSuite
## Routes for ground vehicles: weights from the ground's layers, walls where
## water floods an engine or an obstacle stands, weights that follow the ground
## as it changes, and a pilot that drives a route to its end.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int, on_tick: Callable = Callable()) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0, on_tick)
	assert_bool(result.success).is_true()

func _tiles(points: PackedVector2Array, from: Vector2, t: TtwTerrain) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := from
	for p in points:
		var steps := ceili(at.distance_to(p) / 2.0) + 1
		for k in steps + 1:
			out.append(t.tile_of(at.lerp(p, float(k) / steps)))
		at = p
	return out

## Pavement, 20×12, with deep water over tiles x 8..11, y 0..9.
func _pond() -> TtwTerrain:
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.PAVEMENT)
	for y in 10:
		for x in range(8, 12):
			t.water[t.tile_index(Vector2i(x, y))] = TtwPathGrid.FLOOD_PX + 1.0
	return t

func test_mud_weighs_more_than_pavement_and_water_at_the_intake_is_a_wall() -> void:
	var t := _pond()
	t.set_material(Vector2i(2, 2), TtwMaterials.MUD)
	var grid := TtwPathGrid.new(t)
	assert_float(grid.tile_cost(Vector2i(2, 2))).is_greater(grid.tile_cost(Vector2i(3, 2)))
	assert_float(grid.tile_cost(Vector2i(3, 2))).is_equal_approx(1.0, 0.001)
	assert_bool(is_inf(grid.tile_cost(Vector2i(9, 4)))).is_true()
	# Just under the intake it is passable, at a price.
	t.water[t.tile_index(Vector2i(9, 4))] = TtwPathGrid.FLOOD_PX - 0.1
	assert_bool(is_inf(grid.tile_cost(Vector2i(9, 4)))).is_false()
	assert_float(grid.tile_cost(Vector2i(9, 4))).is_greater(grid.tile_cost(Vector2i(3, 4)) * 2.0)

func test_a_route_goes_around_deep_water() -> void:
	var t := _pond()
	var grid := TtwPathGrid.new(t)
	var from := Vector2(2.5, 5.5) * 16.0
	var to := Vector2(17.5, 5.5) * 16.0
	var route := grid.find(from, to)
	assert_bool(route.is_empty()).is_false()
	assert_vector(route[route.size() - 1]).is_equal(to)
	for tile in _tiles(route, from, t):
		assert_bool(tile.x >= 8 and tile.x <= 11 and tile.y <= 9).override_failure_message("through the pond at %s" % tile).is_false()

func test_a_route_takes_a_firm_detour_round_a_bog() -> void:
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.PAVEMENT)
	for y in range(0, 9):
		for x in range(8, 12):
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
			for c in TtwTerrain.CELLS_PER_TILE * TtwTerrain.CELLS_PER_TILE:
				t.wet[t.cell_index(Vector2i(x, y) * 8 + Vector2i(c % 8, c / 8))] = 1.0
	var grid := TtwPathGrid.new(t)
	var from := Vector2(2.5, 3.5) * 16.0
	var route := grid.find(from, Vector2(17.5, 3.5) * 16.0)
	var crossed := _tiles(route, from, t).filter(func(tile: Vector2i): return t.surface[t.tile_index(tile)] == TtwMaterials.MUD)
	assert_array(crossed).is_empty()

func test_a_route_keeps_to_the_road_round_a_field() -> void:
	# A grass field with mud in it; a road round it, up and back down.
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.GRASS)
	for y in range(3, 9):
		for x in range(6, 14):
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
	var road: Array[Vector2i] = []
	for x in range(2, 18):
		road.append(Vector2i(x, 1))
	for y in range(1, 6):
		road.append(Vector2i(2, y))
		road.append(Vector2i(17, y))
	for tile in road:
		t.set_material(tile, TtwMaterials.PAVEMENT)
	var grid := TtwPathGrid.new(t)
	var from := Vector2(2.5, 5.5) * 16.0
	var to := Vector2(17.5, 5.5) * 16.0
	var off := _tiles(grid.find(from, to), from, t).filter(func(tile: Vector2i): return t.surface[t.tile_index(tile)] != TtwMaterials.PAVEMENT)
	assert_array(off).is_empty()

func test_a_route_keeps_out_of_shallow_water_when_there_is_a_dry_way() -> void:
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.PAVEMENT)
	for y in 10:
		for x in range(8, 12):
			t.water[t.tile_index(Vector2i(x, y))] = 1.0
	var grid := TtwPathGrid.new(t)
	assert_bool(is_inf(grid.tile_cost(Vector2i(9, 4)))).is_false()
	var from := Vector2(2.5, 5.5) * 16.0
	var to := Vector2(17.5, 5.5) * 16.0
	for tile in _tiles(grid.find(from, to), from, t):
		assert_bool(tile.x >= 8 and tile.x <= 11 and tile.y <= 9).override_failure_message("through the water at %s" % tile).is_false()

func test_a_route_leaves_the_road_round_a_wreck_standing_on_it() -> void:
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.GRASS)
	for x in 20:
		t.set_material(Vector2i(x, 5), TtwMaterials.PAVEMENT)
		t.set_material(Vector2i(x, 6), TtwMaterials.PAVEMENT)
	world = Fixture.make(self, t)
	var wreck := world.spawn(&"truck", Vector2(10, 6) * 16.0)
	wreck.add_component(TtwWrecked.new())
	var from := Vector2(2, 6) * 16.0
	var to := Vector2(18, 6) * 16.0
	await _ticks(1) # the grid
	var grid := TtwGround.paths_of(world.session)
	# Before the grid hears of it, the road goes straight through.
	assert_bool(_tiles(grid.find(from, to), from, t).has(Vector2i(10, 6))).is_true()
	await _ticks(TtwCrowdSystem.EVERY_TICKS)
	var clear := TtwSeparationSystem.radius_of(wreck.get_component(TtwVehicle)) + TtwSeparationSystem.radius_of(wreck.get_component(TtwVehicle))
	var at := world.session.body_of(wreck).position
	var route := grid.find(from, to)
	assert_vector(route[route.size() - 1]).is_equal(to)
	var p := from
	for q in route:
		for k in 33:
			assert_float(p.lerp(q, k / 32.0).distance_to(at)).override_failure_message("passes the wreck at %s" % p.lerp(q, k / 32.0)).is_greater(clear)
		p = q

func test_an_obstacle_walls_its_tiles_until_it_is_gone() -> void:
	var t := Fixture.flat(Vector2i(20, 12), TtwMaterials.PAVEMENT)
	var grid := TtwPathGrid.new(t)
	var wall := TtwObstacle.new()
	wall.shape = TtwObstacle.Shape.BOX
	wall.half_extents = Vector2(8, 80)
	var at := Vector2(160, 80) # covers tiles x 9..10 (centres 152, 168), y 0..9
	var tiles: Array[Vector2i] = []
	for y in 12:
		for x in range(8, 12):
			tiles.append(Vector2i(x, y))
	grid.place(1, wall, at, tiles)
	assert_bool(grid.is_open(Vector2(152, 40))).is_false()
	assert_bool(grid.is_open(Vector2(136, 40))).is_true()
	var from := Vector2(40, 40)
	var route := grid.find(from, Vector2(280, 40))
	for tile in _tiles(route, from, t):
		assert_bool(tile.x >= 9 and tile.x <= 10 and tile.y <= 9).override_failure_message("through the wall at %s" % tile).is_false()
	grid.place(1, null, at, [])
	assert_bool(grid.is_open(Vector2(152, 40))).is_true()
	assert_int(grid.find(from, Vector2(280, 40)).size()).is_equal(1)

func test_a_crater_is_weighed_again_on_the_next_tick() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.GRASS)
	world = Fixture.make(self, t)
	await _ticks(1)
	var grid := TtwGround.paths_of(world.session)
	assert_object(grid).is_not_null()
	var tile := Vector2i(8, 8)
	var before := grid.cost[t.tile_index(tile)]
	TtwStamps.crater(t, Vector2(tile) * 16.0 + Vector2(8, 8), &"building")
	await _ticks(1)
	assert_float(grid.cost[t.tile_index(tile)]).is_greater(before)

func test_the_pilot_drives_a_straight_route_and_stops_at_its_end() -> void:
	var t := Fixture.flat(Vector2i(20, 6), TtwMaterials.PAVEMENT)
	world = Fixture.make(self, t)
	var truck := world.spawn(&"truck", Vector2(24, 40))
	var to := Vector2(264, 40)
	TtwPilotSystem.order(truck, to)
	var arrived := []
	(world.session.system(&"pilot") as TtwPilotSystem).arrived.connect(func(e): arrived.append(e))
	# Upper bound: speeding up, the run at top speed, and the last two tiles at
	# the slowest ease-in throttle.
	var d: TtwDrive = truck.get_component(TtwDrive)
	var top := d.max_speed_tiles * 16.0
	var seconds := top / (d.accel_tiles * 16.0) + to.distance_to(Vector2(24, 40)) / top + 32.0 / (top * 0.3)
	await _ticks(ceili(seconds * 60.0) + 1)
	assert_array(arrived).is_equal([truck])
	assert_bool(truck.has_component(TtwMoveOrder)).is_false()
	assert_float(world.session.body_of(truck).position.distance_to(to)).is_less(TtwPilotSystem.ARRIVE_PX + 2.0)

func test_the_pilot_drives_round_the_pond_without_wading_in() -> void:
	var t := _pond()
	world = Fixture.make(self, t)
	var tank := world.spawn(&"tank", Vector2(2.5, 5.5) * 16.0)
	var to := Vector2(17.5, 5.5) * 16.0
	await _ticks(1)
	TtwPilotSystem.order(tank, to)
	var deepest := [0.0]
	var arrived := []
	(world.session.system(&"pilot") as TtwPilotSystem).arrived.connect(func(e): arrived.append(e))
	var grid := TtwGround.paths_of(world.session)
	var route := grid.find(Vector2(2.5, 5.5) * 16.0, to)
	var length := 0.0
	var at := Vector2(2.5, 5.5) * 16.0
	for p in route:
		length += at.distance_to(p)
		at = p
	# Tracks pivot at each turn (at most a half turn each) and drive the rest.
	var d: TtwDrive = tank.get_component(TtwDrive)
	var top := d.max_speed_tiles * 16.0
	var seconds := route.size() * (PI / d.turn_rate + top / (d.accel_tiles * 16.0)) + length / top + 32.0 / (top * 0.3)
	await _ticks(ceili(seconds * 60.0), func(): deepest[0] = maxf(deepest[0], t.water_depth_at(world.session.body_of(tank).position)))
	assert_array(arrived).is_equal([tank])
	assert_float(deepest[0]).is_less(TtwPathGrid.FLOOD_PX)
