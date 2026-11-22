class_name TtwTree2D extends TtwProp2D
## A standing tree. It sways with the wind; destroyed, it falls away from what
## hit it (a short tilt about its base) and becomes a log lying that way,
## leaving a stump and splinters.

const SWAY := preload("res://shaders/wind_sway.gdshader")
const STUMP := preload("res://assets/world/stump.png")
const FALL_SECONDS := 0.7

@export var art: Texture2D = preload("res://assets/world/tree_oak_0.png")
@export var tree: TtwTree

var _pivot: Node2D
var _sprite: Sprite2D

func kit_components() -> Array[Component]:
	var mine := super()
	mine.append(KitSlots.take(tree, TtwTree))
	return mine

func _ready() -> void:
	_pivot = Node2D.new()
	add_child(_pivot)
	_sprite = Sprite2D.new()
	_sprite.texture = art
	_sprite.centered = false
	_sprite.position = Vector2(-art.get_width() * 0.5, -art.get_height() + 2)
	var m := ShaderMaterial.new()
	m.shader = SWAY
	m.set_shader_parameter("lean_pixels", 2.0)
	m.set_shader_parameter("rest_v", 0.75)
	m.set_shader_parameter("full_v", 0.1)
	_sprite.material = m
	_pivot.add_child(_sprite)

## Falls away from `from`: tilts over, then lies as a log.
func destroyed(from: Vector2) -> void:
	var away := position - from
	var direction := away.normalized() if away.length() > 0.5 else Vector2.RIGHT
	if static_body != null:
		static_body.queue_free()
		static_body = null
	var tween := create_tween()
	tween.tween_property(_pivot, "rotation", direction.x * PI * 0.5, FALL_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(_pivot, "scale", Vector2(1.0, lerpf(1.0, 0.35, absf(direction.y))), FALL_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _lie(direction))

func _lie(direction: Vector2) -> void:
	var g := game()
	var length: float = (entity.get_component(TtwTree) as TtwTree).height_px if entity != null else 40.0
	if g != null:
		g.spawn_prop(&"log", position + direction * length * 0.5, direction.angle())
		g.fx.debris.throw(TtwDebris.Kind.DEBRIS, Vector3(position.x + direction.x * length, position.y + direction.y * length, 2.0), direction, 30.0, 2.0, 40.0, 6)
		g.fx.puffs.puff(TtwPuffs.Kind.DUST, position + direction * length * 0.6, direction * 10.0, 4, 1.0)
		var stump := Sprite2D.new()
		stump.texture = STUMP
		stump.position = position + Vector2(0, -3)
		get_parent().add_child(stump)
	retire()
