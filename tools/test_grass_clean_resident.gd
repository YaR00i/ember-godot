extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class Surface extends Node3D:
	var document:=Resource.new()
	var _live_brush_active:=false
	var revision:=1
	var stamp:=1
	var ready_calls:=0
	var ready_area:=true
	var resident:=true
	var active:=true
	func detail_area_resident(_area:Rect2,_resident:bool)->bool:return resident
	func editor_detail_active()->bool:return active
	func detail_area_ready(_area:Rect2)->bool:
		ready_calls+=1;return ready_area
	func column_revision()->int:return revision
	func pending_tile_count()->int:return 1 if not ready_area else 0
class Cover extends Patch:
	var rebuilds:=0
	var fade_updates:=0
	func _ready()->void:set_process(false)
	func _surface_signature(projection:Node3D)->Array:return [projection.stamp]
	func _update_detail_fade(_projection:Node3D,_map:EmberMapLoader)->void:fade_updates+=1
	func _rebuild(_map:EmberMapLoader,projection:Node3D)->void:
		rebuilds+=1;_surface_stamp=_surface_signature(projection);_rebuilding=false
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("GRASS_CLEAN_FAIL ",label)
func _initialize()->void:run.call_deferred()
func expected_area(patch:Node3D,map:EmberMapLoader)->Rect2:
	var area:Rect2=Rect2(Vector2.ZERO,Vector2.ONE*4) if patch.painted_only else Rect2(-patch.size_blocks*0.5,patch.size_blocks)
	var low:=Vector2.INF;var high:=-low
	for point in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
		var world:Vector3=patch.to_global(Vector3(point.x*map.imported_tile_size,0,point.y*map.imported_tile_size))
		low=low.min(Vector2(world.x,world.z));high=high.max(Vector2(world.x,world.z))
	return Rect2(low,high-low).grow(0.35*map.imported_tile_size*patch.tuft_size)
func run()->void:
	var map:=QuietMap.new();root.add_child(map)
	var surface:=Surface.new();surface.name="DerivedCompactWorldTerrain";map.add_child(surface)
	var parent:=Node3D.new();map.add_child(parent)
	var patch:=Cover.new();parent.add_child(patch)
	patch._ensure_visual();patch._dirty=false;patch._transform=patch.global_transform;patch._revision=1;patch._surface_stamp=[1]
	for i in 100:patch._process(0)
	check(surface.ready_calls==0,"clean resident skips repeated terrain readiness scans")
	check(patch.fade_updates==100 and patch._detail_resident,"clean resident still updates fade and residency")
	surface.ready_area=false;surface.revision+=1
	patch._process(0)
	check(not patch._dirty and surface.ready_calls==0,"unrelated revision retains ready scatter without readiness scan")
	surface.stamp+=1;surface.revision+=1;patch._process(0)
	check(patch._dirty and not patch._rebuilding,"changed surface waits for required terrain")
	surface.ready_area=true;patch._process(0);await process_frame
	check(patch.rebuilds==1 and not patch._dirty,"changed surface rebuilds when terrain becomes ready")
	patch.position.x+=3;surface.ready_area=false;patch._process(0)
	check(patch._dirty,"transform invalidates before clean return")
	surface.ready_area=true;patch._process(0);await process_frame
	check(patch.rebuilds==2,"moved patch rebuilds")
	patch.tuft_size=1.5;patch._process(0);await process_frame
	check(patch.rebuilds==3,"authored size setter still rebuilds clean resident")
	for painted in [false,true]:
		patch.painted_only=painted
		for angle in [0.0,PI/4,-PI/4]:
			parent.rotation.y=angle;parent.scale=Vector3(1.4,1,0.7)
			for unit in [16.0,12.0]:
				map.imported_tile_size=unit;patch.size_blocks=Vector2(7,3);patch.tuft_size=2
				check(patch._world_area().is_equal_approx(expected_area(patch,map)),"bounds follow parent transform, mode, unit and extent")
				patch._world_area();patch.size_blocks=Vector2(2,8);patch.tuft_size=0.5
				check(patch._world_area().is_equal_approx(expected_area(patch,map)),"cached bounds invalidate after extent change")
	var second:=QuietMap.new();root.add_child(second);second.imported_tile_size=9
	patch.reparent(second,false)
	check(patch._world_area().is_equal_approx(expected_area(patch,second)),"reparent uses new map and unit")
	second.remove_child(patch);second.add_child(patch)
	check(patch._world_area().is_equal_approx(expected_area(patch,second)),"Undo-style reentry recomputes bounds")
	Preparation.release_projection(surface)
	map.free();second.free()
	print("GRASS_CLEAN_RESIDENT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
