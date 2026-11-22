extends GdUnitTestSuite
## The trimmed session keeps the kit's identity, binding and link rules.

class Marker extends Component:
	pass

class LinkedTo extends Component:
	pass

class Subject extends Node2D:
	func kit_components() -> Array[Component]:
		return [Marker.new()]

var session: KitSession

func before_test() -> void:
	session = KitSession.new()
	add_child(session)

func after_test() -> void:
	session.queue_free()

func test_bound_body_resolves_to_its_entity_and_back() -> void:
	var body := Subject.new()
	add_child(body)
	var entity := session.bind_body(body, "map::Subject")
	assert_object(entity).is_not_null()
	assert_bool(entity.has_component(Marker)).is_true()
	assert_object(session.entity_for(body)).is_same(entity)
	assert_object(session.body_of(entity)).is_same(body)
	body.queue_free()

func test_duplicate_identity_is_refused_with_a_reason() -> void:
	var first := Subject.new()
	var second := Subject.new()
	add_child(first)
	add_child(second)
	assert_object(session.bind_body(first, "map::Twin")).is_not_null()
	assert_object(session.bind_body(second, "map::Twin")).is_null()
	assert_str(session.last_error).contains("Duplicate identity")
	first.queue_free()
	second.queue_free()

func test_requests_from_an_old_generation_do_not_resolve() -> void:
	var entity := Entity.new()
	entity.alias = "thing"
	session.register(entity)
	var captured := session.generation
	assert_object(session.resolve("thing", captured)).is_same(entity)
	session.invalidate()
	assert_object(session.resolve("thing", captured)).is_null()

func test_link_replaces_the_previous_target_and_goes_with_the_target() -> void:
	var pad := Entity.new()
	var depot_a := Entity.new()
	var depot_b := Entity.new()
	for entity in [pad, depot_a, depot_b]:
		session.register(entity)
	session.link(pad, LinkedTo, depot_a)
	session.link(pad, LinkedTo, depot_b)
	assert_object(session.linked(pad, LinkedTo)).is_same(depot_b)
	assert_array(session.linked_to(depot_a, LinkedTo)).is_empty()
	session.remove_entity(depot_b)
	assert_object(session.linked(pad, LinkedTo)).is_null()

func test_the_session_ticks_once_per_physics_frame() -> void:
	var start := session.tick
	var result: Dictionary = await preload("res://tests/support/simulation.gd").physics_ticks(get_tree(), 3, 1.0)
	assert_bool(result.success).is_true()
	assert_int(session.tick - start).is_equal(3)

func test_a_view_sees_an_entity_added_to_an_archetype_it_already_holds() -> void:
	# Two archetypes match; the third entity joins the first one.
	for parts in [[Marker.new()], [Marker.new(), LinkedTo.new()]]:
		var e := Entity.new()
		for part in parts:
			e.add_component(part)
		session.register(e)
	assert_int(session.view([Marker]).size()).is_equal(2)
	var late := Entity.new()
	late.add_component(Marker.new())
	session.register(late)
	assert_int(session.view([Marker]).size()).is_equal(3)
