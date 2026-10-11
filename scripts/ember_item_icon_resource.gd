@tool
class_name EmberItemIconResource
extends Resource
## Native envelope for the existing pixel-icon Dictionary, owned by ItemCatalog.

@export var icon_id := ""
@export var definition: Dictionary = {}


func to_definition() -> Dictionary:
	var result := definition.duplicate(true)
	if not icon_id.strip_edges().is_empty():
		result["id"] = icon_id.strip_edges()
	return result
