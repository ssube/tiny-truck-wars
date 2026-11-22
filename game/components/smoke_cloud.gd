class_name TtwSmokeCloud extends Component
## A hippy's smoke cloud on an entity of its own (TtwSmokeSystem): ground
## units inside drive slower, and guns cannot pick out anything inside it.
## It drifts with the wind and is gone at `until_tick`.

var center: Vector2
var radius_px: float = 48.0
var until_tick: int = 0
## Speed share left to a ground unit inside.
var slow: float = 0.45
