@tool
class_name EmberItemResource
extends Resource
## Godot-owned envelope for one canonical Ember item definition.

@export var item_id := ""
@export var definition: Dictionary = {}


func to_definition() -> Dictionary:
	var result := definition.duplicate(true)
	if not item_id.strip_edges().is_empty():
		result["id"] = item_id.strip_edges()
	return result
