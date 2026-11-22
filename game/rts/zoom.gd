class_name TtwZoom extends RefCounted
## Camera zoom in whole steps from the mouse wheel, toward the cursor. A smooth-scrolling or
## high-resolution wheel sends several events per notch, each carrying a part
## of it (InputEventMouseButton.factor); they are added up and the zoom moves
## one step per whole notch, not one per event.

##
## The levels depend on the view, so every screen shows about the same
## stretch of the world. They were set for the 1280×720 layout (LAYOUT): a
## game starts at zoom 3 there (427×240 world px in view) and the wheel goes
## from 1 to 5; the Mud Lab from 0.5 to 8. A larger view (TtwDisplay gives a
## 1920×1080 window one of 1920×1080) takes the whole zooms that show the
## nearest to the same: it starts at 5 (384×216) and goes from 2 to 8; 1440p
## and 4K, whose pictures are enlarged 2 and 3 times, use the layout's own.

const LAYOUT := Vector2(1280, 720)
## At the layout's size: where a game starts, and the wheel's ends.
const START := 3.0
const SKIRMISH_FAR := 1.0
const SKIRMISH_NEAR := 5.0
const LAB_FAR := 0.5
const LAB_NEAR := 8.0

## Zoom levels, smallest first.
var levels: PackedFloat32Array
var _pending: float = 0.0

func _init(steps: PackedFloat32Array) -> void:
	levels = steps

## The zoom after the wheel `event` (or `current` if it does not move it).
func apply(event: InputEventMouseButton, current: float) -> float:
	if not event.pressed:
		return current
	var notch := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		notch = 1.0
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		notch = -1.0
	else:
		return current
	# 0 where the platform does not report it: a whole notch.
	_pending += notch * (event.factor if event.factor > 0.0 else 1.0)
	if absf(_pending) < 0.999:
		return current
	var steps := int(_pending) if _pending > 0.0 else -int(-_pending)
	_pending -= steps
	var index := _nearest(current)
	return levels[clampi(index + steps, 0, levels.size() - 1)]

func _nearest(value: float) -> int:
	var best := 0
	for k in levels.size():
		if absf(levels[k] - value) < absf(levels[best] - value):
			best = k
	return best

## The whole zoom (at least 1) that shows the nearest, in a view of `view`
## px, to what `at_layout` shows on the layout. The world in view goes as
## 1 / zoom, so "nearest" is measured there; the view counts by its tighter
## side. With `half`, a zoom of 0.5 is allowed too.
static func nearest(view: Vector2, at_layout: float, half: bool = false) -> float:
	var wanted := maxf(at_layout * minf(view.x / LAYOUT.x, view.y / LAYOUT.y), 0.001)
	var candidates: Array[float] = [maxf(1.0, floorf(wanted)), maxf(1.0, ceilf(wanted))]
	if half:
		candidates.append(0.5)
	var best := 1.0
	var best_miss := INF
	for zoom in candidates:
		var miss := absf(1.0 / zoom - 1.0 / wanted)
		if miss < best_miss:
			best_miss = miss
			best = zoom
	return best

## The zoom a game starts at in a view of `view` px.
static func start(view: Vector2) -> float:
	return nearest(view, START)

## The wheel's levels in a view of `view` px: whole steps between the zooms
## nearest the layout's `far` and `near` (a `far` under 1 may give a half
## step below 1).
static func levels_for(view: Vector2, far: float, near: float) -> PackedFloat32Array:
	var first := nearest(view, far, far < 1.0)
	var last := maxf(nearest(view, near), first)
	var steps := PackedFloat32Array()
	if first < 1.0:
		steps.append(first)
	for zoom in range(int(maxf(first, 1.0)), int(last) + 1):
		steps.append(float(zoom))
	return steps

## Zooms `camera` to `zoom`, keeping the world point `at` (the cursor) where
## it is on the screen.
static func toward(camera: Camera2D, at: Vector2, zoom: float) -> void:
	var before := camera.zoom.x
	if is_equal_approx(before, zoom):
		return
	camera.position = at + (camera.position - at) * (before / zoom)
	camera.zoom = Vector2.ONE * zoom
