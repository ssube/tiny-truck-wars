class_name KitTickSystem extends System
## GECS process() runs per archetype. This query matches exactly one entity, so
## global services execute once per tick even with no other inputs.

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([KitSimulationTick])
