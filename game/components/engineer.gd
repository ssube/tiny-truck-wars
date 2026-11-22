class_name TtwEngineer extends Component
## The Engineer kit: structures can only be put down near one, and while
## `paving` it lays gravel road where it drives, filling the ruts (TtwKitSystem).

## How near a building site an engineer must be (tiles).
@export var build_tiles: float = 5.0
## Fuel each tile of road costs it.
@export var pave_fuel: float = 0.6

var paving: bool = false
## The tile it last paved (index), so each is paid for once.
var last_tile: int = -1
