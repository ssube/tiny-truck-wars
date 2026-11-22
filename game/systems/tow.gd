class_name TtwTowSystem extends System
## Towing (TtwTowing from a wrecker to its load): after the drive has moved
## the wrecker, the load follows on a rope of tow length, turned to face it.
## What the load's ground holds is added to the wrecker's own resistance
## (TtwDrive.load), so towing through mud is slow and can get both stuck.

## Share of the load's resistance the wrecker feels.
const LOAD_SHARE := 0.5

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwWinch, TtwDrive, KitBody])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var terrain := TtwGround.of(session)
	for wrecker in entities:
		var wd: TtwDrive = wrecker.get_component(TtwDrive)
		var target := session.linked(wrecker, TtwTowing)
		if target == null:
			wd.load = 0.0
			continue
		var a := session.body_of(wrecker)
		var b := session.body_of(target)
		if a == null or b == null:
			session.unlink(wrecker, TtwTowing)
			wd.load = 0.0
			continue
		var rope := (wrecker.get_component(TtwWinch) as TtwWinch).tow_tiles * TtwTerrain.tile_px()
		var gap := b.position - a.position
		var td: TtwDrive = target.get_component(TtwDrive)
		if gap.length() > rope:
			b.position = a.position + gap.normalized() * rope
		td.heading = (a.position - b.position).angle()
		td.speed = 0.0
		if terrain != null:
			wd.load = TtwDriveSystem.resistance_at(terrain, b.position, td.heading) * LOAD_SHARE
