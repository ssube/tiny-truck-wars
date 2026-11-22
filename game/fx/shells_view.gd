class_name TtwShellsView extends Node2D
## Draws shots in flight (TtwShell): a bright tracer with a short trail for a
## shell, a flame with a smoke streak for a rocket, each lifted by its height
## over the ground, with a shadow on the ground under it. Drawing only.

## How far back the trail reaches (ticks of flight).
const TRAIL_TICKS := 4.0

var session: KitSession

func _init() -> void:
	name = "Shells"
	z_index = 6

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if session == null:
		return
	var terrain := TtwGround.of(session)
	if terrain == null:
		return
	for entity in session.view([TtwShell]):
		var s: TtwShell = entity.get_component(TtwShell)
		var t := clampf(float(session.tick - s.fired_tick) / s.flight_ticks, 0.0, 1.0)
		var up := _lifted(s, t, terrain)
		# Where it was a moment ago: the trail.
		var back := _lifted(s, maxf(0.0, t - TRAIL_TICKS / float(s.flight_ticks)), terrain)
		var p := s.at(t)
		draw_circle(Vector2(p.x, p.y), 1.5, Color(0, 0, 0, 0.3))
		if s.ammo == &"rocket":
			draw_line(back, up, Color(0.85, 0.85, 0.8, 0.6), 2.0)
			draw_circle(up, 1.8, Color(1.0, 0.75, 0.3))
			draw_circle(up, 1.0, Color(1.0, 1.0, 0.85))
		else:
			draw_line(back, up, Color(1.0, 0.8, 0.35, 0.55), 1.5)
			draw_circle(up, 1.6, Color(1.0, 0.85, 0.45))
			draw_circle(up, 0.9, Color(1.0, 1.0, 0.9))

## Where share `t` of the shot's flight is drawn: over the ground, raised
## by its height above it.
func _lifted(s: TtwShell, t: float, terrain: TtwTerrain) -> Vector2:
	var p := s.at(t)
	var ground := Vector2(p.x, p.y)
	return ground - Vector2(0, maxf(0.0, p.z - TtwCombat.ground_height(terrain, ground)) * TtwCombat.TILT_K)
