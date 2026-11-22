class_name TtwAircraft2D extends Node2D
## A helicopter on the map. Its origin is the ground point under it (where
## its shadow falls); the sprite is lifted by its height, nearest of eight
## facings, with the rotor's blur drawn over it. Drawn over ground units.

const DIRECTIONS := TtwVehicle2D.DIRECTIONS
const TILT_K := TtwVehicle2D.TILT_K

## assets/units/<art>/<direction>.png
@export var art: String = "helicopter"
@export var flight: TtwFlight
@export var fuel: TtwFuel
@export var condition: TtwCondition
@export var extra_components: Array[Component] = []
## Where the sprite's centre sits over the ground point when landed.
@export var sprite_offset: Vector2 = Vector2(0, -8)
@export var rotor_px: float = 22.0

var entity: Entity
var sprite: Sprite2D
var _textures: Array[Texture2D] = []
var _facing: int = -1
var _spin: float = 0.0

func kit_components() -> Array[Component]:
	return [TtwAircraft.new(), KitSlots.take(flight, TtwFlight), KitSlots.take(fuel, TtwFuel), KitSlots.take(condition, TtwCondition)]

func kit_bound(_session: KitSession, bound: Entity) -> void:
	entity = bound

func _ready() -> void:
	z_index = 4
	for direction in DIRECTIONS:
		_textures.append(load("res://assets/units/%s/%s.png" % [art, direction]))
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.position = sprite_offset
	add_child(sprite)
	_face(2)

func _face(index: int) -> void:
	if index != _facing:
		_facing = index
		sprite.texture = _textures[index]

func _process(delta: float) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var f: TtwFlight = entity.get_component(TtwFlight)
	_face(TtwVehicle2D.facing_of(f.heading))
	sprite.position = sprite_offset - Vector2(0, roundf(f.altitude * TILT_K))
	var wrecked := entity.has_component(TtwWrecked)
	modulate = Color(0.5, 0.46, 0.44) if wrecked else Color.WHITE
	var running := not wrecked and (f.airborne() or entity.has_component(TtwMoveOrder))
	_spin = fposmod(_spin + delta * (30.0 if running else 0.0), TAU)
	queue_redraw()

func _draw() -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var f: TtwFlight = entity.get_component(TtwFlight)
	# The shadow, smaller and fainter the higher it is.
	var lift := clampf(f.altitude / maxf(f.cruise_px, 1.0), 0.0, 1.0)
	var points := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		points.append(Vector2(cos(a) * 14.0, sin(a) * 6.0) * (1.0 - 0.3 * lift))
	draw_colored_polygon(points, Color(0, 0, 0, 0.25 - 0.1 * lift))
	if _spin != 0.0 or f.airborne():
		var hub := sprite.position + Vector2(0, -6)
		for k in 2:
			var a := _spin + PI * 0.5 * k
			var along := Vector2(cos(a), sin(a) * 0.5) * rotor_px
			draw_line(hub - along, hub + along, Color(0.1, 0.1, 0.1, 0.35), 1.0)
		draw_arc(hub, rotor_px, 0.0, TAU, 24, Color(0.2, 0.2, 0.2, 0.08), 1.0)
