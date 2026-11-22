class_name TtwLog2D extends TtwProp2D
## A fallen trunk lying along its rotation: a box obstacle. Destroyed, it
## splinters. In water it floats off with the current (TtwObstacleSystem).

const LOG := preload("res://assets/world/log.png")

func kit_components() -> Array[Component]:
	var mine := super()
	mine.append(TtwLog.new())
	return mine

func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = LOG
	var length := (obstacle.half_extents.x * 2.0) if obstacle != null else 40.0
	sprite.scale = Vector2(length / LOG.get_width(), 1.0)
	add_child(sprite)

func destroyed(from: Vector2) -> void:
	var g := game()
	if g != null:
		var along := Vector2.from_angle(rotation)
		for k in 4:
			var at := position + along * (k - 1.5) * 9.0
			g.fx.debris.throw(TtwDebris.Kind.DEBRIS, Vector3(at.x, at.y, 2.0), (at - from).normalized(), 35.0, 1.5, 50.0, 3)
		g.fx.puffs.puff(TtwPuffs.Kind.DUST, position, Vector2.ZERO, 4, 1.0)
	retire()
