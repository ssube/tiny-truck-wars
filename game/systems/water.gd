class_name TtwWaterSystem extends System
## Steps the map's water (TtwWater) every STEP_TICKS ticks over the whole wet
## area: no LOD, it flows the same wherever the camera is.

var session: KitSession
var _ticks: int = 0

func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	_ticks += 1
	if _ticks % TtwWater.STEP_TICKS != 0:
		return
	var dt := float(TtwWater.STEP_TICKS) / Engine.physics_ticks_per_second
	for entity in entities:
		var water: TtwWater = entity.get_component(TtwGround).water
		if water != null:
			water.step(dt)
