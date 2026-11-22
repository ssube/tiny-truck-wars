class_name TtwFireField extends RefCounted
## Fire on the map, per tile: fuel (what there is to burn) and heat (how hard
## it burns, 0..1). Only burning tiles are stepped (an active list), so a map
## with no fire costs nothing. A burning tile spends its fuel, heats its
## neighbours (faster downwind), and goes out when the fuel is gone or water
## and rain douse it. Fuel comes from what stands there: trees, buildings,
## wrecks, oil.

## Fuel spent per second at full heat; heat gained per second while fuelled.
const BURN := 1.0
const KINDLE := 0.8
## Heat a neighbour soaks up per second from a fully burning tile, and the
## exposure (heat × seconds) at which it catches.
const SPREAD := 0.35
const CATCH := 1.0
## How much a following wind (dot of direction and wind, per px/s) speeds the
## spread, and how much a head wind slows it.
const WIND_SPREAD := 0.03
## Heat lost per second in rain (at full rain), and the water depth (px) or
## soil moisture that puts a tile out at once.
const RAIN_DOUSE := 1.5
const DOUSE_DEPTH := 0.3
const DOUSE_MOISTURE := 0.85
## Fuel under which a tile has nothing left to burn.
const SPENT := 0.05
## Slick on a tile's water over which it burns on the water.
const SLICK_BURNS := 0.2

var size: Vector2i
var fuel: PackedFloat32Array
var heat: PackedFloat32Array
var exposure: PackedFloat32Array
## Burning tiles (indices), and a flag per tile so none is listed twice.
var burning: PackedInt32Array = []
var _listed: PackedByteArray
## Tiles that caught or went out in the last step (for the view).
var caught: PackedInt32Array = []
var went_out: PackedInt32Array = []

func _init(tiles: Vector2i) -> void:
	size = tiles
	var count := tiles.x * tiles.y
	fuel.resize(count)
	heat.resize(count)
	exposure.resize(count)
	_listed.resize(count)

## Takes the state of a saved field (TtwSave): its layers and burning list.
func restore(saved_fuel: PackedFloat32Array, saved_heat: PackedFloat32Array, saved_exposure: PackedFloat32Array, saved_burning: PackedInt32Array) -> void:
	fuel = saved_fuel
	heat = saved_heat
	exposure = saved_exposure
	burning = saved_burning
	_listed.fill(0)
	for i in burning:
		_listed[i] = 1

func index(tile: Vector2i) -> int:
	return tile.y * size.x + tile.x

func has(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y

func add_fuel(tile: Vector2i, amount: float) -> void:
	if has(tile):
		fuel[index(tile)] = maxf(0.0, fuel[index(tile)] + amount)

## Sets a tile alight (if it has anything to burn).
func ignite(tile: Vector2i, start_heat: float = 0.6) -> bool:
	if not has(tile):
		return false
	var i := index(tile)
	if fuel[i] <= SPENT:
		return false
	heat[i] = maxf(heat[i], start_heat)
	if _listed[i] == 0:
		_listed[i] = 1
		burning.append(i)
		caught.append(i)
	return true

func is_burning(tile: Vector2i) -> bool:
	return has(tile) and _listed[index(tile)] == 1

## Puts a tile out.
func douse(tile: Vector2i) -> void:
	if has(tile):
		heat[index(tile)] = 0.0

## One step of `dt` seconds. `terrain` gives water depth; `weather` rain, wind
## and soil moisture (either may be null).
func step(dt: float, terrain: TtwTerrain, weather: TtwWeather, water: TtwWater = null) -> void:
	caught.clear()
	went_out.clear()
	var wind := weather.wind_now if weather != null else Vector2.ZERO
	var rain := weather.rain if weather != null else 0.0
	var soil := weather.soil_moisture if weather != null else 0.0
	var count := burning.size()
	for k in count:
		var i := burning[k]
		var h := heat[i]
		if h <= 0.0:
			continue
		# Water and wet put it out.
		# (Oil burns on water: a slick keeps a wet tile alight.)
		var afloat := water != null and water.slick[i] > SLICK_BURNS
		if soil >= DOUSE_MOISTURE or (not afloat and terrain != null and terrain.water[i] > TtwTerrain.NO_WATER and _depth(terrain, i) >= DOUSE_DEPTH):
			heat[i] = 0.0
			continue
		h = minf(1.0, h + KINDLE * dt) - rain * RAIN_DOUSE * dt
		var spent := BURN * h * dt
		fuel[i] = maxf(0.0, fuel[i] - spent)
		if fuel[i] <= SPENT:
			h = 0.0
		heat[i] = maxf(0.0, h)
		if h <= 0.0:
			continue
		var x := i % size.x
		var y := i / size.x
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := Vector2i(x, y) + offset
			if not has(n):
				continue
			var j := index(n)
			if _listed[j] == 1 or fuel[j] <= SPENT:
				continue
			var downwind := clampf(1.0 + Vector2(offset).dot(wind) * WIND_SPREAD, 0.2, 3.0)
			exposure[j] += h * SPREAD * downwind * dt
			if exposure[j] >= CATCH:
				exposure[j] = 0.0
				ignite(n, 0.3)
	# Drop the tiles that went out.
	var kept := PackedInt32Array()
	for i in burning:
		if heat[i] > 0.0:
			kept.append(i)
		else:
			_listed[i] = 0
			went_out.append(i)
	burning = kept

func _depth(terrain: TtwTerrain, i: int) -> float:
	var tile := Vector2i(i % size.x, i / size.x)
	return terrain.water_depth_at((Vector2(tile) + Vector2(0.5, 0.5)) * TtwTerrain.tile_px())
