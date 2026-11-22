class_name TtwWaterFx extends Node
## The water's visual detail on the GPU (shaders/water_fx.gdshader): foam and
## silt carried by the simulated current, and ripples from wakes, splashes and
## rain. Never read back: it only changes how the water looks.

const STEP_SHADER := preload("res://shaders/water_fx.gdshader")
## Texels per tile side.
const TEXELS_PER_TILE := 4
## The longest frame stepped at once (a long frame steps as this).
const MAX_DT := 1.0 / 30.0
## Splashes taken per frame (the shader's MAX_SPLASHES); more are merged into
## the nearest already queued.
const MAX_SPLASHES := 64

var terrain: TtwTerrain
var viewport: SubViewport
var rain: float = 0.0:
	set(value):
		rain = value
		if _step != null:
			_step.set_shader_parameter("rain", rain)
var _step: ShaderMaterial
var _rect: ColorRect
var _at: PackedVector4Array = []
## Sprays falling back like local rain: {"at", "radius", "left", "seconds", "drops"}.
var _sprays: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _amount: PackedVector4Array = []

func _init() -> void:
	name = "WaterFx"

func show_terrain(value: TtwTerrain, view: TtwTerrainView) -> void:
	terrain = value
	if viewport == null:
		viewport = SubViewport.new()
		viewport.name = "Buffer"
		viewport.world_2d = World2D.new()
		viewport.transparent_bg = true
		viewport.use_hdr_2d = true
		viewport.disable_3d = true
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		_rect = ColorRect.new()
		_step = ShaderMaterial.new()
		_step.shader = STEP_SHADER
		_rect.material = _step
		viewport.add_child(_rect)
	var texels := terrain.size_tiles * TEXELS_PER_TILE
	viewport.size = texels
	_rect.size = Vector2(texels)
	_step.set_shader_parameter("water_tex", view.water_texture)
	_step.set_shader_parameter("flow_tex", view.flow_texture)
	_step.set_shader_parameter("map_px", terrain.size_px())
	_step.set_shader_parameter("texels", Vector2(texels))
	_step.set_shader_parameter("rain", rain)
	view.set_look(&"fx_tex", viewport.get_texture())

func _process(delta: float) -> void:
	if _step == null:
		return
	_step.set_shader_parameter("dt", minf(delta, MAX_DT))
	_fall(delta)
	# This frame's splashes, then none until more come.
	_step.set_shader_parameter("splash_count", _at.size())
	if not _at.is_empty():
		var at := _at.duplicate()
		var amount := _amount.duplicate()
		at.resize(MAX_SPLASHES)
		amount.resize(MAX_SPLASHES)
		_step.set_shader_parameter("splash_at", at)
		_step.set_shader_parameter("splash_amount", amount)
		_at.clear()
		_amount.clear()

## Adds a splash at a world point: foam and silt (0..1) and a ripple (px of
## height) over `radius_px`. Drawn on the next frame.
func splash(world: Vector2, radius_px: float, foam: float, silt: float, ripple: float) -> void:
	if _step == null or terrain == null:
		return
	var scale := float(TEXELS_PER_TILE) / TtwTerrain.tile_px()
	var at := Vector4(world.x * scale, world.y * scale, maxf(radius_px * scale, 0.75), 0.0)
	var amount := Vector4(foam, silt, ripple, 0.0)
	if _at.size() >= MAX_SPLASHES:
		var nearest := 0
		for k in _at.size():
			if Vector2(_at[k].x, _at[k].y).distance_squared_to(Vector2(at.x, at.y)) < Vector2(_at[nearest].x, _at[nearest].y).distance_squared_to(Vector2(at.x, at.y)):
				nearest = k
		_amount[nearest] += amount
		return
	_at.append(at)
	_amount.append(amount)

## Water thrown up (a blast in a river) coming down like local rain: about
## `drops` small drops over `seconds`, landing from the middle outward to
## `radius_px`, each starting its own ring.
func spray(world: Vector2, radius_px: float, seconds: float = 1.2, drops: int = 90) -> void:
	_sprays.append({"at": world, "radius": radius_px, "left": seconds, "seconds": seconds, "drops": float(drops)})

func _fall(delta: float) -> void:
	for k in range(_sprays.size() - 1, -1, -1):
		var s: Dictionary = _sprays[k]
		var share: float = minf(delta, s.left) / s.seconds
		s.left -= delta
		# Most falls early, close in; the last of it lands furthest out.
		var through: float = 1.0 - maxf(s.left, 0.0) / s.seconds
		var count := int(s.drops * share * 2.0 * (1.0 - through) + _rng.randf())
		for i in count:
			var reach: float = s.radius * sqrt(_rng.randf()) * (0.4 + 0.6 * through)
			var point: Vector2 = s.at + Vector2.from_angle(_rng.randf() * TAU) * reach
			splash(point, 1.5, 0.08, 0.0, 0.5 + _rng.randf() * 0.4)
		if s.left <= 0.0:
			_sprays.remove_at(k)

