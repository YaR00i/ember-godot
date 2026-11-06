@tool
extends "res://scripts/ember_interact.gd"
## Routes the existing action owner from the existing quest projection.
@export var display_name := "Собеседник"
@export var objective_scripts: Dictionary = {}
@export var completed_script_id := ""
@export var model_preset: PackedScene:
	set(value):
		model_preset = value
		if is_inside_tree(): _refresh_model.call_deferred()

var _preset_visual: Node3D


func _ready() -> void:
	super._ready()
	_refresh_model.call_deferred()


func _refresh_model() -> void:
	var parent := get_parent()
	if not is_inside_tree() or parent == null:
		return
	var original := parent.get_node_or_null("Visual") as Node3D
	if original == null:
		return
	if model_preset == null and not is_instance_valid(_preset_visual):
		return
	if is_instance_valid(_preset_visual):
		parent.remove_child(_preset_visual)
		_preset_visual.queue_free()
		_preset_visual = null
	if model_preset != null and model_preset.resource_path != original.scene_file_path:
		var model := model_preset.instantiate()
		if model is Node3D:
			_preset_visual = model
			parent.add_child(_preset_visual, false, Node.INTERNAL_MODE_BACK)
			_preset_visual.transform = original.transform
		elif model != null:
			model.free()
	original.visible = _preset_visual == null

func prompt() -> String:
	return "Поговорить: "+display_name

func runtime_route(flags_override: Variant = null) -> Dictionary:
	var progress := _progress()
	var flags: Dictionary = flags_override if flags_override is Dictionary else (progress.flags if progress != null else {})
	var projected := EmberQuestCatalog.projection(EmberQuestCatalog.definition(quest_id),flags)
	var script := completed_script_id if projected.get("status","") == "done" else ""
	if script.is_empty():
		for objective in projected.get("objectives",[]):
			if bool(objective.get("available",false)):
				script = str(objective_scripts.get(str(objective.id),""))
				break
	return {"available":not script.is_empty(),"scriptId":script,"primary":true,"reason":""}
