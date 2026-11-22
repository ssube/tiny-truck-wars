class_name KitSimulationPolicy extends RefCounted
## Whether the world advances this frame: not while the session is busy or
## the tree is paused (the menu).

var session: KitSession

func _init(owner_session: KitSession) -> void:
	session = owner_session

func world_advances() -> bool:
	return not session.busy and not session.get_tree().paused
