class_name TtwDebris extends Node2D
## Bits thrown about (mud clods, droplets, wreckage) with rough physics: they
## fly in an arc (height drawn up the screen at the terrain's tilt), bounce,
## then slide and roll down the ground's slope (elevation and ruts), slowed by
## what they land on; in water they drift with the current and sink. Droplets
## end where they land, with a ripple if that is water. Drawing only: nothing
## in the game reads them, so they step on the frame clock.
##
## At most MAX_BITS live; past that the oldest go first.
##
## Only the bits near what the camera shows are drawn, and only those move
## every frame: the rest move every FAR_EVERY-th frame, by that many frames'
## time at once. All the sheets are drawn from one texture (`_atlas`), so a
## frame's bits and their shadows go to the GPU together.

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
## Bits this far (px) outside the view still count as in it: a bit is drawn up
## the screen by its height, and the camera may have moved since the canvas
## last heard of it.
const VIEW_MARGIN_PX := 64.0
## Bits out of view move once in this many frames.
const FAR_EVERY := 4
## The longest step (s) a bit takes at once, in view and out of it.
const NEAR_STEP := 1.0 / 20.0
const FAR_STEP := 1.0 / 8.0

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
## The last draw had bits in it.
var _drawn_any := false
## Every sheet, one under the other with a clear row between, and a white
## block under them for the shadows.
var _atlas: ImageTexture
var _white: Rect2
var _frame: int = 0

func _ready() -> void:
	var row := FRAME_PX + 1
	var image := Image.create_empty(FRAMES * FRAME_PX, row * SHEETS.size() + 2, false, Image.FORMAT_RGBA8)
	for k in SHEETS.size():
		var sheet: Image = SHEETS[k].get_image()
		sheet.convert(Image.FORMAT_RGBA8)
		image.blit_rect(sheet, Rect2i(0, 0, FRAMES * FRAME_PX, FRAME_PX), Vector2i(0, k * row))
	_white = Rect2(0, row * SHEETS.size(), 2, 2)
	image.fill_rect(Rect2i(_white), Color.WHITE)
	_atlas = ImageTexture.create_from_image(image)

## What the camera shows, grown by VIEW_MARGIN_PX (everything, without one).
func view_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var screen := viewport.get_visible_rect()
	var a := inverse * screen.position
	var b := inverse * screen.end
	return Rect2(a.min(b), (b - a).abs()).grow(VIEW_MARGIN_PX)

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
	# With no bits there is nothing to move, and nothing to draw once the
	# last of them has been cleared.
	if terrain == null or (position3.is_empty() and not _drawn_any):
		return
	_frame += 1
	var near := view_rect()
	var near_dt := minf(delta, NEAR_STEP)
	var far_dt := minf(delta * FAR_EVERY, FAR_STEP)
	var k := 0
	while k < position3.size():
		var p := position3[k]
		var dt := near_dt
		if not near.has_point(Vector2(p.x, p.y)):
			# Out of view: its turn comes every FAR_EVERY-th frame. (A bit removed
			# ahead of it shifts whose turn it is: one may wait a frame more or less.)
			if (k + _frame) % FAR_EVERY != 0:
				k += 1
				continue
			dt = far_dt
		if _move(k, dt):
			k += 1
		else:
			_remove(k)
	_drawn_any = not position3.is_empty()
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
	var near := view_rect()
	var size := Vector2(FRAME_PX, FRAME_PX)
	var row := FRAME_PX + 1
	for k in position3.size():
		var p := position3[k]
		var at := Vector2(p.x, p.y)
		if not near.has_point(at):
			continue
		var ground := terrain.relief_at(at)
		var screen := Vector2(p.x, p.y - (p.z + ground) * TILT_K).round()
		var kind := kinds[k]
		var alpha := 1.0
		if landed[k] > 0.0 and kind != Kind.DROPLET:
			var life: float = FLOAT_SECONDS if terrain.water_depth_at(at) > 0.0 else REST_SECONDS[kind]
			alpha = clampf((life - landed[k]) / 1.0, 0.0, 1.0)
		if p.z > 0.5:
			draw_texture_rect_region(_atlas, Rect2(Vector2(p.x, p.y - ground * TILT_K).round() - Vector2(1, 0), Vector2(2, 1)), _white, Color(0, 0, 0, 0.25))
		draw_texture_rect_region(_atlas, Rect2(screen - size * 0.5, size), Rect2(frames[k] * FRAME_PX, kind * row, FRAME_PX, FRAME_PX), Color(1, 1, 1, alpha))
