class_name TtwSettleSystem extends System
## The ground settling after it was disturbed: tread prints fade, burns fade,
## wet ground dries, compacted grass springs back, and ground steeper than its
## material holds slumps toward its angle of repose (volume kept). Only disturbed cells are
## visited (TtwTerrain.settling), each about once per PERIOD_TICKS, a slice of
## the queue per tick. Not LOD: every queued cell on the map settles at the
## same rate wherever the camera is.

const PERIOD_TICKS := 60
## Seconds for a tread print to fade to a third, a burn to go, wet ground to dry.
const TRACK_FADE_SECONDS := 150.0
const SCORCH_SECONDS := 240.0
const DRY_SECONDS := 120.0
## Wind (px/s) over which loose sand drifts, and how fast: the share of a
## step down to the next cell downwind that moves per second, per px/s over.
const SAND_WIND := 20.0
const SAND_DRIFT := 0.004
## Share of the excess over the angle of repose that slumps per visit.
const SLUMP := 0.35

## The layers settling writes, as the bits a mark takes.
const TRACK := 1 << TtwTerrain.Layer.TRACK
const SCORCH := 1 << TtwTerrain.Layer.SCORCH
const OIL := 1 << TtwTerrain.Layer.OIL
const WET := 1 << TtwTerrain.Layer.WET
const DEFORM := 1 << TtwTerrain.Layer.DEFORM

var session: KitSession
var _cursor: int = 0

func query() -> QueryBuilder:
	return q.with_all([TtwGround])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var terrain: TtwTerrain = entity.get_component(TtwGround).terrain
		if terrain != null:
			settle(terrain)

func settle(terrain: TtwTerrain) -> void:
	var queue := terrain.settling
	terrain.set_settling(PackedInt32Array()) # hold the only reference while writing
	var count := queue.size()
	if count == 0:
		_cursor = 0
		return
	var slice := maxi(1, ceili(float(count) / PERIOD_TICKS))
	var dt := float(PERIOD_TICKS) / Engine.physics_ticks_per_second
	var fade := exp(-dt / TRACK_FADE_SECONDS)
	var scorch_step := dt / SCORCH_SECONDS
	var dry_step := dt / DRY_SECONDS
	var width := terrain.size_cells.x
	var cells := width * terrain.size_cells.y
	var tiles_wide := terrain.size_tiles.x
	var n := TtwTerrain.CELLS_PER_TILE
	# The layers under local names: the same storage as the terrain's, and two
	# to three times cheaper to read and write than through the terrain.
	var track := terrain.track
	var scorch := terrain.scorch
	var wet := terrain.wet
	var deform := terrain.deform
	var loose := terrain.loose
	var wear := terrain.wear
	var surface := terrain.surface
	var water := terrain.water
	var stale := terrain.floors_stale
	var oil := terrain.oil
	var floods := TtwGround.water_of(session)
	var marked := -1
	var marked_layers := 0
	# Sand drifts with a strong wind: from a cell to the next one downwind
	# when that one stands lower (ruts fill in, berms blow away).
	var weather := TtwWeatherSystem.of(session)
	var gust := weather.wind_now if weather != null else Vector2.ZERO
	var drift := maxf(0.0, gust.length() - SAND_WIND) * SAND_DRIFT * dt
	var downwind := 0
	if drift > 0.0:
		downwind = (1 if gust.x > 0.0 else -1) if absf(gust.x) >= absf(gust.y) else (width if gust.y > 0.0 else -width)
	var end := mini(_cursor + slice, count)
	for k in range(_cursor, end):
		var i := queue[k]
		if i < 0:
			continue
		var active := false
		# The layers whose picture changed (a cell under water, still soaked, has
		# none): the view takes only those to the GPU.
		var changed := 0
		var value := track[i]
		var x := i % width
		var tile := (i / width / n) * tiles_wide + x / n
		var base := surface[tile]
		if value > 0.0:
			track[i] = value * pow(fade, TtwMaterials.PRINT_FADE[base]) if value > 0.03 else 0.0
			active = track[i] > 0.0
			changed |= TRACK
		value = scorch[i]
		if value > 0.0:
			scorch[i] = maxf(0.0, value - scorch_step)
			active = active or scorch[i] > 0.0
			changed |= SCORCH
		value = wet[i]
		# Ground under water stays soaked and has nothing to settle: it leaves
		# the queue, and TtwWater queues it again when the water goes.
		var submerged: bool = water[tile] > deform[i] + loose[i]
		# Oil on ground that goes under lifts off and floats.
		if submerged and oil[i] > 0.0 and floods != null and floods.is_wet(tile):
			floods.add_slick(tile, oil[i])
			oil[i] = 0.0
			changed |= OIL
		if value > 0.0:
			if submerged:
				if value != 1.0:
					wet[i] = 1.0
					changed |= WET
			else:
				wet[i] = maxf(0.0, value - dry_step * TtwMaterials.DRY_RATE[base])
				active = active or wet[i] > 0.0
				changed |= WET
		var here := deform[i]
		if drift > 0.0 and base == TtwMaterials.SAND and not submerged:
			var j := i + downwind
			if j >= 0 and j < cells and (downwind != 1 or x + 1 < width) and (downwind != -1 or x > 0):
				var step_down := here - deform[j]
				if step_down > 0.05:
					var moved := step_down * minf(drift, 0.5)
					deform[i] = here - moved
					deform[j] += moved
					here = deform[i]
					terrain.queue_settle(j)
					stale[tile] = 1
					stale[(j / width / n) * tiles_wide + (j % width) / n] = 1
					active = true
					changed |= DEFORM
		if here < 0.0:
			var rebound: float = TtwMaterials.REBOUND[base]
			if rebound > 0.0 and wear[i] < 1.0 and not submerged:
				deform[i] = minf(0.0, here * (1.0 - rebound * dt) + 0.002)
				here = deform[i]
				active = active or here < 0.0
				changed |= DEFORM
				stale[tile] = 1
		# slump() moves ground exactly when the cell stands too far above one of
		# its neighbours; that is tested here so that it is called only then.
		var repose: float = TtwMaterials.REPOSE[TtwMaterials.WORN[base] if wear[i] >= 1.0 else base]
		if repose != INF and (
				(x + 1 < width and here - deform[i + 1] - repose > 0.01)
				or (x > 0 and here - deform[i - 1] - repose > 0.01)
				or (i + width < cells and here - deform[i + width] - repose > 0.01)
				or (i >= width and here - deform[i - width] - repose > 0.01)):
			slump(terrain, i)
			active = true
			changed |= DEFORM
			stale[tile] = 1
		# One mark per run of visits to the same tile, with every layer the run
		# changed: made when the run ends.
		if changed != 0:
			if tile == marked:
				marked_layers |= changed
			else:
				if marked >= 0:
					terrain.mark_tile_quiet(marked % tiles_wide, marked / tiles_wide, marked_layers)
				marked = tile
				marked_layers = changed
		if not active:
			terrain.unqueue_settle(i)
			queue[k] = -1
	if marked >= 0:
		terrain.mark_tile_quiet(marked % tiles_wide, marked / tiles_wide, marked_layers)
	_cursor = end
	if _cursor >= count:
		# A full sweep done: drop the settled cells.
		var kept := PackedInt32Array()
		for i in queue:
			if i >= 0:
				kept.append(i)
		queue = kept
		_cursor = 0
	# Cells queued while this ran went onto the empty queue: keep them too.
	queue.append_array(terrain.settling)
	terrain.set_settling(queue)

## Moves ground from cell `i` down to any neighbour it stands too far above.
## Returns whether it moved any (the cell has more settling to do).
static func slump(terrain: TtwTerrain, i: int) -> bool:
	var width := terrain.size_cells.x
	var x := i % width
	var y := i / width
	var repose: float = TtwMaterials.REPOSE[terrain.effective_material(Vector2i(x, y))]
	if is_inf(repose):
		return false
	var deform := terrain.deform
	var moved := false
	for j: int in [i + 1 if x + 1 < width else -1, i - 1 if x > 0 else -1, i + width if y + 1 < terrain.size_cells.y else -1, i - width if y > 0 else -1]:
		if j < 0:
			continue
		var excess := deform[i] - deform[j] - repose
		if excess > 0.01:
			var amount := excess * SLUMP * 0.5
			deform[i] -= amount
			deform[j] += amount
			terrain.queue_settle(j)
			terrain.mark_cell_quiet(j, DEFORM)
			terrain.mark_relief_quiet(j)
			moved = true
	return moved
