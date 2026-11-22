class_name TtwFx extends Node
## Every visual effect on the map behind one door: thrown bits (TtwDebris),
## dust and smoke (TtwPuffs), fires, smoke screens and the water's detail
## (TtwWaterFx). Drawing only: the game never reads any of it back.
##
## `ground` holds what lies on the ground under units (firelight); `air` what
## rises above them (bits, puffs, flames).

const GLOW_SHADER := preload("res://shaders/fire_glow.gdshader")

var terrain: TtwTerrain
var water: TtwWaterFx
var ground: Node2D
var air: Node2D
var debris: TtwDebris
var puffs: TtwPuffs
var noise_texture: ImageTexture
## The map's weather (wind, rain), or null.
var weather: TtwWeather
var view: TtwTerrainView
var precipitation: TtwPrecipitation
var _wind_direction := Vector2.ZERO

func _init() -> void:
	name = "Fx"
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 1.0 / 16.0
	noise.fractal_octaves = 3
	var image := noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_L8)
	noise_texture = ImageTexture.create_from_image(image)

## Sets up the two layers: `ground_layer` under units, `air_layer` over them.
func bind(ground_layer: Node2D, air_layer: Node2D, water_fx: TtwWaterFx) -> void:
	ground = ground_layer
	air = air_layer
	water = water_fx
	debris = TtwDebris.new()
	debris.name = "Debris"
	debris.water_fx = water_fx
	air.add_child(debris)
	puffs = TtwPuffs.new()
	puffs.name = "Puffs"
	puffs.noise_texture = noise_texture
	air.add_child(puffs)

func show_terrain(value: TtwTerrain) -> void:
	terrain = value
	debris.terrain = value

var _screens: Array[TtwSmokeScreen] = []

## Passes the wind and rain on to everything that drifts.
func _process(_delta: float) -> void:
	if weather == null:
		return
	var wind := weather.wind_now
	debris.wind = wind
	puffs.wind = wind
	# A screen that has blown away is freed: drop it without touching it
	# (a typed array refuses to erase a freed object).
	var live := _screens.filter(func(s) -> bool: return is_instance_valid(s))
	if live.size() != _screens.size():
		_screens.assign(live)
	for s in _screens:
		s.wind = wind
	if water != null:
		water.rain = weather.rain
	_blow_sand(wind)
	# Still water's waves run with the wind (re-set only when it turns).
	var direction := weather.wind.normalized() if weather.wind.length() > 1.0 else Vector2(1.0, 0.3).normalized()
	if view != null and direction.distance_to(_wind_direction) > 0.05:
		_wind_direction = direction
		view.set_look(&"still_direction", direction)

## A fire at `at` for `seconds`, `size` × a wreck fire.
func fire(at: Vector2, seconds: float = 20.0, size: float = 1.0) -> TtwFire:
	var f := TtwFire.new()
	f.position = at
	f.seconds = seconds
	f.size = size
	f.puffs = puffs
	f.noise_texture = noise_texture
	var glow := Sprite2D.new()
	var image := Image.create(4, 4, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	glow.texture = ImageTexture.create_from_image(image)
	glow.scale = Vector2(56, 40) * size / 4.0
	glow.position = at
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("seed", randf() * 10.0)
	glow.material = m
	ground.add_child(glow)
	f.glow = glow
	air.add_child(f)
	return f

## The hippy's smoke screen over `radius_px` around `at`.
func smoke_screen(at: Vector2, radius_px: float = 48.0, seconds: float = 12.0) -> TtwSmokeScreen:
	var s := TtwSmokeScreen.new()
	s.position = at
	s.radius_px = radius_px
	s.seconds = seconds
	s.noise_texture = noise_texture
	air.add_child(s)
	_screens.append(s)
	return s

## The look of an explosion of `cause` (no fire: TtwGame.explode lights the
## fire field where there is something to burn) (TtwStamps.CRATERS) at `at`: thrown
## earth or wreckage, dust, a smoke plume, fire for wrecks and buildings, and
## in water a burst of silt and foam, rings and a spray falling like rain.
## (The crater itself is the terrain's: TtwStamps.crater.)
func explode(at: Vector2, cause: StringName) -> void:
	var size: Vector2 = TtwStamps.CRATERS.get(cause, TtwStamps.CRATERS[&"shell"])
	var scale := size.x / 6.0
	var wet := terrain != null and terrain.water_depth_at(at) > 0.0
	if wet:
		water.splash(at, size.x * 1.5, 0.8, 0.9, size.y)
		water.spray(at, size.x * 5.0)
		debris.throw(TtwDebris.Kind.DROPLET, Vector3(at.x, at.y, 2.0), Vector2.RIGHT, 50.0 * scale, TAU, 90.0 + 20.0 * scale, int(24 * scale))
	else:
		debris.throw(TtwDebris.Kind.CLOD, Vector3(at.x, at.y, 1.0), Vector2.RIGHT, 45.0 * scale, TAU, 80.0 + 15.0 * scale, int(10 * scale))
		for k in int(2 + scale):
			puffs.puff(TtwPuffs.Kind.DUST, at + Vector2.from_angle(TAU * k / (2 + scale)) * size.x * 0.6, Vector2.from_angle(TAU * k / (2 + scale)) * 20.0, 4, scale * 0.8)
	if cause != &"shell":
		debris.throw(TtwDebris.Kind.DEBRIS, Vector3(at.x, at.y, 2.0), Vector2.RIGHT, 40.0 * scale, TAU, 100.0, int(6 * scale))
	puffs.puff(TtwPuffs.Kind.PLUME, at + Vector2(0, -4), Vector2(0, -10), int(6 + 3 * scale), 0.6 + 0.3 * scale, 1.2 if not wet else 0.0)
	# What burns afterwards is the fire field's (TtwGame.explode ignites it).

## A strong wind lifts dust off sand in view.
const SAND_DUST_WIND := 35.0
var _dust_clock: int = 0

func _blow_sand(wind: Vector2) -> void:
	_dust_clock += 1
	if wind.length() < SAND_DUST_WIND or terrain == null or view == null or _dust_clock % 12 != 0:
		return
	var rect := view.view_rect()
	for k in 3:
		var at := rect.position + Vector2(randf(), randf()) * rect.size
		if terrain.material_at(at) == TtwMaterials.SAND and terrain.water_depth_at(at) <= 0.0:
			puffs.puff(TtwPuffs.Kind.DUST, at, wind * 0.4, 3, 1.2)
