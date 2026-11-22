class_name KitSlots extends RefCounted
## Component slots on bodies. A body exports one resource per component it
## needs (`vehicle`, `drive`, `fuel`...): the defaults are authored in the
## body's scene under prefabs/, and a map that wants something different
## gives that slot its own resource. Anything a kind does not need by default
## goes in the body's `extra_components` array (read by KitSession.bind_body).
##
## The authored resources are shared by every instance of a scene, so nothing
## may change them in place: binding copies each one (take), and code that
## overrides a slot on one instance first makes it that instance's own (own).

## A copy of a component that shares nothing changeable with the original.
## Resource.duplicate() alone leaves arrays and dictionaries (a loot table,
## a shop's stock) shared between the copies; this copies those too. Resources
## they refer to (an attack, a portrait) stay shared: those are definitions.
static func copy(component: Component) -> Component:
	var made: Component = component.duplicate()
	for field in _containers(component.get_script()):
		made.set(field, made.get(field).duplicate(true))
	return made

## The array and dictionary fields of each component type, by script path,
## worked out once (listing a component's properties costs more than the copy).
static var _container_fields: Dictionary = {}

static func _containers(script: Script) -> PackedStringArray:
	var key := script.resource_path
	if not _container_fields.has(key):
		var names: PackedStringArray = []
		for property in script.get_script_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and (property.type == TYPE_ARRAY or property.type == TYPE_DICTIONARY):
				names.append(property.name)
		_container_fields[key] = names
	return _container_fields[key]

## A private copy of an authored component for a new entity, or a fresh
## default of `kind` when the slot was left empty.
static func take(authored: Component, kind: Script) -> Component:
	return copy(authored) if authored != null else kind.new()

## Makes `slot` on `body` its own copy (so changing it leaves the scene it
## came from alone) and returns that copy. An empty slot gets a fresh
## component of the slot's declared kind. Later calls return the same copy.
static func own(body: Node, slot: StringName) -> Component:
	var current: Component = body.get(slot)
	if current != null and _owned.get(current.get_instance_id(), 0) == body.get_instance_id():
		return current
	var mine: Component = copy(current) if current != null else _fresh(body, slot)
	body.set(slot, mine)
	if mine != null:
		_owned[mine.get_instance_id()] = body.get_instance_id()
	return mine

## Which body each owned copy was made for (instance ids only: nothing is
## kept alive, and nothing is written into a scene).
static var _owned: Dictionary = {}

## Sets one authored value on a body: `path` is a property ("display_name")
## or a slot and one of its fields ("brain:aggro_tiles"), in which case the
## slot becomes the body's own first.
static func assign(body: Node, path: String, value: Variant) -> void:
	if not ":" in path:
		body.set(path, value)
		return
	var slot := path.get_slice(":", 0)
	var component := own(body, StringName(slot))
	assert(component != null, "%s has no component slot '%s'." % [body.name, slot])
	component.set(path.get_slice(":", 1), value)

static func _fresh(body: Node, slot: StringName) -> Component:
	for property in body.get_property_list():
		if property.name == slot and not str(property.class_name).is_empty():
			for entry in ProjectSettings.get_global_class_list():
				if entry.class == property.class_name:
					return (load(entry.path) as Script).new() as Component
	return null
