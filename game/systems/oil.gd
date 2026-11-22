class_name TtwOilSystem extends System
## Oil coming out of vehicles: wrecks bleed (TtwLeak) until they run dry, and
## a vehicle worn under DRIP_HEALTH drips as it goes. Every spill also gives
## the fire field fuel where it lands.

const DRIP_HEALTH := 0.3
const DRIP_EVERY := 30
const DRIP := 0.05
## Bleeds in steps this many ticks apart.
const BLEED_EVERY := 15

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([KitBody])

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	var ground := session.view([TtwGround])
	if ground.is_empty():
		return
	var g: TtwGround = ground[0].get_component(TtwGround)
	if g.terrain == null:
		return
	if session.tick % BLEED_EVERY == 0:
		var dt := float(BLEED_EVERY) / Engine.physics_ticks_per_second
		for entity in session.view([TtwLeak, KitBody]):
			var leak: TtwLeak = entity.get_component(TtwLeak)
			var body := session.body_of(entity)
			if leak.left <= 0.0 or body == null:
				continue
			var amount := minf(leak.left, leak.rate * dt)
			leak.left -= amount
			spill(g, body.position, amount, 6.0)
	if session.tick % DRIP_EVERY == 0:
		for entity in session.view([TtwCondition, KitBody]):
			var c: TtwCondition = entity.get_component(TtwCondition)
			var body := session.body_of(entity)
			if body != null and c.share() < DRIP_HEALTH and not entity.has_component(TtwWrecked):
				spill(g, body.position, DRIP, 2.0)

## Spills oil and fuels the fire where it lands.
static func spill(g: TtwGround, at: Vector2, amount: float, radius_px: float) -> void:
	var fuel := TtwOil.spill(g.terrain, g.water, at, amount, radius_px)
	if g.fire != null:
		for tile_index in fuel:
			g.fire.add_fuel(Vector2i(tile_index % g.terrain.size_tiles.x, tile_index / g.terrain.size_tiles.x), fuel[tile_index])
