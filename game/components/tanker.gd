class_name TtwTanker extends Component
## A fuel truck's tank of cargo (the Tanker kit): filled at its side's depots,
## given to its side's units near it, ground or landed (TtwKitSystem).

@export var cargo_capacity: float = 200.0
@export var reach_tiles: float = 2.5
## Fuel per second it gives each unit it serves.
@export var rate: float = 10.0

var cargo: float = -1.0

func level() -> float:
	return cargo if cargo >= 0.0 else cargo_capacity
