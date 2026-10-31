extends "res://scripts/ember_interact.gd"
## Harvest adapter; inventory and the consumed flag commit together in ExploreState.
@export var item_id := "forest_berry"
@export_range(1,99) var harvest_count := 3

func _ready() -> void:
	completion_flag_id=completion_flag_id.strip_edges()
	one_shot=true
	super._ready()

func refresh_runtime_binding() -> void:
	_bind_progress()
	var progress:=_progress()
	var available: bool=progress!=null and not completion_flag_id.is_empty() and not progress.flags.get(completion_flag_id,false)
	var fruit:=get_node_or_null("Berries") as Node3D
	if fruit!=null:fruit.visible=available
	if available:add_to_group("ember_interact")
	else:remove_from_group("ember_interact")
	collision_layer=0;collision_mask=0;monitoring=false

func prompt() -> String:
	return "Собрать лесные ягоды"

func activate() -> String:
	return activate_from(null)

func activate_from(actor: Node3D) -> String:
	var progress:=_progress()
	if progress==null or completion_flag_id.is_empty() or progress.flags.get(completion_flag_id,false):return "Ягоды уже собраны"
	var result:=progress.exchange_items({},{item_id:harvest_count},true,completion_flag_id)
	if not result.ok:return "Нет места в стопке" if result.reason=="stack_full" else "Сейчас нельзя собрать ягоды"
	if is_instance_valid(actor):
		var fruit:=get_node("Berries") as Node3D
		var visual:=fruit.duplicate() as Node3D
		get_tree().current_scene.add_child(visual);visual.global_transform=fruit.global_transform;visual.visible=true
		var effect:=preload("res://scripts/ember_item_pickup_effect.gd").new()
		get_tree().current_scene.add_child(effect);effect.play(visual,actor)
	return "Получено: лесная ягода ×%d" % harvest_count
