extends SceneTree
## The real release scope must include its worker-completion barrier.
class ReleaseWorkspace extends "res://addons/ember_import/ember_voxel_sculpt_workspace.gd":
	var waits:=0
	func _drain_volume_smooth(wait:=false)->void:
		if wait:waits+=1;OS.delay_msec(40)
	func _selected_tool_id()->int:return 0
	func _uses_volume_mask()->bool:return false
	func _clear_stroke_state()->void:_stroke_active=false
	func _set_status(_message:String,_error:=false,_color:=Color(0.66,0.74,0.84))->void:pass

func _initialize()->void:run.call_deferred()

func run()->void:
	var workspace:=ReleaseWorkspace.new()
	workspace.begin_edit_cost_trace()
	workspace._stroke_active=true
	workspace._finish_stroke()
	var report:=workspace.end_edit_cost_trace()
	var release:Dictionary=report.stages.get("outside/pointer_up",{})
	var wait:Dictionary=report.stages.get("outside/worker_completion",{})
	var pass_trace:=int(release.get("inclusive_usec",0))>=35000 and int(wait.get("inclusive_usec",0))>=35000
	var pass_state:=workspace.waits==1 and not workspace._stroke_active and workspace._resource==null
	workspace._stroke_active=true
	workspace._finish_stroke()
	pass_state=pass_state and workspace.waits==2 and not workspace._stroke_active
	print("VOXEL_RELEASE_TRACE ",JSON.stringify({"pass":pass_trace and pass_state,"release":release,"worker_completion":wait,"behavior_preserved":pass_state}))
	workspace.free()
	quit(0 if pass_trace and pass_state else 1)
