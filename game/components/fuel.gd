class_name TtwFuel extends Component
## A vehicle's tank. Burned by effort (TtwDriveSystem); empty, it cannot drive.

@export var capacity: float = 100.0
## Per second with the engine running and the vehicle standing.
@export var idle_burn: float = 0.05
## Per second at full throttle on paved level ground; scaled by resistance and grade.
@export var drive_burn: float = 0.4

var amount: float = -1.0

func level() -> float:
	return amount if amount >= 0.0 else capacity
