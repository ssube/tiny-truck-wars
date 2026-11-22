class_name KitSession extends Node
## Owns the GECS world, entity identity, body binding and the fixed tick.
## A game has one map at a time, and a new
## map (or a load) invalidates the world.
##
## Identity rules:
## - Entities are addressed by alias. Authored map bodies get "map::<node path>".
## - `generation` increments whenever the world is invalidated (new map, load).
##   Requests capture it and are rejected once it moves on.
## - A body maps back to its entity only while the binding is still current.

signal invalidated(generation: int)
signal entity_registered(entity: Entity)
signal entity_removing(entity: Entity)
signal ticked(tick: int)
## Player-facing message (toast). Systems call notify(); the HUD listens.
signal notified(text: String)

## Fixed dispatch order for gameplay groups. "services" runs even while paused.
const GROUPS: Array[String] = ["input", "gameplay", "physics", "presentation"]
const BODY_META := &"kit_entity_id"

var world: World
var simulation: KitSimulationPolicy
var generation: int = 0
var tick: int = 0
var busy: bool = false
var last_error: String = ""
## Installs the systems once the world exists: func(session). Set before the
## session enters the tree; empty means a bare world (unit tests of the core).
var installer: Callable
var _systems: Dictionary = {}
var _views: Dictionary = {}
var _patterns: Dictionary = {}
var _link_views: Dictionary = {}

func _init() -> void:
	name = "Session"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100

func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	var ecs := _ecs()
	if ecs != null:
		ecs.set("world", world)
	simulation = KitSimulationPolicy.new(self)
	var tick_owner := Entity.new()
	tick_owner.alias = "session:simulation"
	tick_owner.add_component(KitSimulationTick.new())
	tick_owner.add_component(KitPersistent.new())
	register(tick_owner)
	if installer.is_valid():
		installer.call(self)

func _exit_tree() -> void:
	if is_instance_valid(world):
		for entity in world.entities.duplicate():
			remove_entity(entity)
		world.purge(false) # Break framework archetype-edge Resource cycles too.
		var ecs := _ecs()
		if ecs != null and ecs.get("world") == world:
			ecs.set("world", null)
	_views.clear()
	_patterns.clear()
	_link_views.clear()
	_systems.clear()

## The GECS autoload, looked up at runtime so tool scripts can compile this class.
func _ecs() -> Node:
	return get_node_or_null("/root/ECS")

## Adds a system under a named service. Systems expose `session` when they need it.
func add_system(key: StringName, system: System, group: String) -> System:
	if "session" in system:
		system.set("session", self)
	system.group = group
	world.add_system(system)
	_systems[key] = system
	return system

func system(key: StringName) -> System:
	return _systems.get(key)

## Every entity with all of `types`. The query is built once and kept (building
## one costs many times what running it does). The array is shared: read it,
## never change it.
func view(types: Array) -> Array:
	var kept: QueryBuilder = _views.get(types)
	if kept == null:
		kept = world.query.with_all(types)
		_views[types] = kept
	return kept.execute()

func _physics_process(delta: float) -> void:
	world.process(delta, "services")
	if not simulation.world_advances():
		return
	tick += 1
	for group in GROUPS:
		world.process(delta, group)
	ticked.emit(tick)

func notify(text: String) -> void:
	if not text.is_empty():
		notified.emit(text)

#region Identity

func register(entity: Entity) -> bool:
	if entity in world.entities:
		return true
	if entity.alias.is_empty():
		entity.alias = GECSIO.uuid()
	if world.has_entity_with_alias(entity.alias):
		last_error = "Entity identity already registered: " + str(entity.alias)
		return false
	world.add_entity(entity)
	entity_registered.emit(entity)
	return true

func resolve(identity: String, expected_generation: int = -1) -> Entity:
	if expected_generation >= 0 and expected_generation != generation:
		return null
	var result := world.get_entity_by_alias(identity)
	if not is_instance_valid(result) or result.is_queued_for_deletion() or result.alias != StringName(identity):
		return null
	return result

func entity_for(body: Node) -> Entity:
	if not is_instance_valid(body):
		return null
	var identity: String = body.get_meta(BODY_META, "")
	var entity := resolve(identity) if not identity.is_empty() else null
	# A late callback from an old node must not resolve a replacement with its ID.
	return entity if entity != null and body_of(entity) == body else null

## Binds a scene node to a new entity. The node provides its authored components
## through `kit_components() -> Array[Component]`, and any further ones in an
## `extra_components` array (copied, so instances never share one).
func bind_body(body: Node2D, identity: String, extra: Array[Component] = []) -> Entity:
	var existing := entity_for(body)
	if existing != null:
		return existing
	if identity.is_empty():
		last_error = "Body identity must not be empty."
		return null
	if world.has_entity_with_alias(identity):
		last_error = "Duplicate identity: " + identity
		return null
	var entity := Entity.new()
	entity.alias = identity
	var binding := KitBody.new()
	binding.node = body
	binding.scene = body.scene_file_path
	entity.add_component(binding)
	if body.has_method("kit_components"):
		for component in body.call("kit_components"):
			entity.add_component(component)
	for component in extra:
		entity.add_component(component)
	var attached: Variant = body.get(&"extra_components")
	if attached is Array:
		for component: Variant in attached:
			if not component is Component:
				last_error = "%s has an empty entry in extra_components." % identity
				entity.free()
				return null
			if entity.has_component(component.get_script()):
				last_error = "%s gives %s twice: in extra_components and as one of its own components." % [identity, component.get_script().get_global_name()]
				entity.free()
				return null
			entity.add_component(KitSlots.copy(component))
	if not register(entity):
		entity.free()
		return null
	body.set_meta(BODY_META, identity)
	if body.has_method("kit_bound"):
		body.call("kit_bound", self, entity)
	return entity

## Gameplay subjects are nodes that declare `kit_components`. Discovery does not
## descend into a subject: its children belong to it.
static func gameplay_bodies(root_node: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child in root_node.get_children():
		if child is Node2D and child.has_method("kit_components"):
			result.append(child)
		else:
			result.append_array(gameplay_bodies(child))
	return result

func body_of(entity: Entity) -> Node2D:
	if not is_instance_valid(entity) or not entity.has_component(KitBody):
		return null
	var binding: KitBody = entity.get_component(KitBody)
	if not is_instance_valid(binding.node) or binding.node.is_queued_for_deletion():
		return null
	return binding.node

func remove_entity(entity: Entity) -> void:
	if not is_instance_valid(entity) or not entity in world.entities:
		return
	if not _link_views.is_empty():
		var id := entity.get_instance_id()
		for key in _link_views.keys():
			if key[1] == id:
				_link_views.erase(key)
	entity_removing.emit(entity)
	var body := body_of(entity)
	if body != null and body.get_meta(BODY_META, "") == str(entity.alias):
		body.remove_meta(BODY_META)
	world.remove_entity(entity)

## Removes an entity and its body for good.
func retire(entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	var body := body_of(entity)
	remove_entity(entity)
	if body != null:
		body.queue_free()

## Retires every outstanding request and UI binding.
func invalidate() -> void:
	generation += 1
	invalidated.emit(generation)

#endregion

#region Links
# Relationships between entities: `relation` is a relation component script.
# GECS drops a link when either end is removed.

## Links `entity` to `target` by `relation`, replacing any link it had of that kind.
func link(entity: Entity, relation: Script, target: Entity) -> void:
	unlink(entity, relation)
	if is_instance_valid(entity) and is_instance_valid(target):
		entity.add_relationship(Relationship.new(relation.new(), target))

func unlink(entity: Entity, relation: Script) -> void:
	if is_instance_valid(entity) and entity.has_relationship(_any(relation)):
		entity.remove_relationship(_any(relation))

func _any(relation: Script) -> Relationship:
	var pattern: Relationship = _patterns.get(relation)
	if pattern == null:
		pattern = Relationship.new(relation.new(), null)
		_patterns[relation] = pattern
	return pattern

## What `entity` is linked to by `relation`, or null.
func linked(entity: Entity, relation: Script) -> Entity:
	if not is_instance_valid(entity):
		return null
	var found := entity.get_relationship(_any(relation))
	var target: Variant = found.target if found != null else null
	return target if target is Entity and is_instance_valid(target) and not target.is_queued_for_deletion() else null

## Every entity linked to `target` by `relation` (a kept query).
func linked_to(target: Entity, relation: Script) -> Array:
	if not is_instance_valid(target):
		return []
	var key := [relation, target.get_instance_id()]
	var kept: QueryBuilder = _link_views.get(key)
	if kept == null:
		kept = world.query.with_relationship([Relationship.new(relation.new(), target)])
		_link_views[key] = kept
	return kept.execute()

#endregion
