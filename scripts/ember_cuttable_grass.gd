extends "res://scripts/ember_leaf_pile.gd"
## Same cover flag/pickup/save owner; grass needs a strike rather than a footstep.
func _ready() -> void:
	super._ready()
	monitoring = false
	collision_mask = 0

func _refresh() -> void:
	super._refresh()
	var stubble := get_node_or_null("CutStubble") as Node3D
	if stubble != null:
		stubble.visible = progress_state != null and progress_state.flags.get(revealed_flag_id,false) == true

func world_hit_feedback() -> String:
	return "Трава скошена — среди стеблей что-то лежит"
