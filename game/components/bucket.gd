class_name TtwBucket extends Component
## A helicopter's water bucket: it dips low over water to fill, and drops it
## all at once on a spot (TtwDropOrder) (TtwKitSystem). A volume unit is
## 1 px of depth over a whole tile: a few go a long way on flat ground.

@export var capacity: float = 4.0
## Per second while dipped.
@export var fill_rate: float = 2.0
## Height it hovers at to fill (px), and the radius the drop lands on.
@export var dip_px: float = 5.0
@export var drop_px: float = 22.0
## Water under it at least this deep (px) to dip in.
@export var min_depth_px: float = 2.0

var amount: float = 0.0
