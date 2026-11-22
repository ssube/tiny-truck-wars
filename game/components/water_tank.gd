class_name TtwWaterTank extends Component
## The Water tanker kit: it pumps from water near it into its tank, and
## sprays it on a spot in range (TtwSprayOrder) to make mud on purpose or put
## out a fire (TtwKitSystem). Volume is the water's (px of depth × tiles).

@export var capacity: float = 8.0
## Per second, pumping and spraying.
@export var pump_rate: float = 1.0
@export var spray_rate: float = 1.0
@export var spray_tiles: float = 4.0
## Radius of the patch the spray lands on (px).
@export var spray_px: float = 14.0
## How far from it it can reach water to pump (px).
@export var pump_reach_px: float = 24.0

var amount: float = 0.0
