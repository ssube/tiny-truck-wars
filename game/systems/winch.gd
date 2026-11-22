class_name TtwWinchSystem extends System
## A wrecker's winch (TtwWinch, linked to its load by TtwWinching): the
## wrecker brakes and drags the load straight towards itself, slower the more
## the ground holds it, burning fuel by the effort. The cable comes off when a
## stuck vehicle is free and can drive, or when an immobile load (a wreck, a
## flooded or dry vehicle) is hauled within tow length.
##
## Runs before the drive, so the wrecker's brake beats its driver's throttle.

signal released(wrecker: Entity, load: Entity)

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwWinch, TtwDrive, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for wrecker in entities:
		var target := session.linked(wrecker, TtwWinching)
		if target != null:
			_pull(wrecker, target, delta)

## Puts the wrecker's cable on `target`. Empty when done; otherwise why not.
static func winch(session: KitSession, wrecker: Entity, target: Entity) -> String:
	var reason := _reach(session, wrecker, target, (wrecker.get_component(TtwWinch) as TtwWinch).range_tiles if wrecker.has_component(TtwWinch) else 0.0)
	if reason.is_empty():
		session.unlink(wrecker, TtwTowing)
		session.link(wrecker, TtwWinching, target)
	return reason

## Hitches `target` behind the wrecker. Empty when done; otherwise why not.
static func tow(session: KitSession, wrecker: Entity, target: Entity) -> String:
	var reason := _reach(session, wrecker, target, (wrecker.get_component(TtwWinch) as TtwWinch).tow_tiles + 1.0 if wrecker.has_component(TtwWinch) else 0.0)
	if reason.is_empty():
		session.unlink(wrecker, TtwWinching)
		session.link(wrecker, TtwTowing, target)
	return reason

## Takes the cable and the hitch off.
static func release(session: KitSession, wrecker: Entity) -> void:
	session.unlink(wrecker, TtwWinching)
	session.unlink(wrecker, TtwTowing)
	if wrecker.has_component(TtwDrive):
		(wrecker.get_component(TtwDrive) as TtwDrive).load = 0.0

static func _reach(session: KitSession, wrecker: Entity, target: Entity, tiles: float) -> String:
	if not wrecker.has_component(TtwWinch):
		return "It has no winch."
	if target == wrecker or target == null or not target.has_component(TtwDrive):
		return "Nothing to hook."
	var a := session.body_of(wrecker)
	var b := session.body_of(target)
	if a == null or b == null:
		return "Nothing to hook."
	if a.position.distance_to(b.position) > tiles * TtwTerrain.tile_px():
		return "Out of reach."
	return ""

## Whether a load cannot move by itself: wrecked, flooded, out of fuel, or
## stalled for good.
static func immobile(entity: Entity) -> bool:
	if entity.has_component(TtwWrecked) or entity.has_component(TtwFlooded):
		return true
	var fuel: TtwFuel = entity.get_component(TtwFuel)
	if fuel != null and fuel.level() <= 0.0:
		return true
	return entity.has_component(TtwStalled) and not TtwDriveSystem.can_restart(entity.get_component(TtwCondition))

func _pull(wrecker: Entity, target: Entity, delta: float) -> void:
	var winch: TtwWinch = wrecker.get_component(TtwWinch)
	var a := session.body_of(wrecker)
	var b := session.body_of(target)
	if a == null or b == null:
		session.unlink(wrecker, TtwWinching)
		return
	var tile := TtwTerrain.tile_px()
	var gap := a.position - b.position
	var dist := gap.length()
	var hauled := dist <= winch.tow_tiles * tile
	if (not target.has_component(TtwStuck) and not immobile(target)) or (hauled and immobile(target)):
		session.unlink(wrecker, TtwWinching)
		released.emit(wrecker, target)
		return
	if dist > winch.range_tiles * tile:
		session.unlink(wrecker, TtwWinching)
		session.notify("The cable will not reach.")
		released.emit(wrecker, target)
		return
	var wd: TtwDrive = wrecker.get_component(TtwDrive)
	wd.throttle = 0.0
	wd.speed = 0.0
	if not TtwDriveSystem.engine_runs(wrecker) or hauled:
		return
	var td: TtwDrive = target.get_component(TtwDrive)
	var terrain := TtwGround.of(session)
	var held := TtwDriveSystem.resistance_at(terrain, b.position, (a.position - b.position).angle()) if terrain != null else td.resistance
	var effort := maxf(1.0, held / winch.force)
	var step := minf(winch.pull_tiles * tile / effort * delta, dist - winch.tow_tiles * tile)
	b.position += gap / dist * step
	td.speed = 0.0
	var fuel: TtwFuel = wrecker.get_component(TtwFuel)
	if fuel != null:
		fuel.amount = maxf(0.0, fuel.level() - winch.fuel_burn * effort * delta)
