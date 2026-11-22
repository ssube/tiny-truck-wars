class_name TtwWeather extends Component
## The map's weather, on the map's entity. Authored per map; the Mud Lab has
## sliders for it. TtwWeatherSystem keeps the derived values.

## Air temperature (°C): snow thaws above 0.
@export var temperature: float = 8.0
## How much sun reaches the ground (0 overcast .. 1 clear).
@export_range(0.0, 1.0) var sun: float = 0.5
## The steady wind (px per second, the direction it blows toward).
@export var wind: Vector2 = Vector2(18.0, 4.0)
## Rain and snowfall (0 none .. 1 heavy).
@export_range(0.0, 1.0) var rain: float = 0.0
@export_range(0.0, 1.0) var snowfall: float = 0.0

## The wind now: the steady wind times the gust (px/s).
var wind_now: Vector2 = Vector2.ZERO
## How wet the ground is everywhere from the weather (0..1): rain raises it,
## sun and warmth dry it. A global term: no cell is written for it.
var soil_moisture: float = 0.0
