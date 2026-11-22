class_name TtwHelipad extends Component
## Repairs and refuels its side's helicopters landed on it, from the depot
## it is linked to (TtwSuppliedBy). It can only be placed with a depot of its
## side within `depot_tiles` (TtwPlacement).

@export var depot_tiles: float = 8.0
@export var service_tiles: float = 1.5
@export var refuel_rate: float = 10.0
@export var repair_rate: float = 6.0
