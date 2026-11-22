class_name TtwHealth extends Component
## A world object's health (trees, logs, buildings). At 0 it is destroyed,
## falling or collapsing away from `last_hit_from`.

@export var max_health: float = 100.0

var health: float = -1.0
## Where the hit that hurt it most recently came from (world px).
var last_hit_from: Vector2 = Vector2.ZERO
var destroyed: bool = false

func current() -> float:
	return health if health >= 0.0 else max_health
