class_name TtwOil extends RefCounted
## Oil: spilled onto the ground (TtwTerrain.oil) or the water (TtwWater's
## slick), smeared about by wheels and treads, slippery, and fuel for fire.
## Volume is kept: what a spill puts down is what lies on the ground plus
## what floats, plus what vehicles carry.

## How slippery a film of oil (FULL_SLIP_FILM and over) makes each material:
## the share of grip lost (pavement worst, sand least).
const SLIP := [0.3, 0.4, 0.7, 0.5, 0.2, 0.6]
## Fire fuel per unit of oil.
const FUEL := 4.0
## Share of the oil under a contact it picks up, and of what it carries that
## it leaves behind, per press.
const PICKUP := 0.3
const DROP := 0.1

## A film this thick (or thicker) takes all the grip its material loses.
const FULL_SLIP_FILM := 0.2

## The grip left on `material` under `film` of oil (1 = none lost).
static func grip(material: int, film: float) -> float:
	return 1.0 - SLIP[material] * clampf(film / FULL_SLIP_FILM, 0.0, 1.0)

## Spills `amount` over a disc of `radius_px` at `at`: onto the ground, or onto
## the water where a tile is wet. Returns the fuel it gives each tile it
## touched (tile index -> fuel), for the fire.
static func spill(terrain: TtwTerrain, water: TtwWater, at: Vector2, amount: float, radius_px: float) -> Dictionary:
	var cell_px := TtwTerrain.cell_px()
	var r := maxf(radius_px, cell_px)
	var lo := terrain.cell_of(at - Vector2(r, r)).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var hi := terrain.cell_of(at + Vector2(r, r)).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)
	var cells: PackedInt32Array = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if ((Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px).distance_to(at) <= r:
				cells.append(y * terrain.size_cells.x + x)
	if cells.is_empty():
		cells.append(terrain.cell_index(terrain.cell_of(at).clamp(Vector2i.ZERO, terrain.size_cells - Vector2i.ONE)))
	var each := amount / cells.size()
	var fuel := {}
	var n := TtwTerrain.CELLS_PER_TILE
	for i in cells:
		var tile := (i / terrain.size_cells.x / n) * terrain.size_tiles.x + (i % terrain.size_cells.x) / n
		if water != null and water.is_wet(tile):
			water.add_slick(tile, each)
		else:
			terrain.oil[i] += each
		fuel[tile] = fuel.get(tile, 0.0) + each * FUEL
	terrain.mark_cells(Rect2i(lo, hi - lo + Vector2i.ONE))
	return fuel

## A contact patch rolls over the ground: it picks up some of the oil there
## and leaves some of what it carries. Returns what it carries now.
static func smear(terrain: TtwTerrain, center: Vector2, heading: float, length_px: float, width_px: float, carried: float) -> float:
	var along := Vector2.from_angle(heading)
	var side := along.orthogonal()
	var cell_px := terrain.cell_size_px
	var half_l := length_px * 0.5
	var half_w := width_px * 0.5
	# Only the cells that can lie under the patch are tested.
	var cells := TtwStamps.strip_cells(terrain, center, along, -half_l, half_l, half_w)
	var lo := cells.position
	var hi := cells.end - Vector2i.ONE
	var width := terrain.size_cells.x
	var foot: PackedInt32Array = []
	var oil := terrain.oil
	var picked := 0.0
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_px - center
			if absf(p.dot(along)) <= half_l and absf(p.dot(side)) <= half_w:
				var i := y * width + x
				foot.append(i)
				var take := oil[i] * PICKUP
				oil[i] -= take
				picked += take
	if foot.is_empty():
		return carried
	var dropped := carried * DROP
	var each := dropped / foot.size()
	for i in foot:
		oil[i] += each
	if picked > 0.0 or dropped > 0.0:
		terrain.mark_cells(cells)
	return carried - dropped + picked
