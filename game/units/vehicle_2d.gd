class_name TtwVehicle2D extends Node2D
## A ground vehicle on the map: its components are authored on the prefab
## (copied per instance), and it draws itself from them: the sprite for the
## nearest of eight facings, sunk into ruts and water, caked in mud, with a
## contact shadow.

const DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const SHADER := preload("res://shaders/vehicle.gdshader")
const REFLECTION_SHADER := preload("res://shaders/reflection.gdshader")
## How far up the screen a px of height is drawn (the terrain shader's tilt).
const TILT_K := 0.6

## assets/units/<art>/<direction>.png
@export var art: String = "truck"
@export var vehicle: TtwVehicle
@export var drive: TtwDrive
@export var fuel: TtwFuel
@export var condition: TtwCondition
@export var extra_components: Array[Component] = []
## Where the sprite's centre sits relative to the ground point under the body.
@export var sprite_offset: Vector2 = Vector2(0, -4)

var entity: Entity
var sprite: Sprite2D
var reflection: Sprite2D
var _textures: Array[Texture2D] = []
var _bottoms: PackedFloat32Array = []
var _heights: PackedFloat32Array = []
var _facing: int = -1

func kit_components() -> Array[Component]:
	return [KitSlots.take(vehicle, TtwVehicle), KitSlots.take(drive, TtwDrive),
		KitSlots.take(fuel, TtwFuel), KitSlots.take(condition, TtwCondition)]

func kit_bound(_session: KitSession, bound: Entity) -> void:
	entity = bound

func _ready() -> void:
	for direction in DIRECTIONS:
		var texture: Texture2D = load("res://assets/units/%s/%s.png" % [art, direction])
		_textures.append(texture)
		var used := texture.get_image().get_used_rect()
		_bottoms.append(float(used.end.y - 1))
		_heights.append(float(used.size.y))
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	sprite.material = shader_material
	sprite.position = sprite_offset
	reflection = Sprite2D.new()
	reflection.name = "Reflection"
	reflection.flip_v = true
	var mirror := ShaderMaterial.new()
	mirror.shader = REFLECTION_SHADER
	reflection.material = mirror
	reflection.visible = false
	add_child(reflection)
	add_child(sprite)
	_face(0)

## The facing (0 east, clockwise in eighths) nearest a heading.
static func facing_of(heading: float) -> int:
	return posmod(roundi(heading / (PI / 4.0)), 8)

func _face(index: int) -> void:
	if index == _facing:
		return
	_facing = index
	sprite.texture = _textures[index]
	reflection.texture = _textures[index]
	sprite.material.set_shader_parameter("bottom_row", _bottoms[index])
	sprite.material.set_shader_parameter("body_rows", _heights[index])

func _process(_delta: float) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var d: TtwDrive = entity.get_component(TtwDrive)
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	if d == null or v == null:
		return
	_face(facing_of(d.heading))
	var sink_rows := roundf(v.sink * TILT_K)
	sprite.position = sprite_offset + Vector2(0, sink_rows)
	sprite.material.set_shader_parameter("sink_rows", sink_rows)
	sprite.material.set_shader_parameter("grime", v.grime)
	sprite.material.set_shader_parameter("in_water", 1.0 if v.water_depth > 0.0 else 0.0)
	sprite.material.set_shader_parameter("wet", v.hull_wet)
	# Mirrored about the waterline (the sprite's bottom less what is under water).
	reflection.visible = v.water_depth > 0.5
	if reflection.visible:
		var texture_size := sprite.texture.get_size()
		var waterline := sprite.position.y - texture_size.y * 0.5 + _bottoms[_facing] + 1.0 - sink_rows
		reflection.position = Vector2(sprite.position.x, 2.0 * waterline - sprite.position.y)
		reflection.material.set_shader_parameter("strength", clampf(v.water_depth / 3.0, 0.0, 1.0))
	modulate = Color(0.55, 0.5, 0.48) if entity.has_component(TtwWrecked) else Color.WHITE
	queue_redraw()

func _draw() -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var d: TtwDrive = entity.get_component(TtwDrive)
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	var along := Vector2.from_angle(d.heading)
	var side := along.orthogonal()
	var half_length := maxf(v.tread_length_px * 0.5, absf(v.axles_px[0]) + 3.0 if not v.axles_px.is_empty() else 8.0)
	var half_width := v.gauge_px * 0.5 + v.contact_width_px * 0.5
	var points := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		points.append(along * cos(a) * half_length + side * sin(a) * half_width)
	draw_colored_polygon(points, Color(0, 0, 0, 0.22))
