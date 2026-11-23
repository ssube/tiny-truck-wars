class_name TtwUnits extends RefCounted
## Putting units on the map: the chassis scene for a kind and the kit it is
## fitted with (TtwProduction), its side, and its marker (TtwUnit). The game,
## its garages and tests all spawn through here.

const SCENES := {
	&"tank": "res://prefabs/unit/tank.tscn",
	&"truck": "res://prefabs/unit/truck.tscn",
	&"hippy": "res://prefabs/unit/hippy.tscn",
	&"boss": "res://prefabs/unit/boss.tscn",
	&"nurse": "res://prefabs/unit/nurse.tscn",
	&"helicopter": "res://prefabs/unit/helicopter.tscn",
}

## Whether `kind` names something that can be spawned (a chassis or a kit).
static func knows(kind: StringName) -> bool:
	return SCENES.has(TtwProduction.chassis(kind))

## A unit of `kind` (a chassis, or a kit on one) for `team` at `at` under
## `parent`, bound as `identity`. Null, with session.last_error, if not.
static func spawn(session: KitSession, parent: Node, kind: StringName, at: Vector2, heading: float, team: int, identity: String) -> Entity:
	var chassis := TtwProduction.chassis(kind)
	if not SCENES.has(chassis):
		session.last_error = "No unit kind %s." % kind
		return null
	var body: Node2D = (load(SCENES[chassis]) as PackedScene).instantiate()
	body.position = at
	dress(body, kind)
	parent.add_child(body)
	var side := TtwTeam.new()
	side.team = team
	var marker := TtwUnit.new()
	marker.kind = kind
	var extra: Array[Component] = [side, marker]
	extra.append_array(TtwKits.parts(TtwProduction.kit(kind)))
	var entity := session.bind_body(body, identity, extra)
	if entity == null:
		body.queue_free()
		return null
	var drive: TtwDrive = entity.get_component(TtwDrive)
	if drive != null:
		drive.heading = heading
	var flight: TtwFlight = entity.get_component(TtwFlight)
	if flight != null:
		flight.heading = heading
	return entity

## Gives a unit's body the art of its kind, if the kind has its own
## (TtwProduction.art): before it is in the tree, or after (a loaded save,
## whose kind is known only once its components are back).
static func dress(body: Node, kind: StringName) -> void:
	var art := TtwProduction.art(kind)
	if not art.is_empty() and "art" in body:
		body.set("art", art)
	if TtwProduction.beacon(kind) and "beacon" in body:
		body.set("beacon", true)

## The kind a unit was built as (TtwUnit), or its chassis.
static func kind_of(entity: Entity) -> StringName:
	var u: TtwUnit = entity.get_component(TtwUnit)
	if u != null and not u.kind.is_empty():
		return u.kind
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	return v.kind if v != null else &""
