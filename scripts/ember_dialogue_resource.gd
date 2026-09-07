@tool
class_name EmberDialogueResource
extends Resource
## Godot-owned envelope for one canonical Ember dialogue dictionary. Graph and
## runtime keep using the same normalized fields while storage moves off JSON.

@export var dialogue_id := ""
@export var document: Dictionary = {}


func to_document() -> Dictionary:
	var result := document.duplicate(true)
	if not dialogue_id.strip_edges().is_empty():
		result["id"] = dialogue_id.strip_edges()
	return result
