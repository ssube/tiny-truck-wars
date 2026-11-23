class_name TtwBuilding2D extends TtwProp2D
## A building, its origin at the middle of its front wall's foot. Hurt, it
## cracks, then its roof breaks; destroyed, it collapses: a crater, rubble
## (broken ground: gravel, heaped up), dust, debris and fire.


@export var art: Texture2D = preload("res://assets/world/house.png")
## Pictures to choose from instead of `art`, by where it stands (the same
## spot, the same building, in a loaded save too).
@export var variants: Array[Texture2D] = []

var _sprite: Sprite2D
var _damage: float = 0.0

func kit_components() -> Array[Component]:
	var mine := super()
	mine.append(TtwBuilding.new())
	return mine

func _ready() -> void:
	if not variants.is_empty():
		art = variants[posmod(hash(Vector2i(position.round())), variants.size())]
	_sprite = Sprite2D.new()
	_sprite.texture = art
	_sprite.centered = false
	_sprite.position = Vector2(-art.get_width() * 0.5, -art.get_height() + 1)
	# The cracks are drawn by this node, over its picture.
	_sprite.show_behind_parent = true
	add_child(_sprite)

## Shows the damage: cracks below 60% health, a broken roof below 30%.
func hurt(share: float) -> void:
	_damage = 1.0 - share
	_sprite.modulate = Color(1, 1, 1).lerp(Color(0.7, 0.66, 0.62), _damage)
	queue_redraw()

func _draw() -> void:
	if _damage < 0.4:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var w := art.get_width()
	var h := art.get_height()
	for k in int(_damage * 8):
		var start := Vector2(rng.randf_range(-w * 0.45, w * 0.45), rng.randf_range(-h * 0.35, -2))
		draw_polyline(PackedVector2Array([start, start + Vector2(rng.randf_range(-4, 4), 3), start + Vector2(rng.randf_range(-5, 5), 6)]), Color(0.15, 0.13, 0.11), 1.0)
	if _damage >= 0.7:
		draw_rect(Rect2(Vector2(-w * 0.2, -h + 6), Vector2(w * 0.3, h * 0.25)), Color(0.08, 0.07, 0.06))

func destroyed(_from: Vector2) -> void:
	var g := game()
	var o: TtwObstacle = entity.get_component(TtwObstacle) if entity != null else obstacle
	var center := position + o.offset
	if g != null:
		var t := g.terrain
		TtwStamps.crater(t, center, &"building")
		# Rubble: the footprint becomes broken ground, heaped.
		var lo := t.tile_of(center - o.half_extents)
		var hi := t.tile_of(center + o.half_extents)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				t.set_material(Vector2i(x, y), TtwMaterials.GRAVEL)
		var rng := RandomNumberGenerator.new()
		rng.seed = get_instance_id()
		for k in 10:
			var at := center + Vector2(rng.randf_range(-1, 1) * o.half_extents.x, rng.randf_range(-1, 1) * o.half_extents.y)
			TtwBrushes.paint(t, TtwBrushes.Kind.RAISE, at, rng.randf_range(4, 8), rng.randf_range(1.0, 2.5))
		TtwRubble.heap(get_parent(), center, o.half_extents, get_instance_id())
		g.fx.explode(center, &"building")
		var field := TtwGround.fire_of(session)
		if field != null:
			for tile in footprint():
				field.ignite(tile, 0.8)
	# The rubble keeps the fuel: what was inside burns on.
	fuel = 0.0
	retire()
