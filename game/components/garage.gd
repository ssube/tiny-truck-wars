class_name TtwGarage extends Component
## Repairs its side's ground vehicles nearby; wrecks towed in are broken up
## for fuel (TtwGarageSystem). What it builds is its TtwBuildQueue.

@export var repair_tiles: float = 3.0
## Health per second, and fuel per health repaired.
@export var repair_rate: float = 6.0
@export var repair_fuel: float = 0.1
