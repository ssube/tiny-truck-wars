extends IGdUnitExecutionStage
## GdUnit 6.0.0 private seam. Delegate execute directly: no extra context or GC.
var delegate: IGdUnitExecutionStage
var record: Callable
var phase: String

func _init(stage: IGdUnitExecutionStage, sink: Callable, label: String) -> void:
	delegate = stage
	record = sink
	phase = label

func execute(context: GdUnitExecutionContext) -> void:
	var identity := {"phase": phase, "source": context.get_test_suite_path()}
	if context.test_case != null:
		identity["guid"] = context.test_case.id()._guid
	record.call("phase_start", identity)
	await delegate.execute(context)
	record.call("phase_end", identity)

func set_debug_mode(enabled: bool) -> void:
	delegate.set_debug_mode(enabled)
