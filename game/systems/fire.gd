class_name TtwFireSystem extends System
## Steps the map's fire (TtwFireField) every STEP_TICKS ticks over the burning
## tiles only, hurts what stands in them (trees, buildings, vehicles), scorches
## the ground, and keeps the flames drawn (TtwFx) one per burning tile.

const STEP_TICKS := 6
## Health lost per second at full heat by what stands in a burning tile.
const BURN_DAMAGE := 25.0
## Fuel a wreck, a tree and a building tile give.
const WRECK_FUEL := 25.0
const TREE_FUEL := 18.0
const BUILDING_FUEL := 12.0
## Share of the oil in a burning tile burnt away per second at full heat.
const OIL_BURN := 0.5
## px of snow a fully burning tile melts per second.
const SNOW_MELT := 2.0

var session: KitSession
var fx: TtwFx
## Burning tile -> the flames drawn for it.
var _flames: Dictionary = {}

func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if session.tick % STEP_TICKS != 0:
		return
	for entity in entities:
		var ground: TtwGround = entity.get_component(TtwGround)
		if ground.fire == null or ground.fire.burning.is_empty():
			continue
		var dt := float(STEP_TICKS) / Engine.physics_ticks_per_second
		ground.fire.step(dt, ground.terrain, TtwWeatherSystem.of(session), ground.water)
		_burn_oil(ground, dt)
		_burn(ground.fire, ground.terrain, dt)
		_draw(ground.fire, ground.terrain)

func _burn(field: TtwFireField, terrain: TtwTerrain, dt: float) -> void:
	if field.burning.is_empty():
		return
	for entity in session.view([KitBody]).duplicate():
		if not (entity.has_component(TtwHealth) or entity.has_component(TtwCondition)):
			continue
		var body := session.body_of(entity)
		if body == null:
			continue
		var tile := terrain.tile_of(body.position)
		if field.is_burning(tile):
			TtwDamage.hurt(session, entity, BURN_DAMAGE * field.heat[field.index(tile)] * dt, body.position + Vector2(0, -1))
	for i in field.caught:
		_scorch(terrain, Vector2i(i % field.size.x, i / field.size.x))
	# Fire melts the snow where it burns.
	if terrain.snow_level > 0.0 or _any_snow(terrain):
		for i in field.burning:
			TtwSnow.melt_tile(terrain, Vector2i(i % field.size.x, i / field.size.x), SNOW_MELT * field.heat[i] * dt)

## Oil in burning tiles burns away with the fire (on the ground and afloat).
func _burn_oil(ground: TtwGround, dt: float) -> void:
	var field := ground.fire
	var terrain := ground.terrain
	var n := TtwTerrain.CELLS_PER_TILE
	var oil := terrain.oil
	for i in field.burning:
		var keep := exp(-field.heat[i] * OIL_BURN * dt)
		var tile := Vector2i(i % field.size.x, i / field.size.x)
		for cy in range(tile.y * n, tile.y * n + n):
			for cx in range(tile.x * n, tile.x * n + n):
				var c := cy * terrain.size_cells.x + cx
				if oil[c] > 0.0:
					oil[c] *= keep
		if ground.water != null and ground.water.slick[i] > 0.0:
			var gone := ground.water.slick[i] * (1.0 - keep)
			ground.water.slick[i] -= gone
			ground.water.slick_total -= gone
			ground.water.slick_dirty = true
		terrain.mark_cells(Rect2i(tile * n, Vector2i(n, n)))

func _scorch(terrain: TtwTerrain, tile: Vector2i) -> void:
	var n := TtwTerrain.CELLS_PER_TILE
	for cy in range(tile.y * n, tile.y * n + n):
		for cx in range(tile.x * n, tile.x * n + n):
			var i := cy * terrain.size_cells.x + cx
			terrain.scorch[i] = maxf(terrain.scorch[i], 0.7)
			terrain.queue_settle(i)
	terrain.mark_cells(Rect2i(tile * n, Vector2i(n, n)))

func _draw(field: TtwFireField, terrain: TtwTerrain) -> void:
	if fx == null or fx.air == null:
		return
	for i in field.caught:
		if not _flames.has(i):
			var at := (Vector2(i % field.size.x, i / field.size.x) + Vector2(0.5, 0.7)) * TtwTerrain.tile_px()
			_flames[i] = fx.fire(at, INF, 0.55)
	for i in field.went_out:
		var flame: TtwFire = _flames.get(i)
		if is_instance_valid(flame):
			flame.die_down()
		_flames.erase(i)
	for i in _flames:
		var flame: TtwFire = _flames[i]
		if is_instance_valid(flame):
			flame.strength = field.heat[i]

## Whether any tile has authored snow.
func _any_snow(terrain: TtwTerrain) -> bool:
	return terrain.snow_base.count(0.0) < terrain.snow_base.size()
