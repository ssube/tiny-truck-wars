class_name TtwZoom extends RefCounted
## Camera zoom in whole steps from the mouse wheel, toward the cursor. A smooth-scrolling or
## high-resolution wheel sends several events per notch, each carrying a part
## of it (InputEventMouseButton.factor); they are added up and the zoom moves
## one step per whole notch, not one per event.

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

## Zooms `camera` to `zoom`, keeping the world point `at` (the cursor) where
## it is on the screen.
static func toward(camera: Camera2D, at: Vector2, zoom: float) -> void:
	var before := camera.zoom.x
	if is_equal_approx(before, zoom):
		return
	camera.position = at + (camera.position - at) * (before / zoom)
	camera.zoom = Vector2.ONE * zoom
