class_name TtwPathView extends Node2D
## Debug drawing for routes: each tile's path weight over the part of the map
## in view (green cheap to red dear, black walls), and the route of every
## vehicle with a move order.

var session: KitSession
var camera: Camera2D
var show_costs: bool = false

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if session == null:
		return
	var grid := TtwGround.paths_of(session)
	if grid == null:
		return
	var t := grid.terrain
	var tile := t.tile_size_px
	if show_costs and camera != null:
		var half := get_viewport_rect().size / camera.zoom * 0.5
		var lo := t.tile_of(camera.position - half).clamp(Vector2i.ZERO, t.size_tiles - Vector2i.ONE)
		var hi := t.tile_of(camera.position + half).clamp(Vector2i.ZERO, t.size_tiles - Vector2i.ONE)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var at := Vector2i(x, y)
				var c := grid.cost[t.tile_index(at)]
				var color := Color(0, 0, 0, 0.6) if grid.astar.is_point_solid(at) else Color.from_hsv(clampf(0.33 - (c - 1.0) * 0.08, 0.0, 0.33), 0.9, 0.9, 0.35)
				draw_rect(Rect2(Vector2(at) * tile, Vector2(tile, tile)), color)
	for entity in session.view([TtwMoveOrder, KitBody]):
		var o: TtwMoveOrder = entity.get_component(TtwMoveOrder)
		var body := session.body_of(entity)
		if body == null or o.path.is_empty():
			continue
		var points := PackedVector2Array([body.position])
		for k in range(o.next, o.path.size()):
			points.append(o.path[k])
		if points.size() > 1:
			draw_polyline(points, Color(1, 1, 1, 0.8), 1.0)
		draw_circle(o.target, 2.0, Color.WHITE)
