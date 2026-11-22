class_name TtwObstacle extends Component
## A shape ground vehicles cannot drive through: a circle (a tree trunk) or an
## oriented box (a log, a building). TtwObstacleSystem pushes vehicles out.

enum Shape { CIRCLE, BOX }

@export var shape: Shape = Shape.CIRCLE
@export var radius: float = 4.0
@export var half_extents: Vector2 = Vector2(8.0, 8.0)
## A vehicle at least this fast (px/s) and this heavy (sink px) hitting it does
## damage (ramming); below either, it just stops.
@export var ram_speed: float = 30.0
@export var ram_weight: float = 1.2

## How tall it stands (px): a shot passing lower than this over it hits it.
@export var height_px: float = 12.0

## Where the shape's centre is from its body's origin (before rotation).
@export var offset: Vector2 = Vector2.ZERO

## The box's rotation (radians), kept by its body.
var angle: float = 0.0
