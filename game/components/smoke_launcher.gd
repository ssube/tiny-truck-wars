class_name TtwSmokeLauncher extends Component
## The hippy's smoke: thrown on a spot within reach, it makes a cloud that
## slows ground units inside and hides them from guns (TtwSpecialSystem).

@export var cooldown_seconds: float = 25.0
@export var throw_tiles: float = 4.0
@export var radius_tiles: float = 3.0
@export var seconds: float = 12.0
## Speed share left to a ground unit inside.
@export var slow: float = 0.45

## The tick it can throw again.
var ready_tick: int = 0
