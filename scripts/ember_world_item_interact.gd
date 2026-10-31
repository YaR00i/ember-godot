extends "res://scripts/ember_interact.gd"
## The existing F interaction route, with a persistent world pickup as its target.

func prompt() -> String:
	if get_parent().carryable:
		return ("F поставить · G бросить: " if get_parent().is_carried() else "Взять: ") + str(get_parent().display_name)
	if get_parent().pushable: return "Тяжёлый ящик · толкай движением"
	return "Подобрать: " + str(get_parent().display_name)

func activate() -> String:
	return get_parent().take()

func activate_from(actor: Node3D) -> String:
	return get_parent().take(actor)

func refresh_runtime_binding() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	var body := get_parent()
	if body.progress_state != null and body.is_item_available() and int(body.progress_state.world_items.get(body.pickup_id,{"count":1}).get("count",0)) > 0:
		add_to_group("ember_interact")
	else: remove_from_group("ember_interact")
