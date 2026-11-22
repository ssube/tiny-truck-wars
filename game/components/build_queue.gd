class_name TtwBuildQueue extends Component
## What a structure builds (a garage's vehicles, a helipad's helicopters): a
## queue, each unit taking time and fuel from the depot the structure is
## supplied by (TtwGarageSystem).

## The kinds it can build (TtwProduction.UNITS).
@export var builds: Array[StringName] = []

## Unit kinds waiting to be built, the first in progress.
var queue: Array[StringName] = []
var progress: float = 0.0
## The first in the queue is paid for.
var paid: bool = false
## Why the queue is not moving ("" when it is).
var status: String = ""
