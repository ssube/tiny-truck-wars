class_name TtwWinchSystem extends System
## A wrecker's winch (TtwWinch, linked to its load by TtwWinching): the
## wrecker brakes and drags the load straight towards itself, slower the more
## the ground holds it, burning fuel by the effort. The cable comes off when a
## stuck vehicle is free and can drive, or when an immobile load (a wreck, a
## flooded or dry vehicle) is hauled within tow length.
##
## The cable can go round an anchor instead (a tree, a log, a house: a world
## object standing in the way): then the winch hauls the wrecker itself to
## the anchor, through whatever holds it, and lets go when it gets there or
## the anchor falls.
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

## Puts the wrecker's cable round `anchor` (a tree, a log, a house), to haul
## itself there. Empty when done; otherwise why not.
static func anchor(session: KitSession, wrecker: Entity, anchor_at: Entity) -> String:
	if not wrecker.has_component(TtwWinch):
		return "It has no winch."
	if not _holds_fast(anchor_at):
		return "Nothing to hook."
	var a := session.body_of(wrecker)
	var b := session.body_of(anchor_at)
	if a == null or b == null:
		return "Nothing to hook."
	if a.position.distance_to(b.position) > (wrecker.get_component(TtwWinch) as TtwWinch).range_tiles * TtwTerrain.tile_px():
		return "Out of reach."
	session.unlink(wrecker, TtwTowing)
	session.link(wrecker, TtwWinching, anchor_at)
	return ""

## Whether `entity` can take a cable round it: a world object standing in
## the way (TtwObstacle) that is not a vehicle and not destroyed.
static func _holds_fast(entity: Entity) -> bool:
	if entity == null or entity.has_component(TtwDrive) or not entity.has_component(TtwObstacle):
		return false
	var h: TtwHealth = entity.get_component(TtwHealth)
	return h == null or not h.destroyed

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

## How far behind its wrecker a load rides on the tow rope (px): the rope's
## length, or the two side by side if that is longer (so the load is never
## pulled into the wrecker and shoved back out, which would walk them both).
static func rope_px(wrecker: Entity, load: Entity) -> float:
	var rope := (wrecker.get_component(TtwWinch) as TtwWinch).tow_tiles * TtwTerrain.tile_px()
	var a: TtwVehicle = wrecker.get_component(TtwVehicle)
	var b: TtwVehicle = load.get_component(TtwVehicle)
	if a != null and b != null:
		rope = maxf(rope, TtwSeparationSystem.radius_of(a) + TtwSeparationSystem.radius_of(b) + 1.0)
	return rope

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
	if not target.has_component(TtwDrive):
		_haul_self(wrecker, winch, a, target, b, delta)
		return
	var tile := TtwTerrain.tile_px()
	var gap := a.position - b.position
	var dist := gap.length()
	var hauled := dist <= rope_px(wrecker, target)
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
	var step := minf(winch.pull_tiles * tile / effort * delta, dist - rope_px(wrecker, target))
	b.position += gap / dist * step
	td.speed = 0.0
	var fuel: TtwFuel = wrecker.get_component(TtwFuel)
	if fuel != null:
		fuel.amount = maxf(0.0, fuel.level() - winch.fuel_burn * effort * delta)

## The wrecker hauls itself towards `anchor` (body `b`): through what holds it
## (its own ground), at the winch's pace, burning fuel by the effort; the
## cable comes off when it is up against the anchor or the anchor is gone.
func _haul_self(wrecker: Entity, winch: TtwWinch, a: Node2D, anchor_at: Entity, b: Node2D, delta: float) -> void:
	if not _holds_fast(anchor_at):
		session.unlink(wrecker, TtwWinching)
		released.emit(wrecker, anchor_at)
		return
	var o: TtwObstacle = anchor_at.get_component(TtwObstacle)
	var post := b.position + o.offset.rotated(o.angle)
	var gap := post - a.position
	var dist := gap.length()
	if dist > winch.range_tiles * TtwTerrain.tile_px():
		session.unlink(wrecker, TtwWinching)
		session.notify("The cable will not reach.")
		released.emit(wrecker, anchor_at)
		return
	var wd: TtwDrive = wrecker.get_component(TtwDrive)
	wd.throttle = 0.0
	wd.speed = 0.0
	var radius := TtwSeparationSystem.radius_of(wrecker.get_component(TtwVehicle)) + 1.0
	# Up against it (the haul stops it at `radius`; half a px of slack).
	var there := TtwObstacles.push_out(a.position, radius + 0.5, o, b.position) != a.position
	if there or dist < 0.001:
		session.unlink(wrecker, TtwWinching)
		released.emit(wrecker, anchor_at)
		return
	if not TtwDriveSystem.engine_runs(wrecker):
		return
	# The winch is on the front: it turns to the cable as it is hauled.
	wd.heading = gap.angle()
	var terrain := TtwGround.of(session)
	var held := TtwDriveSystem.resistance_at(terrain, a.position, wd.heading) if terrain != null else wd.resistance
	var effort := maxf(1.0, held / winch.force)
	var step := minf(winch.pull_tiles * TtwTerrain.tile_px() / effort * delta, dist)
	var next := a.position + gap / dist * step
	# No further than up against the anchor.
	a.position = TtwObstacles.push_out(next, radius, o, b.position)
	var fuel: TtwFuel = wrecker.get_component(TtwFuel)
	if fuel != null:
		fuel.amount = maxf(0.0, fuel.level() - winch.fuel_burn * effort * delta)
