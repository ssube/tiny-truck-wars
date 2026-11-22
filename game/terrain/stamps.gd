class_name TtwStamps extends RefCounted
## What wheels, treads and explosions do to the ground. Every function here
## conserves volume: what it digs out of `deform` and `loose` it puts back as
## berms, mounds, loose mud or mud carried on a vehicle (the sum of deform +
## loose + carried is unchanged), except the share a material compacts
## in place (TtwMaterials.DISPLACE), which springs back over time.

## Shares of the displaced volume: side berms, the bow wave ahead, spray behind.
const BERM_SHARE := 0.6
const BOW_SHARE := 0.25
const SPRAY_SHARE := 0.15
## How wide (px) a berm is, how far ahead the bow reaches, how far spray flies.
const BERM_PX := 3.0
const BOW_PX := 4.0
const SPRAY_PX := 10.0
## Loose mud in the footprint that a press squeezes out.
const SQUEEZE := 0.8
## Share of what a press moves that sticks to the vehicle on sticky ground,
## and share of what it carries that it drops each press.
const PICKUP := 0.08
const DROP := 0.06
## How far (px) past its bounds a press still looks for cells: more than any
## rounding of a cell centre's place, far less than a cell.
const SLACK_PX := 0.05

## The layers a press writes (TtwTerrain.mark_cells): the view uploads these.
const PRESS_LAYERS := (1 << TtwTerrain.Layer.DEFORM) | (1 << TtwTerrain.Layer.LOOSE) | (1 << TtwTerrain.Layer.WEAR) | (1 << TtwTerrain.Layer.TRACK) | (1 << TtwTerrain.Layer.TRACK_ANGLE)

## Craters by cause: radius and depth (px).
const CRATERS := {
	&"shell": Vector2(6.0, 3.0),
	&"rocket": Vector2(9.0, 4.5),
	&"vehicle": Vector2(14.0, 6.0),
	&"building": Vector2(24.0, 8.0),
	&"depot": Vector2(30.0, 9.0),
}

## Presses one contact patch: an oriented rectangle `length_px` long along
## `heading` and `width_px` across, centred on `center`, sinking `sink_px`
## into fully soft ground. `slip` (0..1) throws more out behind. Returns the
## mud the vehicle carries afterwards (was `carried`).
static func press(t: TtwTerrain, center: Vector2, heading: float, length_px: float, width_px: float, sink_px: float, slip: float, carried: float) -> float:
	var along := Vector2.from_angle(heading)
	var side := along.orthogonal()
	var cell_px := t.cell_size_px
	var half_l := length_px * 0.5
	var half_w := width_px * 0.5
	var foot: PackedInt32Array = []
	var berm: PackedInt32Array = []
	var bow: PackedInt32Array = []
	var spray: PackedInt32Array = []
	var reach := half_l + SPRAY_PX + BERM_PX + cell_px
	var lo := t.cell_of(center - Vector2(reach, reach)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var hi := t.cell_of(center + Vector2(reach, reach)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	# Every cell that gets anything lies in the strip from the end of the spray
	# to the end of the bow, a berm wide on each side. Only the cells whose
	# centres can be in that strip are looked at: its bounds along x and y
	# (grown by SLACK_PX, so rounding never drops a cell on its edge), inside
	# the box above.
	var back := -half_l - SPRAY_PX
	var front := half_l + BOW_PX
	var across := half_w + BERM_PX
	var span_x := absf(side.x) * across + SLACK_PX
	var span_y := absf(side.y) * across + SLACK_PX
	lo = lo.max(Vector2i(
		ceili((center.x + minf(along.x * back, along.x * front) - span_x) / cell_px - 0.5),
		ceili((center.y + minf(along.y * back, along.y * front) - span_y) / cell_px - 0.5)))
	hi = hi.min(Vector2i(
		floori((center.x + maxf(along.x * back, along.x * front) + span_x) / cell_px - 0.5),
		floori((center.y + maxf(along.y * back, along.y * front) + span_y) / cell_px - 0.5)))
	var width := t.size_cells.x
	for y in range(lo.y, hi.y + 1):
		var row := y * width
		for x in range(lo.x, hi.x + 1):
			var p := Vector2(x + 0.5, y + 0.5) * cell_px - center
			var v := absf(p.dot(side))
			if v > across:
				continue
			var u := p.dot(along)
			if u < -half_l:
				# Behind the patch: spray, a berm wider than the patch.
				if u >= back:
					spray.append(row + x)
			elif u <= half_l:
				# Beside or under the patch.
				if v <= half_w:
					foot.append(row + x)
				else:
					berm.append(row + x)
			elif u <= front and v <= half_w:
				# Ahead of it: the bow wave, as wide as the patch.
				bow.append(row + x)
	if foot.is_empty():
		return carried
	var moved := 0.0
	var sticky := 0.0
	# Local names share the layers' storage and are cheaper to read and write.
	var surface := t.surface
	var deform := t.deform
	var loose := t.loose
	var wear := t.wear
	var wet := t.wet
	var track := t.track
	var track_angle := t.track_angle
	var tiles_wide := t.size_tiles.x
	for i in foot:
		var base := surface[(i / width / TtwTerrain.CELLS_PER_TILE) * tiles_wide + i % width / TtwTerrain.CELLS_PER_TILE]
		var m := TtwMaterials.effective(base, wear[i])
		var soft: float = TtwMaterials.SOFTNESS[m] * (1.0 + TtwMaterials.WET_SOFTENING[m] * wet[i])
		# Loose mud is squeezed out first.
		var squeezed := loose[i] * SQUEEZE
		loose[i] -= squeezed
		moved += squeezed
		# Then the ground sinks, no deeper than the material holds.
		var room := maxf(0.0, deform[i] + TtwMaterials.MAX_DEPTH[m])
		var dig := minf(sink_px * soft, room)
		deform[i] -= dig
		moved += dig * TtwMaterials.DISPLACE[m]
		sticky += dig * soft
		wear[i] += sink_px * TtwMaterials.WEAR_RATE[base]
		track[i] = 1.0
		track_angle[i] = heading
	t.queue_settle_cells(foot)
	# Some sticks to the vehicle; some of what it carried drops off here.
	var picked := minf(moved, sticky * PICKUP)
	moved -= picked
	var dropped := carried * DROP
	carried = carried - dropped + picked
	_spread_loose(t, foot, dropped)
	# The rest goes aside: berms as raised ground, bow and spray as loose mud.
	var spray_share := SPRAY_SHARE + BOW_SHARE * clampf(slip, 0.0, 1.0) * 0.5
	var bow_share := BOW_SHARE - (spray_share - SPRAY_SHARE)
	var to_berm := moved * BERM_SHARE
	var to_bow := moved * bow_share
	var to_spray := moved * spray_share
	_spread_raise(t, berm if not berm.is_empty() else foot, to_berm)
	_spread_loose(t, bow if not bow.is_empty() else foot, to_bow)
	_spread_loose(t, spray if not spray.is_empty() else foot, to_spray)
	t.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE), PRESS_LAYERS)
	return carried

## Blows a crater of `cause` (CRATERS) at `center`: a bowl dug out whatever the
## ground, its volume thrown into a rim (70%) and clods of loose mud around it
## (30%). The ground in it is torn or broken, and scorched.
static func crater(t: TtwTerrain, center: Vector2, cause: StringName) -> void:
	var size: Vector2 = CRATERS.get(cause, CRATERS[&"shell"])
	blast(t, center, size.x, size.y)

static func blast(t: TtwTerrain, center: Vector2, radius_px: float, depth_px: float) -> void:
	var cell_px := t.cell_size_px
	var outer := radius_px * 2.4
	var lo := t.cell_of(center - Vector2(outer, outer)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var hi := t.cell_of(center + Vector2(outer, outer)).clamp(Vector2i.ZERO, t.size_cells - Vector2i.ONE)
	var width := t.size_cells.x
	var dug := 0.0
	var rim: PackedInt32Array = []
	var rim_weights: PackedFloat32Array = []
	var clods: PackedInt32Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(center.floor()))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var i := y * width + x
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px).distance_to(center) / radius_px
			if d < 1.0:
				var dig := depth_px * (1.0 - d * d)
				var cell := Vector2i(x, y)
				if t.material_at_tile(cell / TtwTerrain.CELLS_PER_TILE) == TtwMaterials.ROCK:
					dig *= 0.3
				t.deform[i] -= dig
				dug += dig + t.loose[i]
				t.loose[i] = 0.0
				t.wear[i] = maxf(t.wear[i], 1.0)
				t.scorch[i] = maxf(t.scorch[i], 1.0 - d * 0.4)
				t.track[i] = 0.0
				t.queue_settle(i)
			elif d < 1.45:
				rim.append(i)
				rim_weights.append(1.0 - absf(d - 1.2) / 0.25)
				t.scorch[i] = maxf(t.scorch[i], 0.5 * (1.45 - d) / 0.45)
				t.queue_settle(i)
			elif d < 2.4 and rng.randf() < 0.18:
				clods.append(i)
	var total_weight := 0.0
	for w in rim_weights:
		total_weight += maxf(w, 0.05)
	var to_rim := dug * (0.7 if not clods.is_empty() else 1.0)
	if total_weight > 0.0:
		for k in rim.size():
			t.deform[rim[k]] += to_rim * maxf(rim_weights[k], 0.05) / total_weight
	else:
		to_rim = 0.0
	_spread_loose(t, clods, dug - to_rim)
	t.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE))

static func _spread_loose(t: TtwTerrain, cells: PackedInt32Array, amount: float) -> void:
	if cells.is_empty() or amount == 0.0:
		return
	var each := amount / cells.size()
	var loose := t.loose
	for i in cells:
		loose[i] += each

## Raises soft ground; on hard ground (nothing to push up) it lies as loose mud.
static func _spread_raise(t: TtwTerrain, cells: PackedInt32Array, amount: float) -> void:
	if cells.is_empty() or amount == 0.0:
		return
	var each := amount / cells.size()
	var width := t.size_cells.x
	var tiles_wide := t.size_tiles.x
	var surface := t.surface
	var wear := t.wear
	var deform := t.deform
	var loose := t.loose
	for i in cells:
		var m := TtwMaterials.effective(surface[(i / width / TtwTerrain.CELLS_PER_TILE) * tiles_wide + i % width / TtwTerrain.CELLS_PER_TILE], wear[i])
		if TtwMaterials.SOFTNESS[m] > 0.0:
			deform[i] += each
		else:
			loose[i] += each
	t.queue_settle_cells(cells)
