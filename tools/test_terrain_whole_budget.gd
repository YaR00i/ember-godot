extends SceneTree
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Probe extends TerrainProjection:
	var observer_us:=0
	var admitted:=0
	func _ready()->void:set_process(false)
	func _poll_detail_observer(_delta:float,_force:=false)->void:OS.delay_usec(observer_us)
	func _update_ground_material_distance(_force:=false)->void:pass
	func _publication_budget_us()->int:return Preparation.FRAME_US
	func _editor_residency_allowed()->bool:return true
	func _poll_editor_surface_jobs(started:int,budget_us:=4000)->void:
		if Time.get_ticks_usec()-started<budget_us:admitted+=1
	func _poll_overviews(_started:int,_budget_us:int)->void:pass
	func _poll_mesh_lods(_started:int)->void:pass
func _initialize()->void:run.call_deferred()
func run()->void:
	var slow:=Probe.new();root.add_child(slow)
	slow.observer_us=Preparation.FRAME_US+1000;slow._process(0)
	var context=Preparation.for_projection(slow)
	var passed:bool=slow.admitted==0 and context._foreground_us>=slow.observer_us
	var quick:=Probe.new();root.add_child(quick);quick._process(0)
	passed=passed and quick.admitted==1
	print("TERRAIN_WHOLE_BUDGET ",JSON.stringify({"pass":passed,"admitted_after_exhausted_observer":slow.admitted,"observer_us":slow.observer_us,"charged_foreground_us":context._foreground_us,"normal_admission":quick.admitted}))
	Preparation.release_projection(slow);Preparation.release_projection(quick)
	slow.free();quick.free();quit(0 if passed else 1)
