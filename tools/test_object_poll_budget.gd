extends SceneTree
## A costly caster must not let a count-bounded poll monopolize the frame.
class TestProjection extends "res://scripts/prototypes/ember_terrain_pilot_projection.gd":
	func _ready()->void:pass
	func _process(_dt:float)->void:pass
	func editor_detail_active()->bool:return true
class Map extends EmberMapLoader:
	var visited:Array[int]=[]
	func _ready()->void:pass
	func _process(_dt:float)->void:pass
	func _update_prop_shadow(prop:EmberVoxelProp,_protected:bool=false)->void:
		visited.append(prop.get_instance_id())
		# Model one synchronous native operation, already larger than the allowance.
		OS.delay_usec(2000)
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("OBJECT_POLL_BUDGET_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var map:=Map.new();root.add_child(map)
	var projection:=TestProjection.new();map.add_child(projection)
	map._visual_surface_projection=projection
	for index in 8:
		var prop:=EmberVoxelProp.new();map.add_child(prop)
		map._object_details[prop.get_instance_id()]=weakref(prop)
	map._poll_object_details(128)
	check(map.visited.size()==1,"one costly operation yields before the next object")
	for turn in 8:
		if map._object_detail_scan_cursor>=map._object_detail_scan.size():break
		map._poll_object_details(128)
	check(map.visited.size()==8 and map._object_detail_scan_cursor==8,"bounded turns finish the same scan")
	var unique:Dictionary={}
	for id in map.visited:unique[id]=true
	check(unique.size()==8,"no starvation or duplicate processing within the scan")
	map.visited.clear();map._poll_object_details()
	check(map.visited.size()==8,"explicit complete refresh keeps its synchronous contract")
	map.free()
	print("OBJECT_POLL_BUDGET ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
