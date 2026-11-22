extends GdUnitTestCIRunner
## GdUnit CI runner that records per-phase resource events and supports exact
## single-method selection (KIT_TEST_METHOD).

const ResourceStage := preload("res://kit/testing/resource_stage.gd")
var events: FileAccess
var selection_failed := false
var expected_cases := {}
var executed_cases := {}

func _ready() -> void:
	events = FileAccess.open(OS.get_environment("KIT_TEST_EVENTS"), FileAccess.WRITE)
	if events == null:
		push_error("Cannot retain resource events")
		get_tree().quit(100)
		return
	record("identity", {
		"pid": OS.get_process_id(), "engine": Engine.get_version_info(),
		"display": DisplayServer.get_name(),
		"display_mode": OS.get_environment("KIT_TEST_DISPLAY_MODE"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(),
		"source": OS.get_environment("KIT_TEST_SOURCE"),
		"method": OS.get_environment("KIT_TEST_METHOD"),
		"physics_hz": Engine.physics_ticks_per_second,
		"fixed_fps": OS.get_environment("KIT_TEST_FIXED_FPS"),
	})
	super()
	# Pinned to GdUnit 6.0.0. Do not replace stage logic, contexts, or GC.
	var suite_stage = _executor._executeStage
	_wrap_resource_stage(suite_stage, "_stage_before", "suite_setup")
	_wrap_resource_stage(suite_stage, "_stage_after", "suite_teardown")
	for stage in [suite_stage._stage_test._stage_single_test, suite_stage._stage_test._stage_fuzzer_test]:
		_wrap_resource_stage(stage, "_stage_before", "case_setup")
		_wrap_resource_stage(stage, "_stage_test", "test_body")
		_wrap_resource_stage(stage, "_stage_after", "case_teardown")

func _wrap_resource_stage(owner_stage: IGdUnitExecutionStage, property: String, label: String) -> void:
	owner_stage.set(property, ResourceStage.new(owner_stage.get(property), record, label))

func record(kind: String, data: Dictionary) -> void:
	if events == null:
		return
	var row := data.duplicate()
	row["kind"] = kind
	row["ticks_us"] = Time.get_ticks_usec()
	row["unix_seconds"] = Time.get_unix_time_from_system()
	events.store_line(JSON.stringify(row))
	events.flush()

func get_cmdline_args() -> PackedStringArray:
	# The vendor parser recognizes its own bootstrap filename only.
	var args := super()
	for index in args.size():
		if args[index] == "res://kit/testing/resource_bootstrap.gd":
			args[index] = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
	return args

func discover_tests() -> Array[GdUnitTestCase]:
	var discovered := super()
	var method := OS.get_environment("KIT_TEST_METHOD")
	var source := OS.get_environment("KIT_TEST_SOURCE")
	var selected: Array[GdUnitTestCase] = []
	var selected_rows := {}
	for test in discovered:
		if method.is_empty() or (test.suite_resource_path == source and test.test_name == method):
			if not method.is_empty() and selected_rows.has(test.attribute_index):
				selection_failed = true
				printerr("Exact test selection is ambiguous: %s::%s" % [source, method])
				return []
			selected_rows[test.attribute_index] = true
			selected.append(test)
			expected_cases[test.guid._guid] = true
			record("discovered", GdUnitTestCase.to_dict(test))
	if not method.is_empty() and selected.is_empty():
		selection_failed = true
		printerr("Exact test selection matched no cases: %s::%s" % [source, method])
	return selected

func quit(code: int) -> void:
	await super(RETURN_ERROR if selection_failed else code)

func _on_gdunit_event(event: GdUnitEvent) -> void:
	record("gdunit", event.serialize())
	if not OS.get_environment("KIT_TEST_METHOD").is_empty():
		if event.type() == GdUnitEvent.TESTCASE_BEFORE:
			executed_cases[event.guid()._guid] = true
		if event.type() == GdUnitEvent.SESSION_CLOSE and expected_cases != executed_cases:
			selection_failed = true
			printerr("Exact selection execution did not match discovered cases")
	super(event)
