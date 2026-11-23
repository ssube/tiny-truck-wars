class_name TtwRubble extends RefCounted
## The heap a destroyed building or structure leaves: one of four pictures,
## drawn 1:1 over the middle of its footprint, its foot on the footprint's
## front edge. The ground under it is made broken by whoever destroyed it;
## this is only the picture, kept in saves (TtwSave.RUBBLE_GROUP).

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/world/rubble_1.png"),
	preload("res://assets/world/rubble_2.png"),
	preload("res://assets/world/rubble_3.png"),
	preload("res://assets/world/rubble_4.png"),
]

## A heap for a footprint centred at `center` reaching `half_extents`, under
## `parent`; `seed` picks the picture (the same seed, the same heap).
static func heap(parent: Node, center: Vector2, half_extents: Vector2, seed: int) -> Sprite2D:
	var variant := posmod(seed, TEXTURES.size())
	return _place(parent, center + Vector2(0, half_extents.y), variant)

## A heap as a save recorded it (`record()`).
static func restore(parent: Node, saved: Dictionary) -> Sprite2D:
	return _place(parent, saved.foot, int(saved.variant))

## What a save keeps of a heap.
static func record(sprite: Sprite2D) -> Dictionary:
	return {"foot": sprite.get_meta(&"foot"), "variant": sprite.get_meta(&"variant")}

static func _place(parent: Node, foot: Vector2, variant: int) -> Sprite2D:
	var texture := TEXTURES[variant]
	var used := texture.get_image().get_used_rect()
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = (foot - Vector2(used.get_center().x, used.end.y - 1)).round()
	sprite.set_meta(&"foot", foot)
	sprite.set_meta(&"variant", variant)
	sprite.add_to_group(TtwSave.RUBBLE_GROUP)
	parent.add_child(sprite)
	return sprite
