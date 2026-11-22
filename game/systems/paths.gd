class_name TtwPathSystem extends System
## Keeps the path grid current: makes it when there is ground, then weighs the
## tiles the terrain queued and a stretch of the sweep each tick.

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var ground: TtwGround = entity.get_component(TtwGround)
		if ground.terrain == null:
			continue
		if ground.paths == null or ground.paths.terrain != ground.terrain:
			ground.paths = TtwPathGrid.new(ground.terrain)
			# What already stands on the map.
			for obstacle in session.view([TtwObstacle, KitBody]):
				var body := session.body_of(obstacle)
				if body != null and body.has_method("block_paths"):
					body.call("block_paths")
		else:
			ground.paths.step()
