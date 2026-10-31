extends SceneTree
## Releasing the cover must not silently consume the travel preparation reserve.
const Patch=preload("res://scripts/ember_grass_patch.gd")
class World extends "res://scripts/world_canvas.gd":
 func _enter_tree()->void:pass
 func _ready()->void:pass
class Map extends EmberMapLoader:
 func _ready()->void:pass
class ProbePatch extends Patch:
 func _ready()->void:pass
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("DETAIL_STARTUP_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var scene:=World.new()
 var map:=Map.new();map.name="Map";scene.add_child(map)
 var canvas:=CanvasLayer.new();canvas.name="CanvasLayer";scene.add_child(canvas)
 var label:=Label.new();label.name="Gate";canvas.add_child(label)
 var projection:=EmberTerrainPilotProjection.new();map.add_child(projection)
 map._visual_surface_projection=projection
 var patch:=ProbePatch.new();patch.painted_only=true;map.add_child(patch)
 root.add_child(scene);projection.set_process(false);patch.set_process(false)
 projection.document=EmberTerrainPilotResource.new();projection.ground_style=1;projection._detail_observer_valid=true
 patch.add_to_group(&"ember_grass_patches")
 patch._detail_resident=true;patch._dirty=true;patch.position=Vector3(26*16,0,0)
 check(not scene._startup_status().ready,"unfinished invisible resident reserve keeps the loading cover")
 patch._dirty=false;patch._rebuilding=false
 check(scene._startup_status().ready,"finished reserve permits reveal")
 patch.position.x=20*16;patch._dirty=true
 check(not scene._startup_status().ready,"unfinished visible grass keeps the cover")
 patch._detail_resident=false
 check(scene._startup_status().ready,"sleeping distant world does not block reveal")
 print("DETAIL_STARTUP_GATE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 scene.free();quit(0 if errors.is_empty() else 1)
