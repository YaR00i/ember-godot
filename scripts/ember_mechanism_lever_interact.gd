extends "res://scripts/ember_interact.gd"
var component: Node
var _followers: WeakRef
func refresh_runtime_binding() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	if is_instance_valid(component): add_to_group("ember_interact")
func runtime_route(_flags: Variant = null) -> Dictionary:
	return {"available": is_instance_valid(component), "primary": true, "scriptId": ""}
func prompt() -> String:
	if is_instance_valid(component) and not str(component.companion_hero_id).is_empty():
		var followers := _party_followers()
		if followers != null and followers.assigned_to(get_parent()):
			return "Позвать спутника обратно"
		return str(component.label)
	return "Переключить: " + str(component.label) if is_instance_valid(component) else "Рычаг недоступен"
func activate_from(actor: Node3D) -> String:
	if not is_instance_valid(component): return "Рычаг недоступен"
	if not str(component.companion_hero_id).is_empty():
		var player := actor as EmberPlayer
		var followers := player.party_followers as EmberPartyFollowers if player != null else null
		if followers == null: return "Нужен спутник"
		if followers.assigned_to(get_parent()):
			followers.release_hold()
			return "Спутник возвращается"
		var state := _progress()
		if state != null and bool(state.flags.get(component.companion_completion_flag, false)):
			return "Заслонка уже зафиксирована"
		if not followers.request_hold(get_parent(), component.companion_hero_id, component.companion_completion_flag):
			return "Спутник не может подойти к рычагу"
		_followers = weakref(followers)
		return "Спутник идёт к рычагу"
	return component.get_parent().toggle_lever(component.component_id)
func activate() -> String: return activate_from(null)

func _party_followers() -> EmberPartyFollowers:
	return _followers.get_ref() as EmberPartyFollowers if _followers != null else null

func companion_holding() -> bool:
	var followers := _party_followers()
	return followers != null and followers.holding_at(get_parent())
