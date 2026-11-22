class_name TtwGun extends Component
## A unit's weapon (TtwGunSystem): a tank's cannon (ballistic shells on a
## high arc, which the height field and tall obstacles can stop short) or a
## helicopter's rockets (flatter and faster, from the air). It aims where a
## moving target will be when the shot lands unless `lead` is off.

## What it fires: the crater it leaves (TtwStamps.CRATERS).
@export var ammo: StringName = &"shell"
@export var range_tiles: float = 9.0
@export var reload_seconds: float = 3.0
## Horizontal speed of the shot (tiles per second).
@export var speed_tiles: float = 10.0
## The arc's top over the straight line between muzzle and target, as a share
## of the distance (0: straight).
@export var arc: float = 0.25
## How high the muzzle sits over the ground (px).
@export var muzzle_px: float = 6.0
## Damage at the centre of the burst, falling to 0 at `splash_tiles`.
@export var damage: float = 90.0
@export var splash_tiles: float = 1.5
## Aim ahead of a moving target.
@export var lead: bool = true
## Whether it can shoot at aircraft, and the share of those shots that hit.
@export var hits_air: bool = true
@export_range(0.0, 1.0) var air_accuracy: float = 0.35

## The tick it may fire again.
var ready_tick: int = 0
## Shots fired at aircraft so far (the hit share is kept exactly, not rolled).
var air_shots: int = 0

func range_px() -> float:
	return range_tiles * TtwTerrain.tile_px()

func speed_px() -> float:
	return speed_tiles * TtwTerrain.tile_px()
