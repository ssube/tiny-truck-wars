class_name TtwFire extends Node2D
## A fire burning on the ground (a wreck, spilt fuel): flames, a heat shimmer
## above them, firelight on the ground around, and smoke lit from below by
## the flames. Burns for `seconds`, dies down over the last few, then goes.

const FIRE_SHADER := preload("res://shaders/fire.gdshader")
const HAZE_SHADER := preload("res://shaders/heat_haze.gdshader")
const GLOW_SHADER := preload("res://shaders/fire_glow.gdshader")
const DIE_DOWN := 4.0
const SMOKE_EVERY := 0.35

var seconds: float = 20.0
## How hard it burns now (0..1), for fires the fire field keeps (seconds INF).
var strength: float = 1.0
var size: float = 1.0
var puffs: TtwPuffs
var noise_texture: Texture2D
## The firelight, drawn on the ground layer under units (set up by TtwFx).
var glow: Sprite2D
var _left: float = 0.0
var _smoke: float = 0.0
var _flames: Array[Sprite2D] = []
var _white: ImageTexture

func _ready() -> void:
	_left = seconds
	var image := Image.create(4, 4, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	var haze := _quad(HAZE_SHADER, Vector2(14, 22) * size, Vector2(0, -20) * size)
	haze.material.set_shader_parameter("noise_tex", noise_texture)
	for k in 3:
		var flame := _quad(FIRE_SHADER, Vector2(10, 16) * size * (1.0 - k * 0.2), Vector2((k - 1) * 4.0, -7.0) * size)
		flame.material.set_shader_parameter("noise_tex", noise_texture)
		flame.material.set_shader_parameter("seed", randf() * 10.0)
		_flames.append(flame)

func _quad(shader: Shader, extent: Vector2, offset: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _white
	sprite.scale = extent / 4.0
	sprite.position = offset
	var m := ShaderMaterial.new()
	m.shader = shader
	sprite.material = m
	add_child(sprite)
	return sprite

func intensity() -> float:
	return clampf(_left / DIE_DOWN, 0.0, 1.0) * strength

## Starts dying down now (the fire field's tile went out).
func die_down() -> void:
	_left = minf(_left, DIE_DOWN)

func _process(delta: float) -> void:
	_left -= delta
	var k := intensity()
	for flame in _flames:
		flame.material.set_shader_parameter("intensity", 0.4 + 0.7 * k)
	if glow != null:
		glow.material.set_shader_parameter("strength", 0.5 * k * size)
	_smoke -= delta
	if _smoke <= 0.0 and puffs != null:
		_smoke = SMOKE_EVERY
		puffs.puff(TtwPuffs.Kind.PLUME, global_position + Vector2(0, -14) * size, Vector2(4, -14), 3, size * (0.6 + 0.4 * k), 1.4 * k)
	if _left <= 0.0:
		if glow != null:
			glow.queue_free()
		queue_free()
