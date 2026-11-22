class_name TtwMoveOrder extends Component
## Drive to `target` (world px) along a route the path grid finds
## (TtwPilotSystem); removed on arrival.

var target: Vector2 = Vector2.ZERO
## The route (turn points) and the one it is heading for.
var path: PackedVector2Array = PackedVector2Array()
var next: int = 0
## The session tick to plan the route again at (0: plan now).
var replan_tick: int = 0
## Following a target it was ordered to attack (TtwGunSystem stops it in range).
var chase: bool = false
## Progress checks (TtwPilotSystem): where it was and which way it faced at
## the last check, when the next is, the times it has backed off, and the
## backing off going on (until a tick, steering one way).
var check_tick: int = 0
var check_at: Vector2 = Vector2.ZERO
var check_heading: float = 0.0
var tries: int = 0
var reverse_until: int = 0
var reverse_steer: float = 0.0
