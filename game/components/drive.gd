class_name TtwDrive extends Component
## How a vehicle is being driven and how it moves. The driver (player orders,
## AI, the Mud Lab's keys) sets throttle and steer; TtwDriveSystem does the rest.

## Top speed on paved, level, dry ground (tiles per second).
@export var max_speed_tiles: float = 4.0
## Tiles per second gained per second of full throttle.
@export var accel_tiles: float = 3.0
## Turn rate at full steer (radians per second).
@export var turn_rate: float = 1.6
## Resistance it can push through before it is stuck (TtwDriveSystem).
@export var traction: float = 6.0

var throttle: float = 0.0
var steer: float = 0.0
var heading: float = 0.0
## Signed speed along the heading (px per second).
var speed: float = 0.0
## Resistance under it last tick (1 = paved road), and the grade along the heading.
var resistance: float = 1.0
var grade: float = 0.0
## Grip left on the oil under it (1 = none lost; TtwOil.grip).
var grip: float = 1.0
## Resistance added by what it tows (TtwTowSystem).
var load: float = 0.0

## The traction it has now: less on oil.
func grip_traction() -> float:
	return traction * grip

## Fills under strain; at 1 the engine stalls (TtwDriveSystem).
var stall_meter: float = 0.0
