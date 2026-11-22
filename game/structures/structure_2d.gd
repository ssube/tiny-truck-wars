class_name TtwStructure2D extends TtwProp2D
## A base structure on the map: garage, fuel depot or helipad. Its origin is
## the middle of its footprint. It is an obstacle with health; hurt, it
## darkens; destroyed, it collapses into a crater and rubble, except a depot,
## which explodes a few ticks later (TtwDepotSystem) and then collapses.
##
## A depot counts the other depots near it with an Area2D: overlaps are
## reported by the physics engine as they begin and end.

signal neighbours_changed(count: int)

const RUBBLE := preload("res://assets/world/rubble.png")
const DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

## assets/structures/<kind>/<facing>.png
@export var kind: StringName = &"depot"
@export var facing: String = "south"
@export var depot: TtwDepot
@export var garage: TtwGarage
@export var helipad: TtwHelipad
@export var build_queue: TtwBuildQueue
## Where the sprite's centre sits from the origin.
@export var sprite_offset: Vector2 = Vector2(0, -6)
## Set before binding (the spawner's side).
var team: int = TtwTeam.NEUTRAL

var sprite: Sprite2D
var _area: Area2D
## Depot areas overlapping this depot's.
var _near: Array[Area2D] = []

func kit_components() -> Array[Component]:
	var mine := super()
	var s := TtwStructure.new()
	s.kind = kind
	mine.append(s)
	var t := TtwTeam.new()
	t.team = team
	mine.append(t)
	if depot != null:
		mine.append(KitSlots.take(depot, TtwDepot))
	if garage != null:
		mine.append(KitSlots.take(garage, TtwGarage))
	if helipad != null:
		mine.append(KitSlots.take(helipad, TtwHelipad))
	if build_queue != null:
		mine.append(KitSlots.take(build_queue, TtwBuildQueue))
	return mine

func kit_bound(bound_session: KitSession, bound: Entity) -> void:
	super(bound_session, bound)
	if bound.has_component(TtwDepot):
		_watch_neighbours(bound.get_component(TtwDepot))

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/structures/%s/%s.png" % [kind, facing])
	sprite.position = sprite_offset
	sprite.show_behind_parent = true
	add_child(sprite)

func _draw() -> void:
	# The side's colour as a ring of paint round the footprint.
	var o: TtwObstacle = obstacle if entity == null else entity.get_component(TtwObstacle)
	var color := TtwTeam.color(TtwTeam.of(entity) if entity != null else team)
	color.a = 0.8
	draw_rect(Rect2(-o.half_extents + o.offset, o.half_extents * 2.0), color, false, 1.0)

#region Depot neighbours

func _watch_neighbours(d: TtwDepot) -> void:
	_area = Area2D.new()
	_area.name = "Cluster"
	_area.collision_layer = Kit2D.LAYER_AREAS
	_area.collision_mask = Kit2D.LAYER_AREAS
	_area.monitorable = true
	_area.set_meta(&"ttw_depot", true)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	# Two circles of half the reach overlap when the depots are within it.
	circle.radius = d.cluster_tiles * TtwTerrain.tile_px() * 0.5
	shape.shape = circle
	_area.add_child(shape)
	add_child(_area)
	_area.area_entered.connect(func(other: Area2D):
		if other.has_meta(&"ttw_depot") and not _near.has(other):
			_near.append(other)
			_announce.call_deferred())
	_area.area_exited.connect(func(other: Area2D):
		if _near.has(other):
			_near.erase(other)
			_announce.call_deferred())

## Told after the physics step, not inside it (listeners may add bodies).
func _announce() -> void:
	neighbours_changed.emit(neighbours())

## Depots of the same side within this depot's cluster reach.
func neighbours() -> int:
	if not is_instance_valid(entity):
		return 0
	var mine := TtwTeam.of(entity)
	var count := 0
	for other in _near:
		if not is_instance_valid(other):
			continue
		var owner := other.get_parent() as TtwStructure2D
		if owner != null and owner.entity != null and is_instance_valid(owner.entity) and TtwTeam.of(owner.entity) == mine and not owner.entity.has_component(TtwDetonating):
			count += 1
	return count

#endregion

func hurt(share: float) -> void:
	if sprite != null:
		sprite.modulate = Color(1, 1, 1).lerp(Color(0.55, 0.5, 0.46), 1.0 - share)

## Destroyed: a depot goes up a few ticks later; anything else collapses.
func destroyed(_from: Vector2) -> void:
	if entity != null and entity.has_component(TtwDepot):
		if not entity.has_component(TtwDetonating):
			var fuse := TtwDetonating.new()
			fuse.at_tick = session.tick + TtwDepotSystem.CHAIN_TICKS
			entity.add_component(fuse)
			if sprite != null:
				sprite.modulate = Color(1.0, 0.6, 0.4)
		return
	collapse(&"building")

## Falls in: a crater of `cause`, the footprint broken into rubble, dust and
## debris; then the entity is gone.
func collapse(cause: StringName) -> void:
	var t := TtwGround.of(session) if session != null else null
	var o: TtwObstacle = entity.get_component(TtwObstacle) if entity != null else obstacle
	var center := position + o.offset
	if t != null:
		TtwStamps.crater(t, center, cause)
		var lo := t.tile_of(center - o.half_extents)
		var hi := t.tile_of(center + o.half_extents)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				t.set_material(Vector2i(x, y), TtwMaterials.GRAVEL)
	var g := game()
	if g != null:
		var heap := Sprite2D.new()
		heap.texture = RUBBLE
		heap.add_to_group(TtwSave.RUBBLE_GROUP)
		heap.position = center
		heap.scale = Vector2(o.half_extents.x * 2.0 / RUBBLE.get_width(), o.half_extents.y * 2.0 / RUBBLE.get_height())
		get_parent().add_child(heap)
		g.fx.explode(center, cause)
	fuel = 0.0
	retire()
