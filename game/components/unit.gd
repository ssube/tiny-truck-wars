class_name TtwUnit extends Component
## A unit the sides command: a ground vehicle or an aircraft. `kind` is what
## a garage or helipad built (TtwProduction: tank, wrecker, helicopter...);
## the chassis it is built on is the body's (TtwVehicle.kind for ground ones).

@export var kind: StringName = &""
