extends SceneTree
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
class QuietProjection extends TerrainProjection:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class Prop extends EmberVoxelProp:
	func _ready()->void:pass
	func _exit_tree()->void:pass
	func object_detail_safe()->bool:return true
	func object_detail_bounds()->AABB:return AABB(global_position,Vector3.ONE*16)
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var map:=QuietMap.new();root.add_child(map)
	var projection:=QuietProjection.new();map.add_child(projection)
	projection.ground_style=1;projection._detail_observer_valid=true
	map._visual_surface_projection=projection
	for i in 43:
		var prop:=Prop.new();map.add_child(prop);prop.owner=map
		prop.position.x=i*32;prop._distance_managed=true;prop._distance_ready=true;prop._distance_resident=i%2==0
		map._object_details[prop.get_instance_id()]=weakref(prop)
	map._poll_object_details()
	var expected:Dictionary=map._object_detail_pending.duplicate()
	var order:Array=map._object_detail_order.duplicate()
	map._object_detail_pending.clear();map._object_detail_order.clear()
	var calls:=0
	while calls==0 or map._object_detail_scan_cursor<map._object_detail_scan.size():
		var before:=0 if calls==0 else map._object_detail_scan_cursor
		map._poll_object_details(7);calls+=1
		check(map._object_detail_scan_cursor-before<=7,"one tick inspects at most the assigned prop count")
	check(calls==7 and map._object_detail_pending==expected and map._object_detail_order==order,"bounded scan keeps full-scan residency and near-first ordering")
	var victim:Node=map._object_details.values()[0].get_ref();var id:=victim.get_instance_id()
	victim.free();projection.detail_policy.anchor=Vector2(10000,0)
	map._poll_object_details()
	check(not map._object_details.has(id) and not map._object_detail_pending.has(id),"deleted props do not leave stale requests")
	map.free()
	print("OBJECT_RESIDENCY_SCAN ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
