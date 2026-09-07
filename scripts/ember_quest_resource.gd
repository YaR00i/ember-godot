@tool
class_name EmberQuestResource
extends Resource
## Godot-owned quest description. Runtime progress stays in EmberExploreState.flags.

@export var quest_id := ""
@export var definition: Dictionary = {}


func to_definition() -> Dictionary:
	var result := definition.duplicate(true)
	if not quest_id.strip_edges().is_empty():
		result["id"] = quest_id.strip_edges()
	return result
