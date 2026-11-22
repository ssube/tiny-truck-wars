class_name TtwDamage extends RefCounted
## Hurting things: world objects (TtwHealth) and vehicles (TtwCondition).
## A world object at 0 is destroyed by its body (`destroyed(from)`), falling
## or collapsing away from where the hit came from.

## Hurts one entity by `amount`, from `from` (world px).
static func hurt(session: KitSession, entity: Entity, amount: float, from: Vector2) -> void:
	if entity.has_component(TtwHealth):
		var h: TtwHealth = entity.get_component(TtwHealth)
		if h.destroyed:
			return
		h.health = maxf(0.0, h.current() - amount)
		h.last_hit_from = from
		var body := session.body_of(entity)
		if h.health <= 0.0:
			h.destroyed = true
			if body != null and body.has_method("destroyed"):
				body.call("destroyed", from)
		elif body != null and body.has_method("hurt"):
			body.call("hurt", h.current() / h.max_health)
	elif entity.has_component(TtwCondition):
		var c: TtwCondition = entity.get_component(TtwCondition)
		c.health = maxf(0.0, c.current() - amount)
		if c.health <= 0.0:
			var drive := session.system(&"drive") as TtwDriveSystem
			if drive != null:
				drive.wreck(entity)

## A blast at `at`: everything with health within `radius` is hurt, less with
## distance, from the blast's centre. Aircraft in the air are over it.
static func blast(session: KitSession, at: Vector2, radius: float, damage: float) -> void:
	for entity in session.view([KitBody]).duplicate():
		if not (entity.has_component(TtwHealth) or entity.has_component(TtwCondition)):
			continue
		var body := session.body_of(entity)
		if body == null or TtwCombat.flying(entity):
			continue
		var d := body.position.distance_to(at)
		if d < radius:
			hurt(session, entity, damage * (1.0 - d / radius), at)
