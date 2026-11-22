class_name TtwFlight extends Component
## How an aircraft flies (TtwFlightSystem): it ignores the ground, holds a
## cruise height, and is pushed by the wind, which its pilot steers against.

## Top air speed (tiles per second) and how fast it gets there.
@export var max_speed_tiles: float = 7.0
## The circle a crashed one fills on the ground (px): vehicles go round it.
@export var ground_radius_px: float = 10.0
@export var accel_tiles: float = 5.0
## Height it flies at, and how fast it climbs or sinks (px, px per second).
@export var cruise_px: float = 26.0
@export var climb_px: float = 14.0
## Share of the wind that moves it.
@export var drift: float = 0.6
## Fuel per second in the air, and added at full speed.
@export var hover_burn: float = 0.25
@export var speed_burn: float = 0.25

var heading: float = 0.0
## Its speed through the air, and over the ground (air speed + the wind's push).
var velocity: Vector2 = Vector2.ZERO
var ground_velocity: Vector2 = Vector2.ZERO
var altitude: float = 0.0
## Set each tick by what wants it low (a bucket dipping): the height to hold
## instead of cruise, or < 0 for none. The flight system reads it once.
var hold_px: float = -1.0

func airborne() -> bool:
	return altitude > 0.5
