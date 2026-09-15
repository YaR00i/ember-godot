@tool
class_name EmberMaterialLibrary
extends RefCounted
## Built-in ShaderMaterial presets, not a new model schema or renderer.
## Creation returns independent parameters; assignment is owned by the caller.
const DIRECTORY := "res://materials/library/"
const PRESETS := [
	{"id":"matte", "name":"Матовая поверхность"},
	{"id":"wood", "name":"Дерево"},
	{"id":"stone", "name":"Камень"},
	{"id":"sand", "name":"Земля / песок"},
	{"id":"leaf", "name":"Листва · просвечивание"},
	{"id":"metal", "name":"Металл"},
	{"id":"glass", "name":"Стекло"},
	{"id":"crystal", "name":"Кристалл"},
	{"id":"emissive", "name":"Свечение"},
]
const PARAMETERS := {
	"base_color": TYPE_COLOR, "use_vertex_color": TYPE_BOOL,
	"surface_roughness": TYPE_FLOAT, "surface_metallic": TYPE_FLOAT,
	"highlight_strength": TYPE_FLOAT, "opacity": TYPE_FLOAT,
	"transmission_strength": TYPE_FLOAT, "transmission_color": TYPE_COLOR,
	"emission_energy": TYPE_FLOAT, "emission_color": TYPE_COLOR,
	"emission_follow_base": TYPE_BOOL,
}
const RANGES := {
	"surface_roughness":Vector2(0.04,1.0), "surface_metallic":Vector2(0.0,1.0),
	"highlight_strength":Vector2(0.0,1.0), "opacity":Vector2(0.02,1.0),
	"transmission_strength":Vector2(0.0,1.0), "emission_energy":Vector2(0.0,16.0),
}

static func preset_path(id: String) -> String:
	for preset in PRESETS:
		if preset.id == id: return DIRECTORY + id + ".tres"
	return ""

static func validate_options(options: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for parameter in options:
		if not PARAMETERS.has(parameter):
			errors.append("Unknown material parameter: " + str(parameter))
			continue
		var value = options[parameter]
		var expected: int = PARAMETERS[parameter]
		if expected == TYPE_FLOAT:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)):
				errors.append("Expected finite number: " + parameter)
			elif float(value) < RANGES[parameter].x or float(value) > RANGES[parameter].y:
				errors.append("Out of range: " + parameter)
		elif typeof(value) != expected:
			errors.append("Wrong parameter type: " + parameter)
		elif expected == TYPE_COLOR:
			var color: Color = value
			if not color.is_equal_approx(color.clamp()):
				errors.append("Expected finite 0..1 color: " + parameter)
	return errors

static func create(id: String, options: Dictionary = {}) -> ShaderMaterial:
	var path := preset_path(id)
	if path.is_empty() or not validate_options(options).is_empty(): return null
	var preset := load(path) as ShaderMaterial
	if preset == null: return null
	# Shader code is immutable/shared; per-object parameter dictionaries are not.
	var material := preset.duplicate() as ShaderMaterial
	material.resource_path = ""
	for parameter in options: material.set_shader_parameter(parameter, options[parameter])
	return material
