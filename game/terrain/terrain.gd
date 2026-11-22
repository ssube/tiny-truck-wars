class_name TtwTerrain extends RefCounted
## The ground of one map: plain packed arrays on the CPU, which are the truth
## for gameplay and tests. The view (TtwTerrainView) uploads the chunks that
## changed. Heights are in world pixels; positive is up.
##
## Two resolutions:
## - tile (Kit2D tile, 16 px): surface material, elevation, water
## - cell (CELLS_PER_TILE per tile side, 2 px): deformation, loose mud,
##   wetness, track strength and track direction
## Chunks are CHUNK_TILES square; each chunk's textures carry APRON extra
## cells on every side so the shader can look across a chunk edge.

## Emitted when cells change, with the cell rect (for path weights, sounds...).
signal cells_changed(rect: Rect2i)

const CELLS_PER_TILE := 8
const CHUNK_TILES := 16
const CHUNK_CELLS := CHUNK_TILES * CELLS_PER_TILE
const APRON := 8
const CHUNK_TEXELS := CHUNK_CELLS + 2 * APRON

enum Layer { DEFORM, LOOSE, WET, TRACK, TRACK_ANGLE, WEAR, SCORCH, OIL, SNOW_GONE }
const LAYER_COUNT := 9
## Every cell layer, as the bits a mark takes (1 << Layer.DEFORM, ...).
const ALL_LAYERS := (1 << LAYER_COUNT) - 1

var size_tiles: Vector2i
var size_cells: Vector2i
var chunks: Vector2i
## A tile's and a cell's side in px, read once: tile_px() and cell_px() ask
## the project settings on every call, which is most of the cost of a lookup.
var tile_size_px: float
var cell_size_px: float
## The water level where there is none: far below any rut or crater.
const NO_WATER := -64.0

## Tile layers.
var surface: PackedByteArray
var elevation: PackedFloat32Array
## Standing water's surface level (px), measured like relief: 0 is the
## undisturbed ground, so a level of 1 fills every rut and covers flat ground
## 1 px deep. NO_WATER where there is none.
var water: PackedFloat32Array
## The water's current per tile (px per second), kept by the water
## simulation (TtwWater) where there is one.
var flow: PackedVector2Array
## Snow lying on each tile as the map was made (px deep), and the snow fallen
## since less what has thawed, everywhere at once (px; negative once the
## thaw has eaten into the base).
var snow_base: PackedFloat32Array
var snow_level: float = 0.0
## Where water comes from and goes: {"rect": Rect2i (tiles), "level": float
## (px, absolute like elevation)}. A source keeps its tiles up to the level,
## a sink drains them down to it.
var water_sources: Array[Dictionary] = []
var water_sinks: Array[Dictionary] = []
## Cell layers. Kept as separate members, never in a container: a packed
## array written through `container[i][j] = v` is copied whole on every write.
## Systems that write cells write these directly and then call mark_cells once.
var deform: PackedFloat32Array
var loose: PackedFloat32Array
var wet: PackedFloat32Array
var track: PackedFloat32Array
var track_angle: PackedFloat32Array
## How worn the ground is (0..1+): worn-through grass is torn up into mud,
## worn-through pavement is broken into gravel (TtwMaterials.effective).
var wear: PackedFloat32Array
## Burn marks from explosions (0..1), fading.
var scorch: PackedFloat32Array
## Oil on the ground (film thickness; about 1 is a puddle). Oil on water is
## TtwWater's slick.
var oil: PackedFloat32Array
## Snow taken from each cell (pressed down, melted, blown away; negative
## where it was pushed up into a berm). A cell's snow is
## snow_base[tile] + snow_level - snow_gone[cell] (TtwSnow.depth).
var snow_gone: PackedFloat32Array
## Cells that still have settling to do (TtwSettleSystem): a queue of cell
## indices, and a flag per cell so none is queued twice.
var settling: PackedInt32Array
var _queued: PackedByteArray
## Chunk index -> the cell layers (a bit each, 1 << Layer) that changed since
## the view last took them, and how many chunks are marked. A writer that
## knows which layers it wrote says so, and the view uploads only those; one
## that does not say marks them all.
var _dirty_chunks: PackedInt32Array
var _dirty_count: int = 0
## The tile layers changed (surface, elevation) since the view last took them.
## Tile index -> 1 when the relief of any of its cells (deform, loose) may have
## changed since the water last worked out that tile's floors (TtwWater clears
## it). Set by mark_cells and mark_relief_quiet.
var floors_stale: PackedByteArray
## Tile index -> 1 while it waits in path_queue for the path grid to weigh it
## again (TtwPathGrid takes them). Set wherever floors_stale is, and when a
## tile's material or elevation changes; a tile is queued once.
var path_stale: PackedByteArray
var path_queue: PackedInt32Array
var tiles_dirty: bool = true
var water_dirty: bool = true

func _init(tiles: Vector2i) -> void:
	size_tiles = Vector2i(maxi(1, tiles.x), maxi(1, tiles.y))
	tile_size_px = tile_px()
	cell_size_px = cell_px()
	size_cells = size_tiles * CELLS_PER_TILE
	chunks = Vector2i(ceili(float(size_tiles.x) / CHUNK_TILES), ceili(float(size_tiles.y) / CHUNK_TILES))
	var tile_count := size_tiles.x * size_tiles.y
	surface = PackedByteArray()
	surface.resize(tile_count)
	surface.fill(TtwMaterials.GRASS)
	elevation = PackedFloat32Array()
	elevation.resize(tile_count)
	water = PackedFloat32Array()
	water.resize(tile_count)
	water.fill(NO_WATER)
	flow.resize(tile_count)
	snow_base.resize(tile_count)
	floors_stale.resize(tile_count)
	path_stale.resize(tile_count)
	var cell_count := size_cells.x * size_cells.y
	deform.resize(cell_count)
	loose.resize(cell_count)
	wet.resize(cell_count)
	track.resize(cell_count)
	track_angle.resize(cell_count)
	wear.resize(cell_count)
	scorch.resize(cell_count)
	oil.resize(cell_count)
	snow_gone.resize(cell_count)
	_queued.resize(cell_count)
	_dirty_chunks.resize(chunks.x * chunks.y)
	mark_all()

## A cell layer by id, for reading. Don't hold it across writes: a write to the
## member while this copy is alive copies the whole layer.
func layer(id: int) -> PackedFloat32Array:
	match id:
		Layer.DEFORM: return deform
		Layer.LOOSE: return loose
		Layer.WET: return wet
		Layer.TRACK: return track
		Layer.TRACK_ANGLE: return track_angle
		Layer.WEAR: return wear
		Layer.SCORCH: return scorch
		Layer.OIL: return oil
		_: return snow_gone

#region Coordinates

static func tile_px() -> float:
	return float(Kit2D.tile_size())

static func cell_px() -> float:
	return float(Kit2D.tile_size()) / CELLS_PER_TILE

func size_px() -> Vector2:
	return Vector2(size_tiles) * tile_size_px

func cell_of(world: Vector2) -> Vector2i:
	return Vector2i((world / cell_size_px).floor())

func tile_of(world: Vector2) -> Vector2i:
	return Vector2i((world / tile_size_px).floor())

func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size_cells.x and cell.y < size_cells.y

func has_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size_tiles.x and tile.y < size_tiles.y

func cell_index(cell: Vector2i) -> int:
	return cell.y * size_cells.x + cell.x

func tile_index(tile: Vector2i) -> int:
	return tile.y * size_tiles.x + tile.x

#endregion

#region Reading

func material_at_tile(tile: Vector2i) -> int:
	tile = tile.clamp(Vector2i.ZERO, size_tiles - Vector2i.ONE)
	return surface[tile_index(tile)]

func material_at(world: Vector2) -> int:
	return material_at_tile(tile_of(world))

## The material a cell behaves as now, after wear (torn grass is mud).
func effective_material(cell: Vector2i) -> int:
	cell = cell.clamp(Vector2i.ZERO, size_cells - Vector2i.ONE)
	return TtwMaterials.effective(material_at_tile(cell / CELLS_PER_TILE), wear[cell_index(cell)])

func effective_material_at(world: Vector2) -> int:
	return effective_material(cell_of(world))

## A cell layer's value; outside the map, the nearest edge cell's.
func cell_value(layer_id: int, cell: Vector2i) -> float:
	cell = cell.clamp(Vector2i.ZERO, size_cells - Vector2i.ONE)
	var i := cell_index(cell)
	match layer_id:
		Layer.DEFORM: return deform[i]
		Layer.LOOSE: return loose[i]
		Layer.WET: return wet[i]
		Layer.TRACK: return track[i]
		Layer.TRACK_ANGLE: return track_angle[i]
		Layer.WEAR: return wear[i]
		Layer.SCORCH: return scorch[i]
		Layer.OIL: return oil[i]
		_: return snow_gone[i]

## The ground's height offset from deformation and loose mud at a point (px).
func relief_at(world: Vector2) -> float:
	var cell := cell_of(world)
	return cell_value(Layer.DEFORM, cell) + cell_value(Layer.LOOSE, cell)

## Elevation (px), bilinear between tile centres.
func elevation_at(world: Vector2) -> float:
	var t := world / tile_size_px - Vector2(0.5, 0.5)
	var base := Vector2i(t.floor())
	var f := t - Vector2(base)
	# The four tiles around it, each held to the map.
	var x0 := clampi(base.x, 0, size_tiles.x - 1)
	var x1 := clampi(base.x + 1, 0, size_tiles.x - 1)
	var row0 := clampi(base.y, 0, size_tiles.y - 1) * size_tiles.x
	var row1 := clampi(base.y + 1, 0, size_tiles.y - 1) * size_tiles.x
	return lerpf(lerpf(elevation[row0 + x0], elevation[row0 + x1], f.x), lerpf(elevation[row1 + x0], elevation[row1 + x1], f.x), f.y)

## The water level over a point (NO_WATER where dry).
func water_at(world: Vector2) -> float:
	var tile := tile_of(world).clamp(Vector2i.ZERO, size_tiles - Vector2i.ONE)
	return water[tile_index(tile)]

## Sum of a cell layer over the whole map (conservation checks).
func layer_total(layer_id: int) -> float:
	var total := 0.0
	for value in layer(layer_id):
		total += value
	return total

#endregion

#region Writing

func set_material(tile: Vector2i, id: int) -> void:
	if has_tile(tile) and TtwMaterials.is_valid(id):
		surface[tile_index(tile)] = id
		tiles_dirty = true
		stale_path(tile_index(tile))

func set_elevation(tile: Vector2i, height: float) -> void:
	if has_tile(tile):
		elevation[tile_index(tile)] = height
		tiles_dirty = true
		for near in [tile, tile + Vector2i.LEFT, tile + Vector2i.RIGHT, tile + Vector2i.UP, tile + Vector2i.DOWN]:
			if has_tile(near):
				stale_path(tile_index(near))

## One cell, marked at once. Bulk writers write the members and mark once.
func set_cell(layer_id: int, cell: Vector2i, value: float) -> void:
	if not has_cell(cell):
		return
	var i := cell_index(cell)
	match layer_id:
		Layer.DEFORM: deform[i] = value
		Layer.LOOSE: loose[i] = value
		Layer.WET: wet[i] = value
		Layer.TRACK: track[i] = value
		Layer.TRACK_ANGLE: track_angle[i] = value
		Layer.WEAR: wear[i] = value
		Layer.SCORCH: scorch[i] = value
		Layer.OIL: oil[i] = value
		_: snow_gone[i] = value
	mark_cells(Rect2i(cell, Vector2i.ONE))

## Marks the chunks that show any cell of `rect` (a chunk shows its apron too).
func mark_cells(rect: Rect2i, layers: int = ALL_LAYERS) -> void:
	var grown := rect.grow(APRON)
	var first := (grown.position / CHUNK_CELLS).clamp(Vector2i.ZERO, chunks - Vector2i.ONE)
	var last := ((grown.end - Vector2i.ONE) / CHUNK_CELLS).clamp(Vector2i.ZERO, chunks - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for i in range(y * chunks.x + first.x, y * chunks.x + last.x + 1):
			if _dirty_chunks[i] == 0:
				_dirty_count += 1
			_dirty_chunks[i] |= layers
	var from := (rect.position / CELLS_PER_TILE).clamp(Vector2i.ZERO, size_tiles - Vector2i.ONE)
	var to := ((rect.end - Vector2i.ONE) / CELLS_PER_TILE).clamp(Vector2i.ZERO, size_tiles - Vector2i.ONE)
	for y in range(from.y, to.y + 1):
		for i in range(y * size_tiles.x + from.x, y * size_tiles.x + to.x + 1):
			floors_stale[i] = 1
			if path_stale[i] == 0:
				path_stale[i] = 1
				path_queue.append(i)
	cells_changed.emit(rect)

## Marks one cell's chunks without telling listeners (bulk settling).
func mark_cell_quiet(index: int, layers: int = ALL_LAYERS) -> void:
	var cell := Vector2i(index % size_cells.x, index / size_cells.x)
	var lo := ((cell - Vector2i(APRON, APRON)) / CHUNK_CELLS).clamp(Vector2i.ZERO, chunks - Vector2i.ONE)
	var hi := ((cell + Vector2i(APRON, APRON)) / CHUNK_CELLS).clamp(Vector2i.ZERO, chunks - Vector2i.ONE)
	for y in range(lo.y, hi.y + 1):
		for i in range(y * chunks.x + lo.x, y * chunks.x + hi.x + 1):
			if _dirty_chunks[i] == 0:
				_dirty_count += 1
			_dirty_chunks[i] |= layers

## Marks the chunks that show any cell of one tile, without telling listeners.
## The apron is a tile wide, so a tile's cells all show in the same chunks.
func mark_tile_quiet(tile_x: int, tile_y: int, layers: int = ALL_LAYERS) -> void:
	var x0 := maxi(tile_x - 1, 0) / CHUNK_TILES
	var x1 := mini((tile_x + 1) / CHUNK_TILES, chunks.x - 1)
	var y1 := mini((tile_y + 1) / CHUNK_TILES, chunks.y - 1)
	for y in range(maxi(tile_y - 1, 0) / CHUNK_TILES, y1 + 1):
		for i in range(y * chunks.x + x0, y * chunks.x + x1 + 1):
			if _dirty_chunks[i] == 0:
				_dirty_count += 1
			_dirty_chunks[i] |= layers

## Tells the water a cell's relief changed, without telling listeners (bulk
## settling: slumps and ruts springing back).
func mark_relief_quiet(index: int) -> void:
	var i := (index / size_cells.x / CELLS_PER_TILE) * size_tiles.x + index % size_cells.x / CELLS_PER_TILE
	floors_stale[i] = 1
	if path_stale[i] == 0:
		path_stale[i] = 1
		path_queue.append(i)

## Queues one tile for the path grid (once).
func stale_path(i: int) -> void:
	if path_stale[i] == 0:
		path_stale[i] = 1
		path_queue.append(i)

## Queues a cell for settling (once).
func queue_settle(index: int) -> void:
	if _queued[index] == 0:
		_queued[index] = 1
		settling.append(index)

## Queues each of `cells` that is not queued yet, in order.
func queue_settle_cells(cells: PackedInt32Array) -> void:
	for index in cells:
		if _queued[index] == 0:
			_queued[index] = 1
			settling.append(index)

## Replaces the settling queue (the settle system's bookkeeping).
func set_settling(queue: PackedInt32Array) -> void:
	settling = queue

func unqueue_settle(index: int) -> void:
	_queued[index] = 0

func mark_all() -> void:
	_dirty_chunks.fill(ALL_LAYERS)
	_dirty_count = _dirty_chunks.size()
	tiles_dirty = true
	water_dirty = true

#endregion

#region For the view

func is_chunk_dirty(chunk: Vector2i) -> bool:
	return _dirty_chunks[chunk.y * chunks.x + chunk.x] != 0

## The cell layers of a chunk that changed since it was last cleaned, a bit
## each (1 << Layer); 0 when none did.
func chunk_dirty_layers(chunk: Vector2i) -> int:
	return _dirty_chunks[chunk.y * chunks.x + chunk.x]

## Takes the chunk's dirty mark (the view has uploaded it).
func clean_chunk(chunk: Vector2i) -> void:
	var i := chunk.y * chunks.x + chunk.x
	if _dirty_chunks[i] != 0:
		_dirty_chunks[i] = 0
		_dirty_count -= 1

func dirty_chunk_count() -> int:
	return _dirty_count

## One cell layer of a chunk as an RF image of CHUNK_TEXELS square: the chunk's
## cells plus APRON cells around it, the map's edge cells repeated outside it.
func chunk_image(layer_id: int, chunk: Vector2i) -> Image:
	var data := layer(layer_id)
	var origin := chunk * CHUNK_CELLS - Vector2i(APRON, APRON)
	var out := PackedFloat32Array()
	var x0 := clampi(origin.x, 0, size_cells.x)
	var x1 := clampi(origin.x + CHUNK_TEXELS, 0, size_cells.x)
	var left := x0 - origin.x
	var right := origin.x + CHUNK_TEXELS - x1
	for row in CHUNK_TEXELS:
		var y := clampi(origin.y + row, 0, size_cells.y - 1)
		var start := y * size_cells.x
		if left > 0:
			var edge := PackedFloat32Array()
			edge.resize(left)
			edge.fill(data[start])
			out.append_array(edge)
		if x1 > x0:
			out.append_array(data.slice(start + x0, start + x1))
		if right > 0:
			var edge := PackedFloat32Array()
			edge.resize(right)
			edge.fill(data[start + size_cells.x - 1])
			out.append_array(edge)
	return Image.create_from_data(CHUNK_TEXELS, CHUNK_TEXELS, false, Image.FORMAT_RF, out.to_byte_array())

## Surface ids as an R8 image, one texel per tile.
func surface_image() -> Image:
	return Image.create_from_data(size_tiles.x, size_tiles.y, false, Image.FORMAT_R8, surface)

func elevation_image() -> Image:
	return Image.create_from_data(size_tiles.x, size_tiles.y, false, Image.FORMAT_RF, elevation.to_byte_array())

## The current as an RGF image, one texel per tile (px/s).
func flow_image() -> Image:
	return Image.create_from_data(size_tiles.x, size_tiles.y, false, Image.FORMAT_RGF, flow.to_byte_array())

func snow_base_image() -> Image:
	return Image.create_from_data(size_tiles.x, size_tiles.y, false, Image.FORMAT_RF, snow_base.to_byte_array())

func water_image() -> Image:
	return Image.create_from_data(size_tiles.x, size_tiles.y, false, Image.FORMAT_RF, water.to_byte_array())

#endregion

## The current at a point (px per second; zero where dry).
func current_at(world: Vector2) -> Vector2:
	if water_depth_at(world) <= 0.0:
		return Vector2.ZERO
	var tile := tile_of(world).clamp(Vector2i.ZERO, size_tiles - Vector2i.ONE)
	return flow[tile_index(tile)]

## The elevation's slope at a point: px of rise per px of run, as a vector.
func elevation_gradient(world: Vector2) -> Vector2:
	var e := tile_size_px * 0.5
	return Vector2(elevation_at(world + Vector2(e, 0)) - elevation_at(world - Vector2(e, 0)),
		elevation_at(world + Vector2(0, e)) - elevation_at(world - Vector2(0, e))) / (2.0 * e)

## How deep standing water is over a point (0 where dry).
func water_depth_at(world: Vector2) -> float:
	return maxf(0.0, water_at(world) - relief_at(world))
