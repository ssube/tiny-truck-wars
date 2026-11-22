extends RefCounted

# Scope selectors to the relevant menu. Ambiguous IDs fail closed instead of
# silently choosing whichever duplicate happens to occur first in the tree.
static func find_by_test_id(root: Node, id: String, visible_only: bool = true) -> Control:
	var matches: Array[Control] = []
	_collect(root, id, visible_only, matches)
	return matches[0] if matches.size() == 1 else null

static func _collect(node: Node, id: String, visible_only: bool, matches: Array[Control]) -> void:
	if node is Control and node.get_meta(&"test_id", "") == id:
		if not visible_only or node.is_visible_in_tree(): matches.append(node)
	for child in node.get_children(): _collect(child, id, visible_only, matches)

static func press(root: Node, id: String) -> bool:
	var button := find_by_test_id(root, id) as BaseButton
	if button == null or button.disabled: return false
	# Semantic activation, not a substitute for pointer/keyboard input coverage.
	button.pressed.emit()
	return true

# Subscribe BEFORE invoking an action: validation failures can emit synchronously.
# A signal of up to four arguments is captured (several come as an array).
# run-tests.sh runs on
# simulated time (--fixed-fps), so every timeout is a budget in simulated seconds.
static func observe(event: Signal, matches: Callable = Callable()) -> Completion:
	return Completion.new(event, matches)

class Completion extends RefCounted:
	signal settled
	var received: bool = false
	var value: Variant = null
	var _argument_count: int = 0
	var _matches: Callable
	var _event: Signal

	func _init(event: Signal, matches: Callable = Callable()) -> void:
		_matches = matches
		_event = event
		for info in event.get_object().get_signal_list():
			if info.name == event.get_name(): _argument_count = info.args.size()
		assert(_argument_count <= 4, "Completion supports signals with up to four arguments.")
		_event.connect(_capture)

	func _capture(first: Variant = null, second: Variant = null, third: Variant = null, fourth: Variant = null) -> void:
		var result: Variant = first
		if _argument_count > 1:
			result = [first, second, third, fourth].slice(0, _argument_count)
		if received or (_matches.is_valid() and not _matches.call(result)): return
		received = true
		value = result
		cancel()
		settled.emit()

	func cancel() -> void:
		if is_instance_valid(_event.get_object()) and _event.is_connected(_capture):
			_event.disconnect(_capture)

	func _timeout() -> void:
		settled.emit()

	func wait(tree: SceneTree, timeout_seconds: float = 5.0) -> Dictionary:
		if not received and timeout_seconds > 0.0:
			var timer := tree.create_timer(timeout_seconds, true, false, true)
			timer.timeout.connect(_timeout, CONNECT_ONE_SHOT)
			# Resume at completion, not after another simulation tick has changed
			# the state that the caller is trying to inspect.
			await settled
			if timer.timeout.is_connected(_timeout): timer.timeout.disconnect(_timeout)
			# Expire the guard: a pending timer per wait would linger for the whole
			# timeout and read as object growth in leak/steady-state checks.
			timer.time_left = 0.0
		cancel()
		return {"received": received, "value": value}
