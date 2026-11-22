class_name TtwTrackSystem extends System
## Presses each ground vehicle's treads or wheels into the ground: once per
## contact per cell it enters, as a patch from where it last pressed to where
## it is now (so a fast vehicle leaves no gaps and a standing one digs nothing
## more). Keeps the hull's grime and how deep it sits, for drawing.

## A contact that jumped further than this (px) was moved, not driven: no rut.
const MAX_PATCH_PX := 24.0
## Spinning in place: past this slip and under this speed (px/s), every
## DIG_EVERY ticks the contacts press again at DIG_SHARE of the sink.
const DIG_SLIP := 0.6
const DIG_SPEED := 4.0
const DIG_EVERY := 20
const DIG_SHARE := 0.5
## Seconds a hull takes to dry after leaving water.
const HULL_DRY_SECONDS := 20.0

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwVehicle, TtwDrive, KitBody]).iterate([TtwVehicle, TtwDrive, KitBody])

func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	# The matches' components, in step with `entities` (nothing here adds or
	# removes a component, so they stay in step).
	var vehicles: Array = components[0]
	var drives: Array = components[1]
	var bodies: Array = components[2]
	for k in entities.size():
		var entity := entities[k]
		if not entity.has_component(TtwWrecked):
			press(entity, vehicles[k], drives[k], (bodies[k] as KitBody).node, terrain, delta)

func press(entity: Entity, v: TtwVehicle, d: TtwDrive, body: Node2D, terrain: TtwTerrain, delta: float) -> void:
	if not is_instance_valid(body):
		return
	var position := body.position
	var cell_px := terrain.cell_size_px
	var size := terrain.size_cells
	var points := v.contacts(position, d.heading)
	if v.last_cells.size() != points.size():
		v.last_cells.resize(points.size())
		v.last_points = points.duplicate()
		for k in points.size():
			v.last_cells[k] = terrain.cell_index(terrain.cell_of(points[k]).clamp(Vector2i.ZERO, size - Vector2i.ONE))
		return
	var slip := clampf(d.resistance / maxf(d.grip_traction(), 0.1), 0.0, 1.0) * absf(d.throttle)
	# Spinning in place digs in: it presses its contacts again, deeper the more
	# it slips, so a vehicle stuck and still flooring it sinks itself.
	if slip > DIG_SLIP and absf(d.speed) < DIG_SPEED and TtwDriveSystem.engine_runs(entity) and session.tick % DIG_EVERY == 0:
		for point in points:
			v.carried_mud = TtwStamps.press(terrain, point, d.heading, cell_px * 2.0, v.contact_width_px, v.sink_px * slip * DIG_SHARE, 1.0, v.carried_mud)
	# The layers and the vehicle's own lists under local names: the same
	# storage, cheaper to reach on the ticks (most) when no contact has moved
	# on to a new cell.
	var deform := terrain.deform
	var loose := terrain.loose
	var last_cells := v.last_cells
	var last_points := v.last_points
	var depth := 0.0
	for k in points.size():
		var point := points[k]
		var cell := Vector2i((point / cell_px).floor())
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			# Off the map: as deep as the nearest edge cell.
			depth += maxf(0.0, -terrain.relief_at(point))
			continue
		var index := cell.y * size.x + cell.x
		depth += maxf(0.0, -(deform[index] + loose[index]))
		if index == last_cells[k]:
			continue
		var from := last_points[k]
		last_cells[k] = index
		last_points[k] = point
		var span := point - from
		if span.length() > MAX_PATCH_PX:
			continue
		var length := maxf(span.length(), cell_px)
		var heading := span.angle() if span.length() > 0.01 else d.heading
		v.carried_mud = TtwStamps.press(terrain, from + span * 0.5, heading, length, v.contact_width_px, v.sink_px, slip, v.carried_mud)
		if terrain.snow_level > 0.0 or terrain.snow_base[terrain.tile_index(cell / TtwTerrain.CELLS_PER_TILE)] > 0.0:
			TtwSnow.press(terrain, from + span * 0.5, heading, length, v.contact_width_px)
		if v.carried_oil > 0.001 or terrain.oil[index] > 0.0:
			v.carried_oil = TtwOil.smear(terrain, from + span * 0.5, heading, length, v.contact_width_px, v.carried_oil)
	# What is under the hull's centre: one cell and one tile, read once.
	var under := terrain.cell_of(position).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var at := under.y * size.x + under.x
	var tile := terrain.tile_of(position).clamp(Vector2i.ZERO, terrain.size_tiles - Vector2i.ONE)
	var water := maxf(0.0, terrain.water[tile.y * terrain.size_tiles.x + tile.x] - (deform[at] + loose[at]))
	v.water_depth = water
	v.hull_wet = 1.0 if water > 0.3 else maxf(0.0, v.hull_wet - delta / HULL_DRY_SECONDS)
	# It sits on the bottom: as deep as its ruts plus the water over them.
	v.sink = minf(depth / maxf(points.size(), 1) + water, 16.0)
	# Mud cakes on in soft going and washes off in water.
	var material := TtwMaterials.effective(terrain.surface[(under.y / TtwTerrain.CELLS_PER_TILE) * terrain.size_tiles.x + under.x / TtwTerrain.CELLS_PER_TILE], terrain.wear[at])
	var muddy: float = TtwMaterials.SOFTNESS[material] + loose[at]
	var moving := absf(d.speed) / terrain.tile_size_px
	v.grime = clampf(v.grime + muddy * moving * 0.02 * delta - water * 0.05 * delta, 0.0, 1.0)
