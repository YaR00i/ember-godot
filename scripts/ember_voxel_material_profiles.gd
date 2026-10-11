@tool
extends RefCounted
## Optional semantic surfaces in the existing model.material dictionary.
## No RGB inference: generators know which palette entries are bark/leaves.
const KEY := "object_surface"
const VERSION := 1
const RENDER_CONTRACT := "object-surface-v2-light-finish"
const OPTICS_RENDER_CONTRACT := "object-optics-v3-reference-finishes"
const OPTICS_DEFAULTS := {"enabled": false, "refraction_strength": 0.02, "clarity": 0.94,
	"body_opacity": 0.18, "ior": 1.45, "thickness_m": 0.65,
	"cloud_strength":0.0,"cloud_scale":3.0,"cloud_seed":0.0,
	"cloud_light":"ffffff","cloud_deep":"606080", "finish":"legacy",
	"surface_roughness":0.0,"surface_detail":0.0,"cloud_blur":1.0,"cloud_opacity":0.55,
	"absorption_strength":2.0,"crack_strength":0.0,"crack_scale":1.5,"crack_width":0.004,
	"bubble_strength":0.0,"bubble_scale":8.0}
const OPTICS_RANGES := {"refraction_strength": Vector2(0,0.08), "clarity": Vector2(0,1),
	"body_opacity": Vector2(0,1), "ior": Vector2(1,2.5), "thickness_m": Vector2(0.01,4),
	"cloud_strength":Vector2(0,1),"cloud_scale":Vector2(0.25,12),"cloud_seed":Vector2(0,100000),
	"surface_roughness":Vector2(0,1),"surface_detail":Vector2(0,0.3),"cloud_blur":Vector2(0,1),
	"cloud_opacity":Vector2(0,1),"absorption_strength":Vector2(0,5),
	"crack_strength":Vector2(0,1),"crack_scale":Vector2(0.25,8),"crack_width":Vector2(0.0005,0.05),
	"bubble_strength":Vector2(0,1),"bubble_scale":Vector2(1,32)}
# Scientific references and visual rationale live in Terrain Authoring.
# Rough exterior and internal clarity are independent; no universal white blur.
const FINISH_PROFILES := {
	"ice_clean": {"ior":1.31,"body_opacity":0.025,"clarity":0.995,"surface_roughness":0.055,
		"surface_detail":0.008,"cloud_strength":0.025,"cloud_blur":0.06,"cloud_opacity":0.10,
		"absorption_strength":0.45,"crack_strength":0.06,"bubble_strength":0.08},
	"ice_natural": {"ior":1.31,"body_opacity":0.055,"clarity":0.985,"surface_roughness":0.19,
		"surface_detail":0.055,"cloud_strength":0.16,"cloud_blur":0.12,"cloud_opacity":0.18,
		"absorption_strength":0.9,"crack_strength":0.65,"bubble_strength":0.55,"crack_width":0.004},
	"crystal_clean": {"ior":1.55,"body_opacity":0.035,"clarity":0.995,"surface_roughness":0.065,
		"surface_detail":0.008,"cloud_strength":0.03,"cloud_blur":0.06,"cloud_opacity":0.10,
		"absorption_strength":0.8,"crack_strength":0.11,"bubble_strength":0.0},
	"crystal_rough": {"ior":1.55,"body_opacity":0.08,"clarity":0.985,"surface_roughness":0.27,
		"surface_detail":0.085,"cloud_strength":0.14,"cloud_blur":0.1,"cloud_opacity":0.15,
		"absorption_strength":1.25,"crack_strength":0.48,"bubble_strength":0.06,"crack_scale":1.2},
}
const PROFILES := {
	"legacy": Vector4(0, 1.0, 0.04, 0.0),
	"stone": Vector4(1, 0.84, 0.035, 0.20),
	"bark": Vector4(2, 0.90, 0.025, 0.18),
	"foliage": Vector4(3, 0.68, 0.028, 0.05),
	"crystal": Vector4(4, 0.22, 0.07, 0.02),
	"ice": Vector4(5, 0.30, 0.018, 0.04),
	"glass": Vector4(6, 0.12, 0.04, 0.0),
}

static func assign(material: Dictionary, default_role: String, palette_roles := {}) -> void:
	material[KEY] = {"version": VERSION, "default": default_role, "palette": palette_roles.duplicate(true)}

static func base_material(material: Dictionary) -> Dictionary:
	var result := material.duplicate(true)
	result.erase(KEY)
	# Merge/stamp may remap roles, but model-wide optical settings cannot be lost
	# or silently applied to a differently configured component.
	var surface: Variant = material.get(KEY,{})
	if surface is Dictionary and surface.has("optics"):
		result[KEY] = {"version":VERSION,"default":"legacy","palette":{},"optics":optics_parameters(material)}
	return result

static func palette_role(material: Dictionary, index: int) -> String:
	var value: Dictionary = material.get(KEY, {})
	var overrides: Dictionary = value.get("palette", {})
	return str(overrides.get(str(index), overrides.get(index, value.get("default", "legacy"))))

static func set_palette_role(material: Dictionary, index: int, role: String) -> void:
	if palette_role(material, index) == role: return
	if not material.has(KEY): assign(material, "legacy")
	material[KEY].palette[str(index)] = role

static func validation_errors(material: Dictionary, palette_size: int) -> Array[String]:
	var errors: Array[String] = []
	if not material.has(KEY): return errors
	var value: Variant = material[KEY]
	if not value is Dictionary:
		errors.append("object_surface must be a dictionary")
		return errors
	if value.get("version") != VERSION: errors.append("unsupported object_surface version")
	if not PROFILES.has(value.get("default", "")): errors.append("unknown default object surface")
	var overrides: Variant = value.get("palette", {})
	if not overrides is Dictionary:
		errors.append("object_surface.palette must be a dictionary")
		return errors
	for key in overrides:
		var text := str(key)
		if not text.is_valid_int() or int(text) <= 0 or int(text) >= palette_size:
			errors.append("object surface palette index outside palette")
		if not PROFILES.has(overrides[key]): errors.append("unknown palette object surface")
	if value.has("optics"):
		var optics: Variant = value.optics
		if not optics is Dictionary: errors.append("object_surface.optics must be a dictionary")
		else:
			if optics.has("finish") and (not optics.finish is String or (str(optics.finish) != "legacy" and not FINISH_PROFILES.has(optics.finish))): errors.append("unknown optics.finish")
			if optics.has("enabled") and not optics.enabled is bool: errors.append("optics.enabled must be boolean")
			for key in OPTICS_RANGES:
				if not optics.has(key): continue
				var parameter: Variant = optics[key]
				var bounds: Vector2 = OPTICS_RANGES[key]
				if (not parameter is float and not parameter is int) or not is_finite(float(parameter)) or float(parameter) < bounds.x or float(parameter) > bounds.y:
					errors.append("invalid optics."+key)
			for key in ["cloud_light","cloud_deep"]:
				if optics.has(key) and (not optics[key] is String or not Color.html_is_valid(str(optics[key]))):
					errors.append("invalid optics."+key)
	if errors.is_empty() and value.get("optics",{}) is Dictionary and bool(value.get("optics",{}).get("enabled",false)):
		for index in range(1,palette_size):
			if palette_role(material,index) not in ["crystal","ice","glass"]:
				errors.append("optics requires crystal/ice/glass roles on the entire object")
				break
	return errors

static func optics_parameters(material: Dictionary) -> Dictionary:
	var result := OPTICS_DEFAULTS.duplicate()
	var value: Variant = material.get(KEY,{})
	if value is Dictionary and value.get("optics",{}) is Dictionary:
		var optics: Dictionary = value.get("optics",{})
		if FINISH_PROFILES.has(optics.get("finish","legacy")): result.merge(FINISH_PROFILES[optics.finish],true)
		for key in OPTICS_DEFAULTS: if optics.has(key): result[key] = optics[key]
	return result

static func palette_parameters(material: Dictionary, palette_size: int) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if not material.has(KEY) or not validation_errors(material, palette_size).is_empty(): return result
	var value: Dictionary = material[KEY]
	var overrides: Dictionary = value.get("palette", {})
	for index in palette_size:
		result.append(PROFILES[overrides.get(str(index), overrides.get(index, value.default))])
	return result
