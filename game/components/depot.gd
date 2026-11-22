class_name TtwDepot extends Component
## A fuel depot: holds fuel, refills over time, refuels units of its side
## nearby, can be captured while neutral, and explodes when destroyed
## (TtwDepotSystem). Depots near each other refill faster: each other depot of
## the same side within `cluster_tiles` adds `cluster_bonus` to the rate, up
## to `cluster_cap` times it. The neighbours are counted by Area2D overlaps
## (TtwStructure2D), never by polling.

@export var capacity: float = 500.0
@export var start_stock: float = 250.0
## Fuel per second, alone.
@export var refill: float = 1.0
@export var cluster_tiles: float = 6.0
@export var cluster_bonus: float = 0.25
@export var cluster_cap: float = 2.0
## Units within this get fuel at `refuel_rate` per second.
@export var refuel_tiles: float = 3.0
@export var refuel_rate: float = 12.0

var stock: float = -1.0
## Neutral: how long one side has held it uncontested (s).
var capture: float = 0.0
var capture_team: int = 0

func level() -> float:
	return stock if stock >= 0.0 else start_stock

func share() -> float:
	return level() / capacity
