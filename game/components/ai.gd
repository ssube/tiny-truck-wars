class_name TtwAi extends Component
## A computer opponent playing one side (TtwAiSystem), on an entity of its
## own. It builds, expands, takes neutral depots, recovers its stuck units,
## defends its base and attacks in waves that grow after each one fails.

@export var team: int = 2
## How often it thinks (ticks).
@export var think_ticks: int = 30
## Tanks gathered before a wave sets out; one more after each wave is beaten.
@export var attack_size: int = 4
@export var max_attack_size: int = 8
## How near its base (tiles) an enemy makes it defend.
@export var defend_tiles: float = 14.0

var next_tick: int = 0
## Its base (its first garage) and where the army gathers.
var home: Vector2 = Vector2.ZERO
var rally: Vector2 = Vector2.ZERO
var wave: int = 0
var attacking: bool = false
## The structure the wave is after (alias).
var target: String = ""
## A unit sent to take a neutral depot, and the depot (aliases).
var capturer: String = ""
var capture_depot: String = ""
## What its engineer is on its way to build, and where.
var building: StringName = &""
var site: Vector2 = Vector2.ZERO
var build_tries: int = 0
