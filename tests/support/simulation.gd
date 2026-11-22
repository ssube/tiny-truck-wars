extends RefCounted

const Operations := preload("res://tests/support/operations.gd")

# Exact, deliberate simulation advancement, not a readiness wait. One callback
# per real physics tick, ordered after the game's physics nodes. Never call GECS
# systems manually or silently substitute the process/render clock when paused.
# `on_tick`, if given, is called once at the end of every counted tick (after the game's physics nodes have moved), so a
# test can sample or assert the state of each tick without a frame loop of its own.
static func physics_ticks(tree: SceneTree, count: int, timeout_seconds: float = 10.0, on_tick: Callable = Callable()) -> Dictionary:
	if count <= 0: return {"received": true, "success": true, "reason": ""}
	var clock := PhysicsClock.new()
	clock.remaining = count
	clock.on_tick = on_tick
	var result := await Operations.complete(clock.finished, func(): tree.root.add_child(clock), tree, timeout_seconds)
	if is_instance_valid(clock): clock.queue_free()
	return result

class PhysicsClock extends Node:
	signal finished(success: bool)
	var remaining: int
	var on_tick: Callable
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1000000
	func _physics_process(_delta: float) -> void:
		if on_tick.is_valid():
			on_tick.call()
		remaining -= 1
		if remaining == 0:
			set_physics_process(false)
			finished.emit(true)
