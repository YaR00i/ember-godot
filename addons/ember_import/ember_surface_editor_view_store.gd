@tool
class_name EmberSurfaceEditorViewStore
extends RefCounted
## Small editor-only LRU store. The plugin persists this through editor_layout.cfg;
## gameplay Resources never own camera, scope, slice or layer presentation.

const VERSION := 1
const MAX_ENTRIES := 32
const DEFAULT_STATE := {
	"yaw": deg_to_rad(45.0),
	"pitch": deg_to_rad(-48.0),
	"ortho_size": 5.8,
	"fit_margin": 1.70,
	"camera_target": Vector3.ZERO,
	"edit_region": Rect2i(),
	"slice_height": -1,
	"show_grid": true,
	"show_region": true,
	"layer_view": "combined",
}

var _states: Dictionary = {}
var _recent_keys: Array[String] = []
var _brush_profiles: Dictionary = {}


static func resource_key(resource: Resource, hinted_path: String) -> String:
	var path := hinted_path.strip_edges()
	if path.is_empty() and resource != null:
		path = resource.resource_path.strip_edges()
	if not path.is_empty():
		return path
	if resource != null and "model_id" in resource:
		var model_id := str(resource.get("model_id")).strip_edges()
		if not model_id.is_empty():
			return "model://%s" % model_id
	return ""


static func _finite_float(value: Variant, fallback: float) -> float:
	var parsed := float(value)
	return parsed if is_finite(parsed) else fallback


static func normalize(state: Dictionary) -> Dictionary:
	var target: Variant = state.get("camera_target", DEFAULT_STATE.camera_target)
	if not target is Vector3:
		target = DEFAULT_STATE.camera_target
	var target_vector := target as Vector3
	if not (
		is_finite(target_vector.x)
		and is_finite(target_vector.y)
		and is_finite(target_vector.z)
	):
		target_vector = DEFAULT_STATE.camera_target
	var region: Variant = state.get("edit_region", DEFAULT_STATE.edit_region)
	if not region is Rect2i:
		region = DEFAULT_STATE.edit_region
	var layer := str(state.get("layer_view", DEFAULT_STATE.layer_view))
	if layer not in ["combined", "floor"]:
		layer = DEFAULT_STATE.layer_view
	var yaw := _finite_float(state.get("yaw", DEFAULT_STATE.yaw), DEFAULT_STATE.yaw)
	var pitch := _finite_float(state.get("pitch", DEFAULT_STATE.pitch), DEFAULT_STATE.pitch)
	var ortho_size := _finite_float(state.get("ortho_size", DEFAULT_STATE.ortho_size), DEFAULT_STATE.ortho_size)
	var fit_margin := _finite_float(state.get("fit_margin", DEFAULT_STATE.fit_margin), DEFAULT_STATE.fit_margin)
	return {
		"yaw": wrapf(yaw, -PI, PI),
		"pitch": clampf(pitch, deg_to_rad(-88.0), deg_to_rad(88.0)),
		"ortho_size": clampf(ortho_size, 1.5, 128.0),
		"fit_margin": clampf(fit_margin, 1.0, 2.5),
		"camera_target": target_vector,
		"edit_region": region,
		"slice_height": maxi(-1, int(state.get("slice_height", DEFAULT_STATE.slice_height))),
		"show_grid": bool(state.get("show_grid", DEFAULT_STATE.show_grid)),
		"show_region": bool(state.get("show_region", DEFAULT_STATE.show_region)),
		"layer_view": layer,
	}


func remember(key: String, state: Dictionary) -> void:
	if key.is_empty():
		return
	_states[key] = normalize(state)
	_recent_keys.erase(key)
	_recent_keys.append(key)
	while _recent_keys.size() > MAX_ENTRIES:
		_states.erase(_recent_keys.pop_front())


func recall(key: String) -> Dictionary:
	if key.is_empty() or not _states.has(key):
		return {}
	_recent_keys.erase(key)
	_recent_keys.append(key)
	return (_states[key] as Dictionary).duplicate(true)


func export_data() -> Dictionary:
	return {
		"version": VERSION,
		"states": _states.duplicate(true),
		"recent_keys": _recent_keys.duplicate(),
		"brush_profiles": _brush_profiles.duplicate(true),
	}


func remember_brush_profiles(profiles: Dictionary) -> void:
	_brush_profiles = profiles.duplicate(true)


func recall_brush_profiles() -> Dictionary:
	return _brush_profiles.duplicate(true)


func import_data(data: Dictionary) -> void:
	_states.clear()
	_recent_keys.clear()
	_brush_profiles.clear()
	if int(data.get("version", 0)) != VERSION:
		return
	var incoming_profiles: Variant = data.get("brush_profiles", {})
	if incoming_profiles is Dictionary:
		_brush_profiles = (incoming_profiles as Dictionary).duplicate(true)
	var incoming: Variant = data.get("states", {})
	if not incoming is Dictionary:
		return
	var incoming_states := incoming as Dictionary
	var order: Variant = data.get("recent_keys", [])
	if order is Array:
		for raw_key in order:
			var key := str(raw_key)
			if incoming_states.has(key):
				remember(key, incoming_states[key] as Dictionary)
	for raw_key in incoming_states:
		var key := str(raw_key)
		if not _states.has(key) and incoming_states[raw_key] is Dictionary:
			remember(key, incoming_states[raw_key] as Dictionary)
