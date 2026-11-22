class_name TtwShell extends Component
## A shot in flight, on an entity of its own with no body (TtwBallisticsSystem).
## Its path is fixed when fired: a straight line over the ground from `from`
## to `to`, at a height that runs from the muzzle to the end height plus an
## arc. The ground and tall obstacles under the path can stop it short.

var from: Vector2
var to: Vector2
## Absolute heights (px, the ground's elevation + relief scale) at the start
## and the end, and the arc's top over the line between them.
var from_h: float = 0.0
var to_h: float = 0.0
var apex: float = 0.0
var fired_tick: int = 0
var flight_ticks: int = 1
var damage: float = 0.0
var splash_px: float = 24.0
var ammo: StringName = &"shell"
var team: int = 0
## Aimed at an aircraft: bursts in the air at the end, hurting it if `hit`.
var air: bool = false
var hit: bool = false
## Where it has got to (the share of the flight checked so far).
var done: float = 0.0

## Where the shot is at share `t` of its flight: x, y over the ground and its height.
func at(t: float) -> Vector3:
	var p := from.lerp(to, t)
	return Vector3(p.x, p.y, lerpf(from_h, to_h, t) + 4.0 * apex * t * (1.0 - t))
