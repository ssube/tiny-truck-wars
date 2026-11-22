class_name TtwSnowSystem extends System
## The snow's weather: snowfall raises the map-wide snow level, warmth, sun
## and rain thaw it, both as one number per tick (no cell is touched).
## Every RUNOFF_TICKS the thaw is booked tile by tile: what melted off a tile
## with ruts or a crater in it runs into them as water (TtwWater); the rest
## soaks the soil (TtwWeather.soil_moisture). Shaders read the level as
## ttw_snow and how slushy it is as ttw_thaw.

## px of snow per second at full snowfall; thawed per second per °C over 0
## (more in sun), and by rain.
const FALL_RATE := 0.02
const THAW_PER_DEGREE := 0.004
const RAIN_THAW := 0.01
## Share of a tile's melt that runs into its ruts when it has any (its
## lowest cell this far below its mean), and how much soil moisture the rest
## adds per px melted over the whole map.
const RUNOFF_SHARE := 0.6
const RUT_DEPTH := 1.0
const SOAK := 0.15
const RUNOFF_TICKS := 120

var session: KitSession
## Melt, booked: all of it, what ran off into water, what soaked in.
var melted: float = 0.0
var ran_off: float = 0.0
var soaked: float = 0.0
var _booked_level: float = 0.0
var _snow_max: float = -1.0

func query() -> QueryBuilder:
	return q.with_all([TtwGround, TtwWeather])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var g: TtwGround = entity.get_component(TtwGround)
		var w: TtwWeather = entity.get_component(TtwWeather)
		if g.terrain == null:
			continue
		var t := g.terrain
		if _snow_max < 0.0 or session.tick % 600 == 0:
			_snow_max = 0.0
			for v in t.snow_base:
				_snow_max = maxf(_snow_max, v)
		if _snow_max <= 0.0 and t.snow_level <= 0.0 and w.snowfall <= 0.0:
			continue
		var thaw := thaw_rate(w)
		t.snow_level = maxf(-_snow_max, t.snow_level + (w.snowfall * FALL_RATE - thaw) * delta)
		RenderingServer.global_shader_parameter_set(&"ttw_snow", t.snow_level)
		RenderingServer.global_shader_parameter_set(&"ttw_thaw", clampf(thaw / 0.03, 0.0, 1.0))
		if session.tick % RUNOFF_TICKS == 0:
			_book(t, g.water, w)

## px of snow thawed per second in this weather.
static func thaw_rate(w: TtwWeather) -> float:
	return maxf(0.0, w.temperature) * THAW_PER_DEGREE * (0.4 + w.sun) + w.rain * RAIN_THAW * float(w.temperature > 0.0)

## Books the thaw since last time tile by tile: runoff into rutted tiles'
## water, the rest into the soil.
func _book(t: TtwTerrain, water: TtwWater, w: TtwWeather) -> void:
	var before := _booked_level
	var after := t.snow_level
	_booked_level = after
	if after >= before:
		return
	var melt_total := 0.0
	var tiles := t.size_tiles.x * t.size_tiles.y
	for i in tiles:
		var base := t.snow_base[i]
		var had := maxf(0.0, base + before)
		if had <= 0.0:
			continue
		var melt := had - maxf(0.0, base + after)
		if melt <= 0.0:
			continue
		melt_total += melt
		if water != null and water.floor_min[i] < water.floor_mean[i] - RUT_DEPTH:
			var run := melt * RUNOFF_SHARE
			water.add_volume(i, run)
			ran_off += run
			soaked += melt - run
		else:
			soaked += melt
	melted += melt_total
	w.soil_moisture = clampf(w.soil_moisture + (melt_total - 0.0) / tiles * SOAK * 10.0, 0.0, 1.0)

## (Tests and tools: the level the books start from.)
func reset_books(level: float) -> void:
	_booked_level = level
	melted = 0.0
	ran_off = 0.0
	soaked = 0.0
