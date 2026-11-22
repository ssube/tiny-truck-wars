class_name TtwSmokeScreen extends Node2D
## The hippy's smoke screen: a few large, slow, shaded billows over an area for
## `seconds`, then thinning out. (Slowing units inside comes with the rules.)

const SMOKE_SHADER := preload("res://shaders/smoke.gdshader")
## Billow size in px: one texel per world px, like the rest of the art.
const TEXELS := 44

var radius_px: float = 48.0
var seconds: float = 12.0
var noise_texture: Texture2D
## The wind now (px/s, set by TtwFx): the screen drifts with a share of it.
var wind: Vector2 = Vector2.ZERO
const DRIFT := 0.25
var _particles: CPUParticles2D
var _left: float

func _ready() -> void:
	_left = seconds
	_particles = CPUParticles2D.new()
	_particles.amount = 18
	_particles.lifetime = 5.0
	_particles.preprocess = 2.0
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = radius_px * 0.7
	_particles.gravity = Vector2(3, -2)
	_particles.initial_velocity_min = 2.0
	_particles.initial_velocity_max = 6.0
	_particles.spread = 180.0
	_particles.anim_offset_max = 1.0
	_particles.scale_amount_min = 0.8
	_particles.scale_amount_max = 1.15
	var image := Image.create(TEXELS, TEXELS, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	_particles.texture = ImageTexture.create_from_image(image)
	var fade := Gradient.new()
	fade.set_color(0, Color(0.95, 0.95, 0.95, 0.0))
	fade.add_point(0.25, Color(0.95, 0.95, 0.95, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(0.95, 0.95, 0.95, 0.0))
	_particles.color_ramp = fade
	var m := ShaderMaterial.new()
	m.shader = SMOKE_SHADER
	m.set_shader_parameter("noise_tex", noise_texture)
	m.set_shader_parameter("smoke_light", Color(0.92, 0.92, 0.9))
	m.set_shader_parameter("smoke_dark", Color(0.55, 0.56, 0.58))
	m.set_shader_parameter("texels", float(TEXELS))
	_particles.material = m
	add_child(_particles)

func _process(delta: float) -> void:
	_left -= delta
	position += wind * DRIFT * delta
	_particles.gravity = Vector2(3, -2) + wind * 0.15
	if _left <= 0.0 and _particles.emitting:
		_particles.emitting = false
	if _left <= -_particles.lifetime:
		queue_free()
