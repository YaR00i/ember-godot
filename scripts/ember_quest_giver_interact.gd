@tool
extends "res://scripts/ember_interact.gd"
## Routes the existing action owner from the existing quest projection.
@export var display_name := "Собеседник"
@export var objective_scripts: Dictionary = {}
@export var completed_script_id := ""

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
