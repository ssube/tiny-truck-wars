class_name TtwCondition extends Component
## A vehicle's health (its wear). At 0 it is destroyed.

@export var max_health: float = 100.0
## Health lost per second per px of water over the wading depth, squared-ish:
## see TtwDriveSystem.water_wear.
@export var water_wear: float = 0.6

var health: float = -1.0

func current() -> float:
	return health if health >= 0.0 else max_health

func share() -> float:
	return current() / max_health
