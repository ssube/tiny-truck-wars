class_name TtwObstacles extends RefCounted
## Pushing a vehicle (a circle) out of an obstacle's shape: exact geometry for
## circles and oriented boxes. The physics engine only finds which obstacles
## are near (TtwObstacleSystem's broadphase).

## Where a circle at `center` of `radius` must move to be clear of `obstacle`
## standing at `at`; `center` itself when already clear.
static func push_out(center: Vector2, radius: float, obstacle: TtwObstacle, at: Vector2) -> Vector2:
	at += obstacle.offset.rotated(obstacle.angle)
	if obstacle.shape == TtwObstacle.Shape.CIRCLE:
		var d := center - at
		var reach := radius + obstacle.radius
		if d.length_squared() >= reach * reach:
			return center
		var away := d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
		return at + away * reach
	var local := (center - at).rotated(-obstacle.angle)
	var h := obstacle.half_extents
	var closest := local.clamp(-h, h)
	var diff := local - closest
	if diff.length_squared() >= radius * radius:
		return center
	if diff.length_squared() < 0.0001:
		# The centre is inside the box: out through the nearest side.
		var gaps := [h.x - local.x, h.x + local.x, h.y - local.y, h.y + local.y]
		var side := gaps.find(gaps.min())
		match side:
			0: local.x = h.x + radius
			1: local.x = -h.x - radius
			2: local.y = h.y + radius
			_: local.y = -h.y - radius
	else:
		local = closest + diff.normalized() * radius
	return at + local.rotated(obstacle.angle)
