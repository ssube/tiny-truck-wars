class_name TtwPuffs extends Node2D
## Dust and smoke from pooled CPUParticles2D, one pool per kind. Taking an
## emitter never makes a new one: when a pool is busy the one that started
## longest ago is restarted. A budget caps the particles alive at once; a puff
## past it is skipped.

enum Kind { DUST, EXHAUST, PLUME }

const POOL := 16
const BUDGET := 900
const DUST_SHEET := preload("res://assets/fx/dust.png")
const SMOKE_SHADER := preload("res://shaders/smoke.gdshader")

var noise_texture: Texture2D
## The wind now (px/s): puffs drift with a share of it (DRIFT by kind).
var wind: Vector2 = Vector2.ZERO
const DRIFT := [0.5, 0.6, 0.45]
var _pools: Array = [[], [], []]
var _next: PackedInt32Array = [0, 0, 0]

func _ready() -> void:
	for kind in Kind.size():
		for i in POOL:
			var e := _make(kind)
			add_child(e)
			_pools[kind].append(e)

## Live particles across every pool (an upper bound: emitting emitters' amounts).
func live() -> int:
	var total := 0
	for pool in _pools:
		for e: CPUParticles2D in pool:
			if e.emitting:
				total += e.amount
	return total

func emitters() -> int:
	return get_child_count()

## A puff of `kind` at `at` moving along `direction` (px/s); `amount` particles,
## `scale` × the kind's size, `underlight` from fire below (smoke only).
func puff(kind: int, at: Vector2, direction: Vector2 = Vector2.ZERO, amount: int = 0, scale: float = 1.0, underlight: float = 0.0) -> bool:
	var pool: Array = _pools[kind]
	var e: CPUParticles2D = pool[_next[kind]]
	_next[kind] = (_next[kind] + 1) % POOL
	var count: int = amount if amount > 0 else int(e.get_meta(&"amount", 4))
	var freed: int = e.amount if e.emitting else 0
	if live() - freed + count > BUDGET:
		return false
	e.emitting = false
	e.amount = count
	e.position = at
	e.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.UP
	var speed: float = e.get_meta(&"speed", 10.0)
	e.initial_velocity_min = speed * 0.5 + direction.length() * 0.3
	e.initial_velocity_max = speed + direction.length() * 0.5
	e.scale_amount_min = e.get_meta(&"scale", 1.0) * scale * 0.7
	e.scale_amount_max = e.get_meta(&"scale", 1.0) * scale * 1.2
	e.gravity = e.get_meta(&"gravity", Vector2.ZERO) + wind * DRIFT[kind]
	if e.material is ShaderMaterial:
		(e.material as ShaderMaterial).set_shader_parameter("underlight", underlight)
	e.restart()
	e.emitting = true
	return true

func _make(kind: int) -> CPUParticles2D:
	var e := CPUParticles2D.new()
	e.one_shot = true
	e.emitting = false
	e.local_coords = false
	e.explosiveness = 0.85
	e.spread = 35.0
	e.gravity = Vector2.ZERO
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	e.color_ramp = fade
	match kind:
		Kind.DUST:
			e.texture = DUST_SHEET
			var m := CanvasItemMaterial.new()
			m.particles_animation = true
			m.particles_anim_h_frames = 6
			m.particles_anim_v_frames = 1
			e.material = m
			e.anim_speed_min = 1.0
			e.anim_speed_max = 1.0
			e.lifetime = 1.1
			e.damping_min = 10.0
			e.damping_max = 20.0
			e.gravity = Vector2(0, -6)
			e.set_meta(&"amount", 3)
			e.set_meta(&"speed", 12.0)
			e.set_meta(&"scale", 1.3)
		Kind.EXHAUST, Kind.PLUME:
			# One texel per world px at the kind's typical size.
			var texels := 12 if kind == Kind.EXHAUST else 28
			var image := Image.create(texels, texels, false, Image.FORMAT_L8)
			image.fill(Color.WHITE)
			e.texture = ImageTexture.create_from_image(image)
			var m := ShaderMaterial.new()
			m.shader = SMOKE_SHADER
			m.set_shader_parameter("noise_tex", noise_texture)
			m.set_shader_parameter("texels", float(texels))
			e.material = m
			e.anim_offset_max = 1.0 # a seed per puff (INSTANCE_CUSTOM.z)
			if kind == Kind.EXHAUST:
				e.lifetime = 1.4
				e.gravity = Vector2(0, -10)
				e.set_meta(&"amount", 2)
				e.set_meta(&"speed", 8.0)
				e.set_meta(&"scale", 0.7)
				e.scale_amount_curve = _grow(0.6, 1.4)
			else:
				e.lifetime = 3.2
				e.explosiveness = 0.6
				e.gravity = Vector2(0, -22)
				e.spread = 60.0
				e.set_meta(&"amount", 10)
				e.set_meta(&"speed", 14.0)
				e.set_meta(&"scale", 0.8)
				e.scale_amount_curve = _grow(0.5, 1.6)
	e.set_meta(&"gravity", e.gravity)
	return e

static func _grow(from: float, to: float) -> Curve:
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0, from))
	curve.add_point(Vector2(1, to))
	return curve
