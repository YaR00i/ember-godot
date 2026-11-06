extends SceneTree
const PlayerScript=preload("res://scripts/ember_player.gd")
const InteractScript=preload("res://scripts/ember_interact.gd")
class Actor extends PlayerScript:
 func _ready()->void:pass
 func _physics_process(_dt:float)->void:pass
class Action extends InteractScript:
 var queries:=0
 func _ready()->void:pass
 func runtime_available(flags_override:Variant=null)->bool:
  queries+=1
  return super.runtime_available(flags_override)
var errors:Array[String]=[]
var nodes:Array[Node]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("NEAREST_DISTANCE_FAIL ",label)
func _initialize()->void:run.call_deferred()
func action(at:Vector3,size:=Vector3.ONE)->Action:
 var area:=Action.new();area.kind="custom";area.script_id="fixture";area.position=at
 area.monitoring=false;area.collision_layer=0;area.collision_mask=0
 var shape:=CollisionShape3D.new();shape.name="Shape";var box:=BoxShape3D.new();box.size=size;shape.shape=box;area.add_child(shape)
 root.add_child(area);area.add_to_group("ember_interact");nodes.append(area);return area
func clear()->void:
 for node in nodes:node.free()
 nodes.clear()
func run()->void:
 var state:=EmberExploreState.new();state.persistence_enabled=false
 var actor:=Actor.new();actor.progress_state=state;root.add_child(actor)
 var near:=action(Vector3(3,0,0));var far:=action(Vector3(1000,0,0))
 check(actor._nearest()==near,"nearest reachable action selected")
 check(far.queries==0,"out-of-reach action never resolves story availability")
 clear()
 var locked:=action(Vector3(2,0,0));locked.condition_flag_id="ready";locked.condition_expected=true
 var allowed:=action(Vector3(5,0,0))
 check(actor._nearest()==allowed,"unavailable closer action does not block reachable fallback")
 state.flags.ready=true
 check(actor._nearest()==locked,"same-frame flag edit immediately selects newly available action")
 locked.one_shot=true;locked.completion_flag_id="done";state.flags.done=true
 check(actor._nearest()==allowed,"same-frame completion immediately removes one-shot action")
 clear()
 var large:=action(Vector3(100,0,0),Vector3(198,4,4));var point:=action(Vector3(4,0,0))
 check(actor._nearest()==large,"large volume reaches player despite distant origin")
 large.rotation.y=PI/2
 check(actor._nearest()==point,"rotated large shape uses canonical transformed distance")
 clear()
 var first:=action(Vector3(4,0,0));var tied:=action(Vector3(-4,0,0))
 check(actor._nearest()==first,"equal distances retain group order")
 first.hide();check(actor._nearest()==tied,"hidden action excluded immediately")
 first.show();first.queue_free();nodes.erase(first);check(actor._nearest()==tied,"queued-for-deletion action excluded immediately")
 clear()
 var at_limit:=action(Vector3(12.5,0,0))
 check(actor._nearest()==null,"strict distance threshold preserved")
 at_limit.position.x=12.49;check(actor._nearest()==at_limit,"just inside threshold remains reachable")
 clear()
 actor.position=Vector3(400,3,-100)
 var moved:=action(actor.position+Vector3(3,0,0));check(actor._nearest()==moved,"translated player uses current world position")
 clear();actor.position=Vector3.ZERO
 var held:=Node3D.new();held.add_child(Node3D.new());held.get_child(0).name="Pickup";root.add_child(held)
 actor.set_meta("ember_carried_item",weakref(held));check(actor._nearest()==held.get_node("Pickup"),"carried pickup retains priority without group lookup")
 actor.remove_meta("ember_carried_item");held.free()
 var far_actions:Array[Action]=[]
 for i in 256:far_actions.append(action(Vector3(100+i*3,0,50)))
 var began:=Time.get_ticks_usec()
 for i in 128:check(actor._nearest()==null,"all distant actions remain unreachable")
 var elapsed:=Time.get_ticks_usec()-began;var queries:=0
 for item in far_actions:queries+=item.queries
 check(queries==0,"distant stress does no availability routing")
 clear();actor.free();state.free();await process_frame
 print("NEAREST_DISTANCE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"distant_queries":queries,"stress128_us":elapsed}));quit(0 if errors.is_empty() else 1)
