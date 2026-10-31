extends "res://scripts/ember_interact.gd"
var component: Node
func refresh_runtime_binding() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	if is_instance_valid(component): add_to_group("ember_interact")
func runtime_route(_flags: Variant = null) -> Dictionary:
	return {"available": is_instance_valid(component), "primary": true, "scriptId": ""}
func prompt() -> String:
	return "Переключить: " + str(component.label) if is_instance_valid(component) else "Рычаг недоступен"
func activate_from(_actor: Node3D) -> String:
	if not is_instance_valid(component): return "Рычаг недоступен"
	return component.get_parent().toggle_lever(component.component_id)
func activate() -> String: return activate_from(null)
