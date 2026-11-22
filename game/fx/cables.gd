class_name TtwCables extends Node2D
## Draws winch cables (taut, straight) and tow ropes (sagging when slack)
## between wreckers and their loads.

const CABLE := Color(0.12, 0.11, 0.1)
const TILT_K := 0.6
## Hitch height above the ground (px, drawn up the screen).
const HITCH_PX := 4.0

var session: KitSession

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if session == null:
		return
	for wrecker in session.view([TtwWinch, KitBody]):
		var winch: TtwWinch = wrecker.get_component(TtwWinch)
		for relation in [TtwWinching, TtwTowing]:
			var load := session.linked(wrecker, relation)
			var a := session.body_of(wrecker)
			var b := session.body_of(load) if load != null else null
			if b == null or a == null:
				continue
			var from := a.position - Vector2(0, HITCH_PX * TILT_K)
			var to := b.position - Vector2(0, HITCH_PX * TILT_K)
			var slack := 0.0
			if relation == TtwTowing:
				slack = maxf(0.0, TtwWinchSystem.rope_px(wrecker, load) - from.distance_to(to))
			var points := PackedVector2Array()
			for k in 9:
				var s := k / 8.0
				points.append(from.lerp(to, s) + Vector2(0, slack * 0.5 * 4.0 * s * (1.0 - s)))
			draw_polyline(points, CABLE, 1.0)
