class_name TtwPrecipitation extends Node2D
## Rain and snow over the camera's view (ported from the 2D kit's
## KitWeather2D): two emitters that follow the camera, as heavy as the
## weather says, slanted and drifting with the wind.

var weather: TtwWeather
var camera: Camera2D
var _rain: CPUParticles2D
var _snow: CPUParticles2D
var _applied := Vector3(-1, -1, NAN)

func _ready() -> void:
	_rain = _emitter(Color(0.72, 0.8, 0.95, 0.55), Vector2(1, 4))
	_rain.lifetime = 0.9
	_rain.initial_velocity_min = 260.0
	_rain.initial_velocity_max = 320.0
	_rain.spread = 2.0
	_snow = _emitter(Color(0.95, 0.96, 1.0, 0.9), Vector2(2, 2))
	_snow.lifetime = 5.0
	_snow.initial_velocity_min = 18.0
	_snow.initial_velocity_max = 30.0
	_snow.spread = 25.0

func _emitter(tint: Color, size: Vector2i) -> CPUParticles2D:
	var e := CPUParticles2D.new()
	e.emitting = false
	e.local_coords = false
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.color = tint
	var image := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	e.texture = ImageTexture.create_from_image(image)
	add_child(e)
	return e

func _process(_delta: float) -> void:
	if weather == null or camera == null:
		return
	var view := get_viewport().get_visible_rect().size / camera.zoom
	position = camera.get_screen_center_position() - Vector2(0, view.y * 0.6)
	var wanted := Vector3(snappedf(weather.rain, 0.05), snappedf(weather.snowfall, 0.05), snappedf(weather.wind_now.x, 2.0))
	if wanted == _applied:
		return
	_applied = wanted
	for e: CPUParticles2D in [_rain, _snow]:
		e.emission_rect_extents = Vector2(view.x * 0.7, 2.0)
	_apply_amount(_rain, weather.rain, 400, Vector2(weather.wind_now.x * 0.004, 1.0))
	_apply_amount(_snow, weather.snowfall, 260, Vector2(0.0, 1.0))
	_snow.gravity = Vector2(weather.wind_now.x * 0.6, 4.0)

func _apply_amount(e: CPUParticles2D, amount: float, most: int, direction: Vector2) -> void:
	e.emitting = amount > 0.01
	if e.emitting:
		var count := maxi(1, int(most * amount))
		if e.amount != count:
			e.amount = count
		e.direction = direction.normalized()
