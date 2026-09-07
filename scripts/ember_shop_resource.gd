@tool
class_name EmberShopResource
extends Resource
## Godot-owned envelope for one canonical Ember shop definition.

@export var shop_id := ""
@export var definition: Dictionary = {}


func to_definition() -> Dictionary:
	var result := definition.duplicate(true)
	if not shop_id.strip_edges().is_empty():
		result["id"] = shop_id.strip_edges()
	return result
