extends SceneTree
const Recovery=preload("res://scripts/ember_world_recovery.gd")
class FloorMap extends "res://scripts/ember_map_loader.gd":
 var ready_floor:=true
 var queries:=0
 func _ready()->void:pass
 func _process(_dt:float)->void:pass
 func _physics_process(_dt:float)->void:pass
 func prepare_physics_destination(_point:Vector3)->bool:return ready_floor
 func physics_destination_ready(_point:Vector3)->bool:queries+=1;return ready_floor
var failures:Array[String]=[]
var returns:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
 if not value:failures.append(label);push_error(label)
func run()->void:
 var scene:=Node3D.new();root.add_child(scene)
 var map:=FloorMap.new();map.name="Map";scene.add_child(map)
 var recovery:=Recovery.new();recovery.floor_y=10.0;scene.add_child(recovery)
 recovery.character_return=func(_body:Node3D):returns+=1
 for kind in ["character","rigid"]:
  var body:PhysicsBody3D=CharacterBody3D.new() if kind=="character" else RigidBody3D.new()
  if body is CharacterBody3D:body.set_physics_process(true)
  body.position.y=20.0;scene.add_child(body)
  recovery._register_body(body)
  recovery._hold_for_support(body)
  scene.remove_child(body)
  map.queries=0
  recovery._resume_supported_bodies()
  recovery._physics_process(0.21)
  recovery.recover_body(body)
  check(map.queries==0 and returns==0,"detached body must not query/recover: "+kind)
  check(recovery._pending_support.has(body.get_instance_id()),"detached support lease retained: "+kind)
  check((not body.is_physics_processing()) if body is CharacterBody3D else body.freeze,"detached body remains held: "+kind)
  scene.add_child(body);recovery._register_body(body);recovery._resume_supported_bodies()
  check(not recovery._pending_support.has(body.get_instance_id()),"reentered body resumes support: "+kind)
  check(body.is_physics_processing() if body is CharacterBody3D else not body.freeze,"reentered body restores state: "+kind)
  body.free()
 # Both deferred entry paths must tolerate deletion before the queue drains.
 var short_lived:=RigidBody3D.new();scene.add_child(short_lived)
 var released_id:=short_lived.get_instance_id()
 recovery.body_entered.emit(short_lived)
 short_lived.free()
 await process_frame
 await process_frame
 check(not recovery._origins.has(released_id) and returns==0,"deleted deferred body is ignored")
 var live:=CharacterBody3D.new();live.position.y=0.0;scene.add_child(live)
 recovery.recover_body(live);check(returns==1,"live below-floor body still recovers")
 scene.free()
 print("WORLD_RECOVERY_DETACHED ",JSON.stringify({"pass":failures.is_empty(),"failures":failures}))
 quit(0 if failures.is_empty() else 1)
