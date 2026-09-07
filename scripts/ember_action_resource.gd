@tool
class_name EmberActionResource
extends Resource
## Godot-owned envelope for one canonical Ember action-chain dictionary.

@export var action_id := ""
@export var document: Dictionary = {}


func to_document() -> Dictionary:
	var result := document.duplicate(true)
	if not action_id.strip_edges().is_empty():
		result["id"] = action_id.strip_edges()
	return result
