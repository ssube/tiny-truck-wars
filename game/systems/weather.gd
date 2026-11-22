class_name TtwWeatherSystem extends System
## The weather each tick: the gusting wind (a gust of three beats
## that never line up, on the session tick, never wall time) and the ground's
## moisture from rain against sun and warmth. Shaders read the wind through
## the globals ttw_wind and ttw_wind_clock, and the moisture through ttw_soil.

## Soil moisture gained per second at full rain, and lost per second at full
## sun and 20 °C (less when cooler or overcast).
const WETTING := 1.0 / 40.0
const DRYING := 1.0 / 300.0

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwWeather])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var w: TtwWeather = entity.get_component(TtwWeather)
		var clock := clock_at(session.tick)
		w.wind_now = w.wind * gust(clock, 0.0)
		w.soil_moisture = moisture_after(w, w.soil_moisture, delta)
		RenderingServer.global_shader_parameter_set(&"ttw_wind", w.wind)
		RenderingServer.global_shader_parameter_set(&"ttw_wind_clock", clock)
		RenderingServer.global_shader_parameter_set(&"ttw_soil", w.soil_moisture)

## Seconds of game clock at `tick`.
static func clock_at(tick: int) -> float:
	return tick / float(Engine.physics_ticks_per_second)

## The gust (0.15 to 1.2). shaders/wind_sway.gdshader repeats it.
static func gust(clock: float, phase: float) -> float:
	return clampf(0.62 + 0.24 * sin(clock * 0.31 + phase) + 0.17 * sin(clock * 0.83 + phase * 2.3) + 0.11 * sin(clock * 1.9 + phase * 0.7), 0.15, 1.2)

## The wind at `tick` for something with `phase` (px/s).
static func wind_at(weather: TtwWeather, tick: int, phase: float) -> Vector2:
	return weather.wind * gust(clock_at(tick), phase)

## The soil moisture after `delta` seconds of this weather.
static func moisture_after(w: TtwWeather, moisture: float, delta: float) -> float:
	var warmth := clampf(w.temperature / 20.0, 0.0, 1.5)
	var drying := DRYING * (0.3 + w.sun) * (0.2 + warmth)
	return clampf(moisture + (w.rain * WETTING - drying * (1.0 - w.rain)) * delta, 0.0, 1.0)

## The session's weather, or null.
static func of(session: KitSession) -> TtwWeather:
	var found := session.view([TtwWeather])
	return found[0].get_component(TtwWeather) if not found.is_empty() else null
