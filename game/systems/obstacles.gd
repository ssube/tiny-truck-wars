class_name TtwObstacleSystem extends System
## Keeps ground vehicles out of trees, logs and buildings. The physics engine
## finds what is near each vehicle (a shape query against the structures
## layer); TtwObstacles does the push. A vehicle that hits one stops; a fast,
## heavy one rams it and hurts it (a tank knocks a tree down). Logs in water
## drift with the current.

## Speed kept when a vehicle runs into something.
const BUMP_KEEP := 0.2
## Health lost per px/s of ramming speed over the obstacle's ram speed.
const RAM_DAMAGE := 2.0
## How much of the current carries a floating log.
const LOG_DRIFT := 0.5

var session: KitSession
var _circle := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()

func query() -> QueryBuilder:
	return q.with_all([TtwVehicle, TtwDrive, KitBody])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var terrain := TtwGround.of(session)
	_drift_logs(terrain, delta)
	for entity in entities:
		var body := (entity.get_component(KitBody) as KitBody).node
		if is_instance_valid(body) and body.is_inside_tree() and not entity.has_component(TtwWrecked):
			_clear(entity, body)

func _clear(entity: Entity, body: Node2D) -> void:
	var v: TtwVehicle = entity.get_component(TtwVehicle)
	var d: TtwDrive = entity.get_component(TtwDrive)
	var radius := v.gauge_px * 0.5 + v.contact_width_px * 0.5
	_circle.radius = radius
	_query.shape = _circle
	_query.transform = Transform2D(0.0, body.position)
	_query.collision_mask = Kit2D.LAYER_STRUCTURES
	var space := body.get_world_2d().direct_space_state
	for hit in space.intersect_shape(_query, 8):
		var other: Node = hit.collider
		var owner := other.get_parent() if other is StaticBody2D else other
		var obstacle_entity := session.entity_for(owner)
		if obstacle_entity == null or not obstacle_entity.has_component(TtwObstacle):
			continue
		var obstacle: TtwObstacle = obstacle_entity.get_component(TtwObstacle)
		var clear := TtwObstacles.push_out(body.position, radius, obstacle, (owner as Node2D).position)
		if clear == body.position:
			continue
		var into := (body.position - clear).normalized()
		var heading := Vector2.from_angle(d.heading) * signf(d.speed)
		var impact := absf(d.speed) * maxf(0.0, heading.dot(into))
		if impact > obstacle.ram_speed and v.sink_px >= obstacle.ram_weight:
			TtwDamage.hurt(session, obstacle_entity, (impact - obstacle.ram_speed) * RAM_DAMAGE * v.sink_px, body.position)
		body.position = clear
		if impact > 0.0:
			d.speed *= BUMP_KEEP

func _drift_logs(terrain: TtwTerrain, delta: float) -> void:
	if terrain == null:
		return
	for entity in session.view([TtwLog, KitBody]):
		var body := (entity.get_component(KitBody) as KitBody).node
		if is_instance_valid(body) and terrain.water_depth_at(body.position) > 1.0:
			var before := terrain.tile_of(body.position)
			body.position += terrain.current_at(body.position) * LOG_DRIFT * delta
			if terrain.tile_of(body.position) != before and body.has_method("block_paths"):
				body.call("block_paths")
