extends GdUnitTestSuite
## What a vehicle's wheels and treads leave as it drives (TtwTrackSystem):
## ruts under each wheel line, packed snow, nothing from a wreck; and what it
## takes from the ground under it (how deep it sits, the water, the grime).

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

## A truck heading east from `start` at full throttle, and its build.
func _truck(start: Vector2) -> Entity:
	var truck := world.spawn(&"truck", start)
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	return truck

## Ticks for a truck to cover `px` at its top speed, the least it can take.
func _ticks_for(truck: Entity, px: float) -> int:
	var d: TtwDrive = truck.get_component(TtwDrive)
	return ceili(px / (d.max_speed_tiles * world.terrain.tile_size_px) * Engine.physics_ticks_per_second)

## Soft going holds a truck to well under its top speed: the checks below
## cover whatever stretch it drove, and need only more than its axles' spread.
const SOFT_GOING_SLOWDOWN := 4.0

## The x of each column of cells both wheel lines have crossed: from the
## frontmost axle's start to the rearmost axle's end, 2 px in from each.
func _crossed(v: TtwVehicle, start: Vector2, end: Vector2) -> Array:
	return range(int(start.x + v.axles_px[0]) + 2, int(end.x + v.axles_px[v.axles_px.size() - 1]) - 2, 2)

func test_a_truck_on_mud_leaves_a_rut_under_each_wheel_line_and_none_between() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(32, 16), TtwMaterials.MUD))
	var t := world.terrain
	var start := Vector2(48, 128)
	var truck := _truck(start)
	var v: TtwVehicle = truck.get_component(TtwVehicle)
	await _ticks(_ticks_for(truck, 64.0 * SOFT_GOING_SLOWDOWN))
	var end := world.session.body_of(truck).position
	var lines := 0
	for x in _crossed(v, start, end):
		for y in [start.y - v.gauge_px * 0.5, start.y + v.gauge_px * 0.5]:
			assert_float(t.relief_at(Vector2(x, y))).is_less(0.0)
			lines += 1
		assert_float(t.relief_at(Vector2(x, start.y))).is_greater_equal(0.0)
	assert_int(lines).is_greater(8)
	assert_float(t.layer_total(TtwTerrain.Layer.DEFORM) + t.layer_total(TtwTerrain.Layer.LOOSE) + v.carried_mud).is_equal_approx(0.0, 0.001)

func test_a_truck_packs_snow_under_its_wheels_and_not_between() -> void:
	var ground := Fixture.flat(Vector2i(32, 16), TtwMaterials.GRASS)
	ground.snow_base.fill(2.0)
	world = Fixture.make(self, ground)
	var t := world.terrain
	var start := Vector2(48, 128)
	var truck := _truck(start)
	var v: TtwVehicle = truck.get_component(TtwVehicle)
	await _ticks(_ticks_for(truck, 64.0 * SOFT_GOING_SLOWDOWN))
	var end := world.session.body_of(truck).position
	var columns := _crossed(v, start, end)
	assert_int(columns.size()).is_greater(4)
	for x in columns:
		for y in [start.y - v.gauge_px * 0.5, start.y + v.gauge_px * 0.5]:
			assert_bool(TtwSnow.is_packed(t, t.cell_index(t.cell_of(Vector2(x, y))))).is_true()
		assert_bool(TtwSnow.is_packed(t, t.cell_index(t.cell_of(Vector2(x, start.y))))).is_false()

func test_a_wreck_dragged_over_mud_presses_nothing() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(16, 16), TtwMaterials.MUD))
	var t := world.terrain
	var wreck := world.spawn(&"truck", Vector2(64, 128))
	wreck.add_component(TtwWrecked.new())
	var body := world.session.body_of(wreck)
	# Dragged a cell a tick, as a tow would, for 32 px.
	var step := t.cell_size_px
	await _ticks(ceili(32.0 / step), func() -> void: body.position.x += step)
	assert_float(body.position.x).is_greater_equal(64.0 + 32.0)
	for i in t.deform.size():
		assert_float(t.deform[i]).is_equal(0.0)
		assert_float(t.track[i]).is_equal(0.0)

func test_a_truck_standing_in_a_flooded_hole_sits_in_it_and_gets_wet() -> void:
	var ground := Fixture.flat(Vector2i(16, 16), TtwMaterials.MUD)
	ground.deform.fill(-2.0)
	ground.water.fill(1.0)
	world = Fixture.make(self, ground)
	var truck := world.spawn(&"truck", Vector2(128, 128))
	var v: TtwVehicle = truck.get_component(TtwVehicle)
	# The first tick lays down where its contacts are; the second reads under them.
	await _ticks(2)
	# 2 px of hole and 3 px of water over its bottom.
	assert_float(v.water_depth).is_equal_approx(3.0, 0.0001)
	assert_float(v.sink).is_equal_approx(5.0, 0.0001)
	assert_float(v.hull_wet).is_equal(1.0)

func test_a_hull_cakes_in_mud_driving_through_it_and_stays_clean_on_pavement() -> void:
	var ground := Fixture.flat(Vector2i(32, 16), TtwMaterials.PAVEMENT)
	for y in range(8, 16):
		for x in 32:
			ground.set_material(Vector2i(x, y), TtwMaterials.MUD)
	world = Fixture.make(self, ground)
	var road := _truck(Vector2(48, 64))
	var mud := _truck(Vector2(48, 192))
	await _ticks(_ticks_for(road, 64.0))
	assert_float((road.get_component(TtwVehicle) as TtwVehicle).grime).is_equal(0.0)
	assert_float((mud.get_component(TtwVehicle) as TtwVehicle).grime).is_greater(0.0)
