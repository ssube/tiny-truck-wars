class_name TtwVehicle extends Component
## A ground vehicle's build and what it is carrying of the ground. Authored per
## kind on its prefab (copied per instance).

enum Running { TREADS, WHEELS }

@export var kind: StringName = &""
@export var running: Running = Running.WHEELS
## How far (px) one press of a contact sinks into fully soft ground.
@export var sink_px: float = 1.2
## Treads: length of each tread, distance between the two tread centres.
## Wheels: distance between the left and right wheels.
@export var tread_length_px: float = 0.0
@export var gauge_px: float = 14.0
## Width of a tread or tyre.
@export var contact_width_px: float = 4.0
## Wheels: each axle's offset (px) from the centre along the heading, front first.
@export var axles_px: PackedFloat32Array = PackedFloat32Array([10.0, -10.0])
## Water deeper than this (px) wears the vehicle; at flood_depth_px it floods the engine.
@export var wading_depth_px: float = 3.0
@export var flood_depth_px: float = 9.0

## Mud stuck to the vehicle (px³-like units of loose mud), dropped as it drives.
var carried_mud: float = 0.0
## Oil on its tyres or treads, smeared as it drives (TtwOil.smear).
var carried_oil: float = 0.0
## How caked in mud the hull looks (0..1).
var grime: float = 0.0
## How far (px) the hull sits sunk in ruts and water, for drawing.
var sink: float = 0.0
## How deep the water it stands in is (px).
var water_depth: float = 0.0
## How wet its hull is (0..1): 1 in water, drying after.
var hull_wet: float = 0.0
## The cell each contact last pressed, and where it was (contacts in order:
## treads left, right; or each axle's left, right).
var last_cells: PackedInt32Array = PackedInt32Array()
var last_points: PackedVector2Array = PackedVector2Array()

## Where each contact is now (world px), at the leading end of a tread.
func contacts(center: Vector2, heading: float) -> PackedVector2Array:
	var along := Vector2.from_angle(heading)
	var side := along.orthogonal()
	var points := PackedVector2Array()
	if running == Running.TREADS:
		var front := along * tread_length_px * 0.5
		points.append(center + front - side * gauge_px * 0.5)
		points.append(center + front + side * gauge_px * 0.5)
	else:
		for offset in axles_px:
			points.append(center + along * offset - side * gauge_px * 0.5)
			points.append(center + along * offset + side * gauge_px * 0.5)
	return points
