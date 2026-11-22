extends RefCounted
## Empties the project's static caches (the item catalogue, icon and texture
## caches and the like) so nothing is left holding resources when the process
## ends. Scripts keep their `static var`s for as long as they are loaded, and a
## cached resource points back at scripts, so without this Godot reports
## hundreds of resources "still in use at exit".
##
## Only for the very end of a run: the caches refill on next use, but shared
## objects kept in statics (palette and input-hint event hubs) are dropped.

const ROOTS := ["res://kit/", "res://game/", "res://ui/", "res://tools/"]

## Clears every static variable of every loaded project script. Returns how
## many it emptied.
static func release() -> int:
	var cleared := 0
	for entry in ProjectSettings.get_global_class_list():
		var path := str(entry.path)
		if not ROOTS.any(func(root): return path.begins_with(root)) or not ResourceLoader.has_cached(path):
			continue
		cleared += release_script(load(path) as GDScript)
	return cleared

## Empties every loaded project script (its constants, preloads and member
## types), so scripts that refer to one another in a ring let go. Godot does
## not always break such rings itself at exit, and one such ring keeps every
## script alive. Scripts with live instances are left
## alone (emptying them is refused). Returns how many were emptied.
static func unlink_scripts(skip: Array[String] = []) -> int:
	var emptied := 0
	for entry in ProjectSettings.get_global_class_list():
		var path := str(entry.path)
		if not ROOTS.any(func(root): return path.begins_with(root)) or not ResourceLoader.has_cached(path) or skip.any(func(part): return path.begins_with(part)):
			continue
		var script := load(path) as GDScript
		if script == null:
			continue
		script.source_code = "extends %s\n" % script.get_instance_base_type()
		if script.reload(false) == OK:
			emptied += 1
	return emptied

## Clears one script's statics (and its inner classes'): containers are
## emptied in place, objects let go of.
static func release_script(script: GDScript) -> int:
	if script == null:
		return 0
	var cleared := 0
	for property in script.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value: Variant = script.get(property.name)
		match typeof(value):
			TYPE_DICTIONARY, TYPE_ARRAY:
				if not value.is_read_only() and not value.is_empty():
					value.clear()
					cleared += 1
			TYPE_OBJECT:
				if value != null:
					script.set(property.name, null)
					cleared += 1
	var inner: Dictionary = script.get_script_constant_map()
	for name in inner:
		if inner[name] is GDScript and inner[name] != script:
			cleared += release_script(inner[name])
	return cleared
