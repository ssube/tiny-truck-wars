extends GdUnitTestSuite
## Every shader in the game fits a GL device with only 16 texture units for
## its fragment stage (the most WebGL 2 and GLES 3 promise, and what browsers
## and many laptop GPUs give). A shader over it does not compile there; this
## machine's GPU allows more, so only this count catches it.
##
## Godot does not hand out the GLSL it builds, so the count is read from the
## sources: every sampler uniform (arrays counted by their length, global and
## instance uniforms too), plus the textures Godot itself binds for a 2D
## shader: the sprite's own texture, and for a lit one its normal and
## specular maps and the light atlas (counted whether drawn lit or not).

const LIMIT := 16
## Godot's own textures in a canvas_item fragment shader.
const CANVAS_OWN_UNSHADED := 1
const CANVAS_OWN_LIT := 4

static func _shader_files(dir: String, out: PackedStringArray) -> void:
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gdshader") or name.ends_with(".gdshaderinc"):
			out.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub != "addons":
			_shader_files(dir.path_join(sub), out)

static func _without_comments(code: String) -> String:
	var block := RegEx.create_from_string("(?s)/\\*.*?\\*/")
	var line := RegEx.create_from_string("//[^\\n]*")
	return line.sub(block.sub(code, "", true), "", true)

## The sampler uniforms a shader declares, counting array lengths.
static func samplers_in(code: String) -> int:
	var uniform := RegEx.create_from_string("\\b(?:(?:global|instance)\\s+)?uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?[iu]?sampler\\w*\\s+\\w+\\s*(?:\\[\\s*(\\d+)\\s*\\])?")
	var count := 0
	for found in uniform.search_all(_without_comments(code)):
		count += int(found.get_string(1)) if not found.get_string(1).is_empty() else 1
	return count

## The texture units a shader's fragment stage may need: its own samplers
## and Godot's.
static func units_for(code: String) -> int:
	var clean := _without_comments(code)
	var own := samplers_in(clean)
	if clean.contains("shader_type canvas_item"):
		var unshaded := RegEx.create_from_string("render_mode[^;]*\\bunshaded\\b").search(clean) != null
		own += CANVAS_OWN_UNSHADED if unshaded else CANVAS_OWN_LIT
	return own

func test_every_shader_fits_sixteen_texture_units() -> void:
	var files := PackedStringArray()
	_shader_files("res://", files)
	assert_int(files.size()).is_greater(0)
	for path in files:
		var code := FileAccess.get_file_as_string(path)
		var units := units_for(code)
		assert_int(units).override_failure_message("%s needs %d texture units, over %d" % [path, units, LIMIT]).is_less_equal(LIMIT)
		# The count misses none Godot sees (globals are not in its list).
		if path.ends_with(".gdshader"):
			var listed := 0
			for u in (load(path) as Shader).get_shader_uniform_list():
				if u.type == TYPE_OBJECT:
					listed += 1
			assert_int(samplers_in(code)).override_failure_message("%s: counted fewer samplers than Godot lists" % path).is_greater_equal(listed)

func test_the_count_sees_every_kind_of_sampler() -> void:
	var code := """shader_type canvas_item;
render_mode unshaded;
// uniform sampler2D in_a_comment;
/* uniform sampler2D in_a_block; */
uniform sampler2D a : filter_linear;
uniform highp sampler2DArray b;
uniform usampler2D c;
global uniform sampler2D d;
uniform sampler2D e[3];
uniform float not_a_texture;
"""
	assert_int(samplers_in(code)).is_equal(7)
	assert_int(units_for(code)).is_equal(8)
	assert_int(units_for(code.replace("render_mode unshaded;", ""))).is_equal(11)
