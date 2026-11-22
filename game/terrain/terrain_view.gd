class_name TtwTerrainView extends Node2D
## Draws a TtwTerrain as chunks, each a quad under shaders/terrain.gdshader
## with its own layer textures. Only chunks on screen are drawn, and a chunk's
## textures are uploaded only when it is on screen and its cells changed (an
## off-screen chunk keeps its dirty mark until it comes into view).
##
## The shader works out one colour per world pixel, so the chunks are drawn
## into a buffer of one texel per world pixel (`buffer`, covering what the
## camera shows) and the buffer is put on screen enlarged, nearest texel: at
## zoom 3 that is a ninth of the pixels shaded for the same picture. Zoomed
## out past one screen pixel per world pixel the buffer is the screen's size.
##
## Level of detail is for drawing only (the simulation never uses it). Each
## chunk picks a tier from its distance to the centre of the view and from the
## camera's zoom, with hysteresis, and cross-fades over FADE_SECONDS.

const SHADER := preload("res://shaders/terrain.gdshader")
## Distance from the view's centre, as a share of its half-diagonal, past which
## a chunk drops to the next tier (full -> mid -> far).
const BANDS: Array[float] = [0.62, 1.05]
const HYSTERESIS := 0.08
## Zoom (screen px per world px) below which every chunk is at least mid / far.
const ZOOM_MID := 2.0
const ZOOM_FAR := 1.0
const FADE_SECONDS := 0.25
## Chunks uploaded per refresh at most; the rest wait their turn.
const UPLOADS_PER_REFRESH := 8
## Chunks this far (px) outside the view are still prepared.
const MARGIN_PX := 32.0
## Texels of the buffer kept around the view on each side.
const BUFFER_PAD := 1

enum Tier { FULL, MID, FAR }
## Debug overlays, SimCity style (the shader's `overlay`). TIERS tints chunks
## by their LOD tier instead.
enum Overlay { NONE, WEAR, WETNESS, RELIEF, LOOSE_MUD, TREAD_PRINTS, SCORCH, WATER_DEPTH, MATERIAL, ELEVATION, OIL, SNOW, TIERS }
const OVERLAY_NAMES := ["none", "wear", "wetness", "relief (blue low, red high)", "loose mud", "tread prints", "scorch", "water depth", "material (after wear)", "elevation (bands of 32 px)", "oil (on the ground and afloat)", "snow depth", "LOD tier (white full, orange mid, blue far)"]

var terrain: TtwTerrain
## Off: every chunk draws at FULL (look and cost comparisons in the Mud Lab).
var lod_enabled: bool = true
## The cheapest tier allowed to be better than (quality option): FAR allows all.
var max_tier: int = Tier.FAR
## Tints chunks by tier (debugging the LOD).
var show_tiers: bool = false:
	set(value):
		show_tiers = value
		for chunk in _chunks:
			chunk.modulate = _tier_tint(chunk.tier) if show_tiers else Color.WHITE

var surface_texture: ImageTexture
var elevation_texture: ImageTexture
var water_texture: ImageTexture
var flow_texture: ImageTexture
var slick_texture: ImageTexture
var snow_base_texture: ImageTexture
## The water simulation, for its oil slick (or null).
var water_sim: TtwWater
var noise_texture: ImageTexture
var overlay: int = Overlay.NONE:
	set(value):
		overlay = posmod(value, Overlay.size())
		show_tiers = overlay == Overlay.TIERS
		set_look(&"overlay", overlay if overlay != Overlay.TIERS else 0)
## What the chunks are drawn into, and the sprite that shows it.
var buffer: SubViewport
var _screen: Sprite2D
## The main canvas's transform the buffer was last placed for.
var _placed_for := Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO)
var _placed_window := Vector2.ZERO
var _chunks: Array[Chunk] = []
var _uploads_this_frame: int = 0
var _layers_this_frame: int = 0

## One chunk: its quad, material and layer textures.
class Chunk extends Node2D:
	var coord: Vector2i
	var material_ref: ShaderMaterial
	var textures: Array[ImageTexture] = []
	var tier: int = Tier.FULL
	var from_tier: int = Tier.FULL
	var fade: float = 1.0
	var size_px: Vector2

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color.WHITE)

func show_terrain(value: TtwTerrain) -> void:
	for chunk in _chunks:
		chunk.queue_free()
	_chunks.clear()
	terrain = value
	if terrain == null:
		return
	if noise_texture == null:
		noise_texture = ImageTexture.create_from_image(_make_noise())
	if buffer == null:
		buffer = SubViewport.new()
		buffer.name = "Buffer"
		buffer.world_2d = World2D.new()
		buffer.disable_3d = true
		# Opaque, like the window: drawn through a buffer with a transparent
		# background, one pixel in ten came out a level off the picture drawn
		# straight to the window (docs/ecs.md). The sprite shows only the
		# part of it that is on the map.
		buffer.transparent_bg = false
		buffer.gui_disable_input = true
		buffer.snap_2d_transforms_to_pixel = true
		buffer.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(buffer)
		_screen = Sprite2D.new()
		_screen.name = "Screen"
		_screen.centered = false
		_screen.region_enabled = true
		_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_screen.texture = buffer.get_texture()
		add_child(_screen)
	_placed_for = Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO)
	surface_texture = ImageTexture.create_from_image(terrain.surface_image())
	elevation_texture = ImageTexture.create_from_image(terrain.elevation_image())
	snow_base_texture = ImageTexture.create_from_image(terrain.snow_base_image())
	water_texture = ImageTexture.create_from_image(terrain.water_image())
	flow_texture = ImageTexture.create_from_image(terrain.flow_image())
	var none := PackedFloat32Array()
	none.resize(terrain.size_tiles.x * terrain.size_tiles.y)
	slick_texture = ImageTexture.create_from_image(Image.create_from_data(terrain.size_tiles.x, terrain.size_tiles.y, false, Image.FORMAT_RF, none.to_byte_array()))
	terrain.tiles_dirty = false
	terrain.water_dirty = false
	var chunk_px := TtwTerrain.CHUNK_TILES * TtwTerrain.tile_px()
	for cy in terrain.chunks.y:
		for cx in terrain.chunks.x:
			var chunk := Chunk.new()
			chunk.coord = Vector2i(cx, cy)
			chunk.name = "Chunk_%d_%d" % [cx, cy]
			chunk.position = Vector2(cx, cy) * chunk_px
			# The last row and column stop at the map's edge.
			chunk.size_px = (terrain.size_px() - chunk.position).min(Vector2(chunk_px, chunk_px))
			var shader_material := ShaderMaterial.new()
			shader_material.shader = SHADER
			shader_material.set_shader_parameter("chunk_origin_px", chunk.position)
			shader_material.set_shader_parameter("map_tiles", Vector2(terrain.size_tiles))
			shader_material.set_shader_parameter("tile_px", TtwTerrain.tile_px())
			shader_material.set_shader_parameter("cell_px", TtwTerrain.cell_px())
			shader_material.set_shader_parameter("apron_cells", float(TtwTerrain.APRON))
			shader_material.set_shader_parameter("chunk_texels", float(TtwTerrain.CHUNK_TEXELS))
			shader_material.set_shader_parameter("surface_tex", surface_texture)
			shader_material.set_shader_parameter("elevation_tex", elevation_texture)
			shader_material.set_shader_parameter("snow_base_tex", snow_base_texture)
			shader_material.set_shader_parameter("water_tex", water_texture)
			shader_material.set_shader_parameter("flow_tex", flow_texture)
			shader_material.set_shader_parameter("slick_tex", slick_texture)
			shader_material.set_shader_parameter("noise_tex", noise_texture)
			chunk.material = shader_material
			chunk.material_ref = shader_material
			buffer.add_child(chunk)
			_chunks.append(chunk)
	_upload_all()

## Every chunk, row by row.
func chunks() -> Array[Chunk]:
	return _chunks

func chunk_at(coord: Vector2i) -> Chunk:
	if terrain == null or coord.x < 0 or coord.y < 0 or coord.x >= terrain.chunks.x or coord.y >= terrain.chunks.y:
		return null
	return _chunks[coord.y * terrain.chunks.x + coord.x]

## Sets one look parameter on every chunk.
func set_look(parameter: StringName, value: Variant) -> void:
	for chunk in _chunks:
		chunk.material_ref.set_shader_parameter(parameter, value)

func overlay_name() -> String:
	return OVERLAY_NAMES[overlay]

func look(parameter: StringName) -> Variant:
	return _chunks[0].material_ref.get_shader_parameter(parameter) if not _chunks.is_empty() else null

func _process(delta: float) -> void:
	refresh(delta)

func _enter_tree() -> void:
	RenderingServer.frame_pre_draw.connect(_before_draw)

func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_before_draw)

## A camera moved during the frame reaches the canvas after every _process:
## the buffer is put where the view is now, just before it is drawn.
func _before_draw() -> void:
	if terrain != null and buffer != null:
		_place_buffer()

## Puts the buffer over what the camera shows: one texel per world pixel on
## whole world pixels, or per screen pixel when zoomed out past that.
func _place_buffer() -> void:
	# Hidden, or not in the tree (no viewport, no canvas): nothing is drawn.
	var showing := is_visible_in_tree()
	var mode := SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
	if buffer.render_target_update_mode != mode:
		buffer.render_target_update_mode = mode
	if not showing:
		return
	var canvas := get_global_transform_with_canvas()
	var window := get_viewport().get_visible_rect().size
	if canvas == _placed_for and window == _placed_window:
		return
	_placed_for = canvas
	_placed_window = window
	var view := view_rect()
	var texels_per_px := minf(absf(canvas.get_scale().x), 1.0)
	var origin: Vector2
	var size: Vector2i
	if texels_per_px < 1.0:
		# Zoomed out: the buffer is the screen, texel for pixel, with the
		# canvas's own transform moved over by the pad.
		var pad := Vector2(BUFFER_PAD, BUFFER_PAD)
		origin = canvas.affine_inverse() * -pad
		size = Vector2i((window + pad * 2.0).ceil())
		buffer.canvas_transform = Transform2D(canvas.x, canvas.y, canvas.origin + pad)
	else:
		# One texel per world pixel, on whole world pixels.
		var pad := Vector2(BUFFER_PAD, BUFFER_PAD)
		origin = (view.position - pad).floor()
		size = Vector2i((view.end + pad - origin).ceil())
		buffer.canvas_transform = Transform2D(0.0, -origin)
	size = size.maxi(2)
	if buffer.size != size:
		buffer.size = size
	# The sprite shows the texels whose centres are on the map, as the chunks
	# drawn straight to the screen would cover the pixels whose centres are.
	var half := Vector2(0.5, 0.5)
	var first := ((-origin) * texels_per_px - half).ceil().clamp(Vector2.ZERO, Vector2(size))
	var end := ((terrain.size_px() - origin) * texels_per_px - half).ceil().clamp(Vector2.ZERO, Vector2(size))
	_screen.visible = end.x > first.x and end.y > first.y
	_screen.position = origin + first / texels_per_px
	_screen.scale = Vector2.ONE / texels_per_px
	_screen.region_rect = Rect2(first, end - first)

## Culls, picks tiers and uploads what changed. Called each frame; tests and
## probes call it directly to bring the view up to date before a draw.
func refresh(delta: float = 0.0) -> void:
	if terrain == null:
		return
	_uploads_this_frame = 0
	_layers_this_frame = 0
	if terrain.tiles_dirty:
		surface_texture.update(terrain.surface_image())
		elevation_texture.update(terrain.elevation_image())
		snow_base_texture.update(terrain.snow_base_image())
		terrain.tiles_dirty = false
	if terrain.water_dirty:
		water_texture.update(terrain.water_image())
		flow_texture.update(terrain.flow_image())
	if water_sim != null and water_sim.slick_dirty:
		slick_texture.update(water_sim.slick_image())
		water_sim.slick_dirty = false
		terrain.water_dirty = false
	_place_buffer()
	var view := view_rect()
	var center := view.get_center()
	var half_diagonal := maxf(view.size.length() * 0.5, 1.0)
	var zoom := view_zoom()
	var prepared := view.grow(MARGIN_PX)
	for chunk in _chunks:
		var rect := Rect2(chunk.position, chunk.size_px)
		var on_screen := rect.intersects(prepared)
		chunk.visible = on_screen
		if not on_screen:
			continue
		if terrain.is_chunk_dirty(chunk.coord) and _uploads_this_frame < UPLOADS_PER_REFRESH:
			_upload(chunk)
		var nearest := center.clamp(rect.position, rect.end)
		var share := nearest.distance_to(center) / half_diagonal
		var wanted := tier_for(chunk.tier, share, zoom) if lod_enabled else Tier.FULL
		wanted = mini(wanted, max_tier)
		_set_tier(chunk, wanted, delta)

## The world rect the active camera shows (the whole map without one).
func view_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(Vector2.ZERO, terrain.size_px())
	var inverse := (get_global_transform_with_canvas()).affine_inverse()
	var screen := viewport.get_visible_rect()
	var a := inverse * screen.position
	var b := inverse * screen.end
	return Rect2(a.min(b), (b - a).abs())

func view_zoom() -> float:
	var viewport := get_viewport()
	return viewport.get_canvas_transform().get_scale().x if viewport != null else 1.0

## The tier for a chunk now at `current`, whose nearest point is `share` of the
## view's half-diagonal from its centre, at `zoom`. A chunk moves to a cheaper
## tier only past a band's edge plus HYSTERESIS, and back only inside it minus
## HYSTERESIS, so it doesn't flicker on the edge.
static func tier_for(current: int, share: float, zoom: float) -> int:
	var tier := Tier.FULL
	for i in BANDS.size():
		var edge := BANDS[i] + (HYSTERESIS if current <= i else -HYSTERESIS)
		if share > edge:
			tier = i + 1
	if zoom < ZOOM_FAR:
		tier = maxi(tier, Tier.FAR)
	elif zoom < ZOOM_MID:
		tier = maxi(tier, Tier.MID)
	return tier

func _set_tier(chunk: Chunk, wanted: int, delta: float) -> void:
	if wanted != chunk.tier:
		chunk.from_tier = chunk.tier
		chunk.tier = wanted
		chunk.fade = 0.0 if delta > 0.0 else 1.0
		chunk.material_ref.set_shader_parameter("lod", chunk.tier)
		chunk.material_ref.set_shader_parameter("lod_from", chunk.from_tier)
		if show_tiers:
			chunk.modulate = _tier_tint(chunk.tier)
	if chunk.fade < 1.0:
		chunk.fade = minf(1.0, chunk.fade + delta / FADE_SECONDS)
	chunk.material_ref.set_shader_parameter("lod_mix", chunk.fade)

static func _tier_tint(tier: int) -> Color:
	return [Color(1, 1, 1), Color(1.0, 0.85, 0.7), Color(0.7, 0.8, 1.0)][tier]

func _upload_all() -> void:
	for chunk in _chunks:
		_upload(chunk)

const LAYER_NAMES: Array[StringName] = [&"deform_tex", &"loose_tex", &"wet_tex", &"track_tex", &"angle_tex", &"wear_tex", &"scorch_tex", &"oil_tex", &"snow_gone_tex"]

## Takes the chunk's changed layers to its textures (every layer the first time).
func _upload(chunk: Chunk) -> void:
	var first := chunk.textures.is_empty()
	var changed := TtwTerrain.ALL_LAYERS if first else terrain.chunk_dirty_layers(chunk.coord)
	for layer in TtwTerrain.LAYER_COUNT:
		if (changed & (1 << layer)) == 0:
			continue
		_layers_this_frame += 1
		var image := terrain.chunk_image(layer, chunk.coord)
		if first:
			var texture := ImageTexture.create_from_image(image)
			chunk.textures.append(texture)
			chunk.material_ref.set_shader_parameter(LAYER_NAMES[layer], texture)
		else:
			chunk.textures[layer].update(image)
	terrain.clean_chunk(chunk.coord)
	_uploads_this_frame += 1

## Chunks uploaded by the last refresh().
func uploads_last_refresh() -> int:
	return _uploads_this_frame

## Layer textures uploaded by the last refresh() (a chunk has LAYER_COUNT).
func layers_last_refresh() -> int:
	return _layers_this_frame

static func _make_noise() -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 16.0
	noise.fractal_octaves = 3
	var image := noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_L8)
	return image
