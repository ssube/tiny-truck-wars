class_name TtwProp2D extends Node2D
## Shared by trees, logs and buildings: a static collision shape on the
## structures layer matching its TtwObstacle, health, and the way back to the
## game (spawning what it leaves behind, the effects).

@export var health: TtwHealth
@export var obstacle: TtwObstacle
@export var extra_components: Array[Component] = []
## Fuel this object gives each tile it stands on (TtwFireField).
@export var fuel: float = 0.0

var entity: Entity
var session: KitSession
var static_body: StaticBody2D

func kit_components() -> Array[Component]:
	return [KitSlots.take(health, TtwHealth), KitSlots.take(obstacle, TtwObstacle)]

func kit_bound(bound_session: KitSession, bound: Entity) -> void:
	session = bound_session
	entity = bound
	var o: TtwObstacle = entity.get_component(TtwObstacle)
	o.angle = rotation
	static_body = StaticBody2D.new()
	static_body.collision_layer = Kit2D.LAYER_STRUCTURES
	static_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	if o.shape == TtwObstacle.Shape.CIRCLE:
		var c := CircleShape2D.new()
		c.radius = o.radius
		shape.shape = c
	else:
		var r := RectangleShape2D.new()
		r.size = o.half_extents * 2.0
		shape.shape = r
	shape.position = o.offset
	static_body.add_child(shape)
	add_child(static_body)
	_fuel(1.0)
	block_paths()

## Tells the path grid which tiles this object blocks (again, once it moved).
func block_paths() -> void:
	var paths := TtwGround.paths_of(session) if session != null else null
	if paths != null and entity != null:
		paths.place(get_instance_id(), entity.get_component(TtwObstacle), position, footprint(TtwPathGrid.OBSTACLE_GROW))

## Tiles this object stands on, or comes within `grow` px of.
func footprint(grow: float = 0.0) -> Array[Vector2i]:
	var o: TtwObstacle = entity.get_component(TtwObstacle) if entity != null else obstacle
	var center := position + o.offset.rotated(rotation)
	var reach := Vector2(o.radius, o.radius)
	if o.shape == TtwObstacle.Shape.BOX:
		# The turned box's bounds.
		var c := absf(cos(rotation))
		var s := absf(sin(rotation))
		reach = Vector2(o.half_extents.x * c + o.half_extents.y * s, o.half_extents.x * s + o.half_extents.y * c)
	reach += Vector2(grow, grow)
	var tile := TtwTerrain.tile_px()
	var lo := Vector2i(((center - reach) / tile).floor())
	var hi := Vector2i(((center + reach) / tile).floor())
	var out: Array[Vector2i] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out

func _fuel(sign: float) -> void:
	if fuel <= 0.0 or session == null:
		return
	var field := TtwGround.fire_of(session)
	if field != null:
		for tile in footprint():
			field.add_fuel(tile, fuel * sign)

func game() -> TtwGame:
	return get_tree().get_first_node_in_group(&"ttw_game") as TtwGame if is_inside_tree() else null

## Removes the entity and this body for good (and what it gave the fire).
func retire() -> void:
	_fuel(-1.0)
	var paths := TtwGround.paths_of(session) if session != null else null
	if paths != null:
		paths.place(get_instance_id(), null, position, [])
	if session != null and entity != null:
		session.retire(entity)
	else:
		queue_free()
