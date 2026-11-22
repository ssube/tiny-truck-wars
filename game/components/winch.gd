class_name TtwWinch extends Component
## A winch and tow hitch (the Wrecker's kit). It drags a linked vehicle or
## wreck towards itself (TtwWinching) or tows one behind it (TtwTowing):
## TtwWinchSystem, TtwTowSystem.

## How far the cable reaches (tiles).
@export var range_tiles: float = 5.0
## Pull speed on firm ground (tiles per second); slower through what holds it.
@export var pull_tiles: float = 0.6
## Resistance the pull goes through at full speed; past it, slower in step.
@export var force: float = 4.0
## Tow rope length (tiles); a winch hauls an immobile load up to this.
@export var tow_tiles: float = 1.5
## Fuel per second while winching, times how hard it pulls.
@export var fuel_burn: float = 0.5
