class_name EmberDialogueSession
extends RefCounted
## Pure traversal of the existing Ember scene graph. UI and persistence stay outside.

const MAX_AUTO_STEPS := 64
const VnSceneState = preload("res://scripts/ember_vn_scene_state.gd")

var _scene: Dictionary = {}
var _steps: Dictionary = {}
var _current: Dictionary = {}
var _flags: Dictionary = {}
var _finished := true


func start(scene: Dictionary) -> bool:
	_scene = scene.duplicate(true)
	_steps.clear()
	_current.clear()
	_flags.clear()
	_finished = false
	var raw_steps: Variant = _scene.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY:
		_finished = true
		return false
	for raw_step in raw_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		var step_id := str(step.get("id", "")).strip_edges()
		if not step_id.is_empty():
			_steps[step_id] = step
	var start_id := str(_scene.get("startStepId", "")).strip_edges()
	if start_id.is_empty() and not _steps.is_empty():
		start_id = str(_steps.keys()[0])
	_enter(start_id)
	return not _finished


func advance() -> void:
	if _finished:
		return
	var kind := current_kind()
	if kind == "dialogue" or kind == "splash":
		_enter(str(_current.get("next", "")))


func choose(index: int) -> void:
	if _finished or current_kind() != "choice":
		return
	var options: Variant = _current.get("options", [])
	if typeof(options) != TYPE_ARRAY or index < 0 or index >= options.size():
		return
	var option: Variant = options[index]
	if typeof(option) != TYPE_DICTIONARY:
		return
	var option_dict: Dictionary = option
	var set_flags: Variant = option_dict.get("setFlags", {})
	if typeof(set_flags) == TYPE_DICTIONARY:
		for flag_id in set_flags:
			var value: Variant = set_flags[flag_id]
			if _is_flag_value(value):
				_flags[str(flag_id)] = value
	_enter(str(option_dict.get("next", "")))


func is_finished() -> bool:
	return _finished


func scene_name() -> String:
	return str(_scene.get("nameRu", _scene.get("id", "")))


func current_kind() -> String:
	return str(_current.get("type", ""))


func current_title() -> String:
	if current_kind() == "dialogue":
		return str(_current.get("nameRu", _current.get("speaker", scene_name())))
	return scene_name()


func current_text() -> String:
	match current_kind():
		"dialogue":
			return str(_current.get("textRu", ""))
		"choice":
			return str(_current.get("promptRu", ""))
		"splash":
			return str(_current.get("captionRu", ""))
	return ""


func current_visual_state() -> Dictionary:
	if _finished:
		return {}
	return VnSceneState.visual_state(_scene, _current)


func choice_labels() -> Array[String]:
	var result: Array[String] = []
	if current_kind() != "choice":
		return result
	var options: Variant = _current.get("options", [])
	if typeof(options) != TYPE_ARRAY:
		return result
	for option in options:
		if typeof(option) == TYPE_DICTIONARY:
			result.append(str(option.get("labelRu", option.get("id", ""))))
	return result


func flags() -> Dictionary:
	return _flags.duplicate(true)


func _enter(step_id: String) -> void:
	var next_id := step_id.strip_edges()
	for _guard in range(MAX_AUTO_STEPS):
		if next_id.is_empty() or not _steps.has(next_id):
			_finish()
			return
		var step: Dictionary = _steps[next_id]
		match str(step.get("type", "")):
			"dialogue", "choice", "splash":
				_current = step
				return
			"set_flag":
				var flag_id := str(step.get("flag", step.get("flagId", ""))).strip_edges()
				var value: Variant = step.get("value", true)
				if not flag_id.is_empty() and _is_flag_value(value):
					_flags[flag_id] = value
				next_id = str(step.get("next", ""))
			"grant_cinders":
				# Persistence owns currency. Traversal still follows the authored graph.
				next_id = str(step.get("next", ""))
			"end":
				_finish()
				return
			_:
				_finish()
				return
	_finish()


func _finish() -> void:
	_finished = true
	_current.clear()


func _is_flag_value(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_BOOL
		or typeof(value) == TYPE_STRING
		or typeof(value) == TYPE_INT
		or (typeof(value) == TYPE_FLOAT and is_finite(float(value)))
	)
