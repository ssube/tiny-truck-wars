class_name TtwGround extends Component
## The map's ground, on the map's entity. Systems that read or change the
## terrain ask for this (session.view([TtwGround])), or call of().

var terrain: TtwTerrain
## The water simulation over it, or null for still, authored water.
var water: TtwWater
## The fire on it, or null.
var fire: TtwFireField
## Where ground vehicles can go (TtwPathSystem makes it once there is ground).
var paths: TtwPathGrid

## The session's ground, or null before a map is loaded.
static func of(session: KitSession) -> TtwTerrain:
	var ground := session.view([TtwGround])
	return ground[0].get_component(TtwGround).terrain if not ground.is_empty() else null

## The session's water simulation, or null.
static func water_of(session: KitSession) -> TtwWater:
	var ground := session.view([TtwGround])
	return ground[0].get_component(TtwGround).water if not ground.is_empty() else null

## The session's fire field, or null.
static func fire_of(session: KitSession) -> TtwFireField:
	var ground := session.view([TtwGround])
	return ground[0].get_component(TtwGround).fire if not ground.is_empty() else null

## The session's path grid, or null.
static func paths_of(session: KitSession) -> TtwPathGrid:
	var ground := session.view([TtwGround])
	return ground[0].get_component(TtwGround).paths if not ground.is_empty() else null
