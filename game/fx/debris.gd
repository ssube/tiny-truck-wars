class_name TtwDebris extends Node2D
## Bits thrown about (mud clods, droplets, wreckage) with rough physics: they
## fly in an arc (height drawn up the screen at the terrain's tilt), bounce,
## then slide and roll down the ground's slope (elevation and ruts), slowed by
## what they land on; in water they drift with the current and sink. Droplets
## end where they land, with a ripple if that is water. Drawing only: nothing
## in the game reads them, so they step on the frame clock.
##
## At most MAX_BITS live; past that the oldest go first.

enum Kind { CLOD, DROPLET, DEBRIS }

const SHEETS := [preload("res://assets/fx/mud_clods.png"), preload("res://assets/fx/droplets.png"), preload("res://assets/fx/debris.png")]
const FRAMES := 4
const FRAME_PX := 6
const MAX_BITS := 600
## px/s² down; share of the fall speed kept on a bounce; below it, it lands.
const GRAVITY := 260.0
const BOUNCE := 0.3
const LAND_SPEED := 30.0
## How hard a slope (px per px) pushes a resting bit (px/s²).
const SLIDE := 140.0
## How fast motion dies on each material (1/s): mud holds, pavement lets go.
const FRICTION := [7.0, 5.0, 1.6, 3.0, 4.5, 2.0]
## How long a bit lies about after landing (s), and how long it floats.
const REST_SECONDS := [2.5, 0.0, 14.0]
const FLOAT_SECONDS := 2.5
## How quickly the current takes over a floating bit (1/s).
const CURRENT_GRIP := 2.5
const TILT_K := 0.6

var terrain: TtwTerrain
var water_fx: TtwWaterFx
## The wind now (px/s): bits in the air are pushed by a little of it.
var wind: Vector2 = Vector2.ZERO
const WIND_PUSH := 0.6
## Per bit: x, y (world px), z (px above the ground under it).
var position3: PackedVector3Array = []
var velocity3: PackedVector3Array = []
var kinds: PackedInt32Array = []
var frames: PackedInt32Array = []
## Seconds since it landed (negative while in the air).
var landed: PackedFloat32Array = []
var _rng := RandomNumberGenerator.new()

func count() -> int:
	return position3.size()

## Throws `amount` bits of `kind` from `at` (z above the ground) along
## `direction` (world, xy) at about `speed` px/s, spread over `spread` radians,
## with `lift` px/s upward.
func throw(kind: int, at: Vector3, direction: Vector2, speed: float, spread: float, lift: float, amount: int) -> void:
	for i in amount:
		if position3.size() >= MAX_BITS:
			_remove(0)
		var angle := direction.angle() + _rng.randf_range(-spread, spread) * 0.5
		var pace := speed * _rng.randf_range(0.6, 1.2)
		position3.append(at)
		velocity3.append(Vector3(cos(angle) * pace, sin(angle) * pace, lift * _rng.randf_range(0.7, 1.3)))
		kinds.append(kind)
		frames.append(_rng.randi() % FRAMES)
		landed.append(-1.0)

func _process(delta: float) -> void:
	step(minf(delta, 1.0 / 20.0))
	queue_redraw()

## Moves every bit on by `dt` seconds.
func step(dt: float) -> void:
	if terrain == null:
		return
	var k := 0
	while k < position3.size():
		if _move(k, dt):
			k += 1
		else:
			_remove(k)

## One bit; false when it is done.
func _move(k: int, dt: float) -> bool:
	var p := position3[k]
	var v := velocity3[k]
	var at := Vector2(p.x, p.y)
	if p.z > 0.0 or v.z > 0.0:
		v.z -= GRAVITY * dt
		v.x += wind.x * WIND_PUSH * dt
		v.y += wind.y * WIND_PUSH * dt
		p += v * dt
		if p.z <= 0.0:
			p.z = 0.0
			var depth := terrain.water_depth_at(Vector2(p.x, p.y))
			if kinds[k] == Kind.DROPLET:
				if depth > 0.0 and water_fx != null:
					water_fx.splash(Vector2(p.x, p.y), 1.5, 0.05, 0.0, 0.45)
				return false
			if depth > 0.0 and water_fx != null:
				water_fx.splash(Vector2(p.x, p.y), 2.0, 0.1, 0.05, 0.6)
			if -v.z > LAND_SPEED * 2.0 and depth <= 0.0:
				v.z = -v.z * BOUNCE
				v.x *= 0.6
				v.y *= 0.6
			else:
				v.z = 0.0
				landed[k] = 0.0
		position3[k] = p
		velocity3[k] = v
		frames[k] = (frames[k] + (1 if Engine.get_process_frames() % 4 == 0 else 0)) % FRAMES
		return p.x >= 0.0 and p.y >= 0.0 and p.x < terrain.size_px().x and p.y < terrain.size_px().y
	# On the ground or in water.
	landed[k] += dt
	var depth := terrain.water_depth_at(at)
	var flat := Vector2(v.x, v.y)
	if depth > 0.0:
		flat = flat.lerp(terrain.current_at(at), minf(1.0, CURRENT_GRIP * dt))
		if landed[k] > FLOAT_SECONDS:
			return false
	else:
		var slope := terrain.elevation_gradient(at) + _relief_gradient(at)
		flat -= slope * SLIDE * dt
		flat *= exp(-FRICTION[terrain.effective_material_at(at)] * dt)
		if landed[k] > REST_SECONDS[kinds[k]]:
			return false
	at += flat * dt
	position3[k] = Vector3(at.x, at.y, 0.0)
	velocity3[k] = Vector3(flat.x, flat.y, 0.0)
	return at.x >= 0.0 and at.y >= 0.0 and at.x < terrain.size_px().x and at.y < terrain.size_px().y

func _relief_gradient(at: Vector2) -> Vector2:
	var e := TtwTerrain.cell_px()
	return Vector2(terrain.relief_at(at + Vector2(e, 0)) - terrain.relief_at(at - Vector2(e, 0)),
		terrain.relief_at(at + Vector2(0, e)) - terrain.relief_at(at - Vector2(0, e))) / (2.0 * e)

func _remove(k: int) -> void:
	position3.remove_at(k)
	velocity3.remove_at(k)
	kinds.remove_at(k)
	frames.remove_at(k)
	landed.remove_at(k)

func _draw() -> void:
	if terrain == null:
		return
	for k in position3.size():
		var p := position3[k]
		var ground := terrain.relief_at(Vector2(p.x, p.y))
		var screen := Vector2(p.x, p.y - (p.z + ground) * TILT_K).round()
		var region := Rect2(frames[k] * FRAME_PX, 0, FRAME_PX, FRAME_PX)
		var alpha := 1.0
		if landed[k] > 0.0 and kinds[k] != Kind.DROPLET:
			var life: float = FLOAT_SECONDS if terrain.water_depth_at(Vector2(p.x, p.y)) > 0.0 else REST_SECONDS[kinds[k]]
			alpha = clampf((life - landed[k]) / 1.0, 0.0, 1.0)
		if p.z > 0.5:
			draw_rect(Rect2(Vector2(p.x, p.y - ground * TILT_K).round() - Vector2(1, 0), Vector2(2, 1)), Color(0, 0, 0, 0.25))
		draw_texture_rect_region(SHEETS[kinds[k]], Rect2(screen - Vector2(FRAME_PX, FRAME_PX) * 0.5, Vector2(FRAME_PX, FRAME_PX)), region, Color(1, 1, 1, alpha))
