extends Area3D
## Authored gated fruit uses the existing ExploreState/WorldItem save path.
@export var dropped_flag_id := ""
var progress_state: EmberExploreState
var _shake: Tween
var _direction := Vector2.ZERO
var _dropped_now := false

func _ready() -> void:
	monitoring=false
	if progress_state==null:progress_state=get_node_or_null("/root/EmberExploreProgress")
	if progress_state!=null:progress_state.progress_changed.connect(_refresh)
	var mesh:=get_node_or_null("Tree/Mesh") as MeshInstance3D
	if mesh!=null:mesh.extra_cull_margin=maxf(mesh.extra_cull_margin,0.1)
	_finish_shake()
	_refresh()

func _refresh() -> void:
	var dropped: bool=progress_state!=null and progress_state.flags.get(dropped_flag_id,false)==true
	var fruit:=get_node_or_null("HangingFruit") as Node3D
	if fruit!=null:fruit.visible=not dropped
	collision_layer=0 if dropped_flag_id.strip_edges().is_empty() else 4

func receive_world_hit(_actor: Node3D,direction: Vector3) -> bool:
	if progress_state==null or progress_state.combat_party_locked or dropped_flag_id.strip_edges().is_empty():return false
	_dropped_now=false
	var mesh:=get_node_or_null("Tree/Mesh") as MeshInstance3D
	if mesh!=null:
		var local:=mesh.global_basis.inverse()*Vector3(direction.x,0,direction.z)
		_direction=Vector2(local.x,local.z).normalized()
		if _shake!=null:_shake.kill()
		_shake=create_tween()
		_shake.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_shake.tween_method(_shake_step,0.0,1.0,0.65)
		_shake.finished.connect(_finish_shake)
	if not progress_state.flags.get(dropped_flag_id,false):
		_dropped_now=bool(progress_state.apply_authored_flag(dropped_flag_id,true).get("changed",false))
		if _dropped_now:
			var push:=Vector3(direction.x,0,direction.z).normalized()
			for body in get_tree().get_nodes_in_group("ember_world_item_bodies"):
				if body.progress_state==progress_state and body.available_flag_id==dropped_flag_id and not body.is_queued_for_deletion():
					body.queue_release_motion(push*2.5,Vector3(push.z,0,-push.x)*1.25)
	return true

func _shake_step(phase: float) -> void:
	var mesh:=get_node_or_null("Tree/Mesh") as MeshInstance3D
	if mesh==null:return
	var amount:=sin(phase*TAU*2.2)*pow(1.0-phase,2.0)*0.12
	mesh.set_instance_shader_parameter("tree_hit_sway",Vector4(_direction.x*amount,_direction.y*amount,1.2,3.2))

func _finish_shake() -> void:
	var mesh:=get_node_or_null("Tree/Mesh") as MeshInstance3D
	if mesh!=null:mesh.set_instance_shader_parameter("tree_hit_sway",Vector4.ZERO)
	_shake=null

func _exit_tree() -> void:
	if _shake!=null:_shake.kill()
	_finish_shake()

func world_hit_feedback() -> String:
	return "С дерева упало яблоко" if _dropped_now else "Листва покачнулась"
