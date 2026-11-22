extends RefCounted
## Event-exact completion helpers. Subscribe before triggering; a timeout only
## fails a missing event and is never a readiness proxy.

const UI := preload("res://tests/support/ui.gd")

static func complete(event: Signal, trigger: Callable, tree: SceneTree, timeout_seconds: float = 30.0) -> Dictionary:
	var observation := UI.observe(event)
	trigger.call()
	var result := await observation.wait(tree, timeout_seconds)
	return {"received": result.received, "success": result.received and result.value == true,
		"reason": "Operation timed out." if not result.received else ("" if result.value == true else "Operation reported failure.")}
