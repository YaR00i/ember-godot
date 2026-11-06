extends SceneTree
## Native body-space membership, canonical floor and multi-actor/teleport return.
class QuietMap extends EmberMapLoader:
	var floor_ready:=true
	var restore_calls:=0
	var bounds_queries:=0
	func _physics_prop_area(prop:EmberVoxelProp)->Rect2:
		bounds_queries+=1;return super._physics_prop_area(prop)
	var prepare_calls:=0
	func prepare_physics_destination(point:Vector3)->bool:
		prepare_calls+=1;return super.prepare_physics_destination(point)
	func _restore_physics_near(point:Vector3)->void:
		restore_calls+=1;super._restore_physics_near(point)
	func _ready()->void:pass
	func _process(_dt:float)->void:pass
	func physics_destination_ready(_point:Vector3)->bool:return floor_ready
class Actor extends CharacterBody3D:
	func _physics_process(_dt:float)->void:pass
class PassiveActor extends CharacterBody3D:
	var simulation_required:=false
	var age:=17.0
	var calls:=0
	func runtime_simulation_required()->bool:return simulation_required
	func _physics_process(dt:float)->void:age+=dt;calls+=1
class Support extends "res://scripts/prototypes/ember_terrain_pilot_projection.gd":
	func _ready()->void:pass
	func _process(_dt:float)->void:pass
class Anchors extends Node:
	var points:Array[Vector3]=[Vector3.ZERO]
	func physics_activity_anchors(_world:World3D)->Array[Vector3]:return points
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("PHYSICS_ACTIVITY_FAIL ",label)
func _initialize()->void:run.call_deferred()
func prop_at(map:EmberMapLoader,position:Vector3)->EmberVoxelProp:
	var prop:=EmberVoxelProp.new();prop.position=position
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
	mesh.surface_set_name(0,"activity_fixture");mesh.set_meta("solid_surface_roles",PackedStringArray(["stone"]))
	var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=mesh;prop.add_child(visual)
	var body:=StaticBody3D.new();body.name="Collision";prop.add_child(body)
	var shape:=CollisionShape3D.new();shape.name="Shape";shape.shape=mesh.create_trimesh_shape();body.add_child(shape)
	map.add_child(prop);map._object_details[prop.get_instance_id()]=weakref(prop)
	return prop
func run()->void:
	var map:=QuietMap.new();map.compact_terrain=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd").base();map.world_look=0;map.compact_ground_style=1
	map.name="Map";root.add_child(map);map.set_physics_process(false)
	check(map.runtime_physics_anchors().is_empty(),"cold start without participant registry returns an empty typed list")
	var near:=prop_at(map,Vector3.ZERO);var far:=prop_at(map,Vector3(1600,0,0))
	var protected:=prop_at(map,Vector3(3200,0,0));var area:=Area3D.new();protected.add_child(area)
	var anchors:=Anchors.new();root.add_child(anchors);map.set_physics_activity_source(anchors)
	map.set_physics_process(false)
	var body:StaticBody3D=far.get_node("Collision");var shape:CollisionShape3D=body.get_node("Shape")
	var identity:=shape.shape.get_instance_id();var stamp:=far.detail_surface_signature()
	map._physics_process(0);await physics_frame;await process_frame
	check(not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"far static body leaves active physics space")
	check(PhysicsServer3D.body_get_space(near.get_node("Collision").get_rid()).is_valid(),"near static body stays active")
	check(PhysicsServer3D.body_get_space(protected.get_node("Collision").get_rid()).is_valid(),"gameplay/Area prop stays active")
	check(not shape.disabled and body.collision_layer==1 and shape.shape.get_instance_id()==identity,"canonical shape and layers retained")
	for index in 44:anchors.points.append(Vector3.ZERO)
	map._physics_process(0);map.restore_calls=0
	anchors.points[0]=Vector3(80,0,0);map._physics_process(0)
	check(map.restore_calls==1,"moving one of45 participants only restores that participant's neighbourhood")
	# One invalidation can return a whole party/NPC group simultaneously.
	var suspended_before:=map._physics_activity_suspended.size()
	anchors.points=[]
	for index in 45:anchors.points.append(Vector3(-3200-index*80,0,0))
	map.bounds_queries=0;map._physics_process(0)
	check(map.bounds_queries<=suspended_before+8,"multi-actor admission reads each suspended bound once plus bounded pruning")
	anchors.points[-1]=far.global_position;map._physics_process(0);await process_frame
	check(PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"last participant in a returning batch restores its surrounding floor")
	anchors.points=[Vector3.ZERO];map.invalidate_physics_activity();map._physics_process(0)
	check(far.detail_surface_signature()==stamp and far.surface_floor_sample(far.global_position).get("solid",false),"floor/scatter signature survives physics release")
	anchors.points.append(far.global_position);map._physics_process(0);await process_frame
	check(PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"second actor/crate immediately pins its surrounding physics")
	anchors.points=[Vector3.ZERO];map._physics_process(0);await process_frame
	check(not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"departing second actor permits release again")
	map.safe_spawn_world(far.global_position);await process_frame
	check(PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"spawn/teleport admission restores before actor appears")
	map.invalidate_physics_activity();map._physics_process(0);await process_frame
	far.get_node("Mesh").mesh.emit_changed()
	check(body.process_mode==Node.PROCESS_MODE_INHERIT and map._physics_activity_stamp.is_empty(),"physical Source edit restores body and invalidates completed scan")
	var recovery:=preload("res://scripts/ember_world_recovery.gd").new();recovery.name="WorldRecovery";root.add_child(recovery)
	var crate:=RigidBody3D.new();crate.freeze=true;crate.position=far.global_position
	root.add_child(crate);await process_frame
	crate.position=Vector3(0,-300,0);map.invalidate_physics_activity();map._physics_process(0)
	map.floor_ready=false;recovery.recover_body(crate)
	check(body.process_mode==Node.PROCESS_MODE_INHERIT and crate.global_position==far.global_position,"generic crate recovery restores destination physics synchronously")
	check(recovery._pending_support.has(crate.get_instance_id()),"recovered rigid body waits for streamed terrain")
	map.floor_ready=true;recovery._resume_supported_bodies()
	check(not recovery._pending_support.has(crate.get_instance_id()) and crate.freeze,"recovery preserves authored freeze state")
	map.floor_ready=false;var actor:=Actor.new();root.add_child(actor);await process_frame
	check(not actor.is_physics_processing(),"new NPC physics waits for its streamed floor")
	map.floor_ready=true;recovery._resume_supported_bodies()
	check(actor.is_physics_processing(),"NPC physics resumes once the same floor is ready")
	var item=preload("res://scripts/ember_world_item_3d.gd").new()
	var state:=EmberExploreState.new();state.persistence_enabled=false;state.world_items={"activity_item":{"count":1,"position":[1600,0,0],"rotation":[0,0,0]}}
	item.progress_state=state;item.position=far.global_position;root.add_child(item);item.set_physics_process(false)
	item.pickup_id="activity_item";await process_frame
	item.position=Vector3(0,-300,0);map.invalidate_physics_activity();map._physics_process(0)
	map.floor_ready=false;item.recover_from_void()
	check(body.process_mode==Node.PROCESS_MODE_INHERIT and item._waiting_for_world and item.freeze,"world-item recovery restores destination and holds gravity")
	map.floor_ready=true;item._physics_process(0)
	check(not item._waiting_for_world and not item.freeze,"world-item owner thaws after floor readiness")
	var support:=Support.new();support.document=map.compact_terrain;map.add_child(support)
	anchors.points=[Vector3(192,0,64)]
	check(support._runtime_support_tiles(null).has(Vector2i(3,1)),"terrain support includes distant active physical participants")
	await hidden_harvest_activity(map,recovery,state,anchors)
	await character_simulation_activity(map,recovery,anchors)
	anchors.points=[Vector3.ZERO]
	map.invalidate_physics_activity();map._physics_process(0);await process_frame
	far.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE);await process_frame
	check(body.process_mode==Node.PROCESS_MODE_INHERIT,"authoring save restores original body state")
	map.invalidate_physics_activity();map._physics_process(0);await process_frame
	var other:=QuietMap.new();root.add_child(other)
	far.reparent(other);await process_frame
	check(body.process_mode==Node.PROCESS_MODE_INHERIT and PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"reparent/Undo returns authored physics")
	map.set_physics_activity_source(null);map.free();other.free();anchors.free();actor.queue_free();crate.queue_free();item.queue_free();state.free();recovery.queue_free();await process_frame
	print("PHYSICS_ACTIVITY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)

func hidden_harvest_activity(map:QuietMap,recovery:Node,state:EmberExploreState,anchors:Node)->void:
	var remote:=prop_at(map,Vector3(6400,0,0))
	var remote_body:StaticBody3D=remote.get_node("Collision")
	var ordinary:=RigidBody3D.new();ordinary.position=Vector3(1200,4,128);ordinary.freeze=true;ordinary.sleeping=true
	root.add_child(ordinary);await process_frame
	var base_anchors:int=recovery.physics_activity_anchors(root.get_world_3d()).size()
	check(recovery.physics_activity_anchors(root.get_world_3d()).has(ordinary.global_position),"ordinary sleeping/frozen body remains a support anchor")
	var before:=map.prepare_calls
	var hidden=preload("res://scripts/ember_world_item_3d.gd").new()
	hidden.pickup_id="activity_hidden_apple";hidden.item_id="apple";hidden.available_flag_id="activity_harvest_revealed"
	hidden.progress_state=state;hidden.position=Vector3(6400,6,0)
	root.add_child(hidden);hidden.set_physics_process(false);await process_frame
	check(map.prepare_calls==before,"hidden remote WorldItem does not eagerly prepare physics")
	check(recovery._origins.has(hidden.get_instance_id()) and state.world_items.has(hidden.pickup_id),"hidden WorldItem retains recovery and persistent registration")
	check(recovery.physics_activity_anchors(root.get_world_3d()).size()==base_anchors,"only unavailable gated WorldItem is absent from anchors")
	map.set_physics_activity_source(recovery);map.set_physics_process(false);map.invalidate_physics_activity();map._physics_process(0);await process_frame
	check(not PhysicsServer3D.body_get_space(remote_body.get_rid()).is_valid(),"hidden harvest permits remote canonical physics release")
	map.floor_ready=false;before=map.prepare_calls
	state.set_flag(hidden.available_flag_id,true,false);hidden.refresh_availability()
	check(map.prepare_calls==before+1 and hidden.freeze and hidden._waiting_for_world,"first reveal requests support before thaw")
	check(PhysicsServer3D.body_get_space(remote_body.get_rid()).is_valid(),"remote reveal restores canonical collider synchronously")
	check(recovery.physics_activity_anchors(root.get_world_3d()).size()==base_anchors+1,"revealed item pins support while still frozen")
	hidden.queue_release_motion(Vector3(2.5,0,0),Vector3(0,1.25,0))
	for i in 8:hidden.refresh_availability();hidden._physics_process(0)
	check(hidden.freeze and hidden._release_pending and hidden.angular_velocity==Vector3.ZERO and map.prepare_calls==before+1,"waiting reveal retains one impulse and does not resubmit support each tick")
	map.floor_ready=true;hidden._physics_process(0)
	var spin:Vector3=hidden.angular_velocity
	check(not hidden.freeze and not hidden._release_pending and spin.is_equal_approx(Vector3(0,1.25,0)),"ready floor thaws and applies apple spin once")
	hidden._physics_process(0)
	check(hidden.angular_velocity.is_equal_approx(spin),"later item tick does not repeat release impulse")
	state.set_flag(hidden.available_flag_id,false,false);hidden.refresh_availability()
	check(hidden.freeze and recovery.physics_activity_anchors(root.get_world_3d()).size()==base_anchors,"hiding again freezes and removes only its support anchor")
	map.invalidate_physics_activity();map._physics_process(0);await process_frame
	check(not PhysicsServer3D.body_get_space(remote_body.get_rid()).is_valid(),"re-hidden item permits another unload")
	map.floor_ready=false;before=map.prepare_calls
	state.set_flag(hidden.available_flag_id,true,false);hidden.refresh_availability();hidden._physics_process(0)
	check(map.prepare_calls==before+1 and PhysicsServer3D.body_get_space(remote_body.get_rid()).is_valid() and hidden.freeze,"repeated reveal after unload re-prepares and waits")
	state.set_flag(hidden.available_flag_id,false,false);hidden.refresh_availability()
	before=map.prepare_calls;hidden.restore_progress()
	check(map.prepare_calls==before and hidden.freeze,"hidden save restore does not prepare remote terrain")
	state.set_flag(hidden.available_flag_id,true,false)
	state.world_items[hidden.pickup_id].position=[6464,6,0]
	hidden.queue_release_motion(Vector3.ONE*10,Vector3.ONE*10)
	before=map.prepare_calls;hidden.restore_progress();hidden.refresh_availability()
	check(map.prepare_calls==before+1 and hidden.global_position==Vector3(6464,6,0) and hidden.freeze and hidden._waiting_for_world,"available save restore requests its saved destination before gravity")
	map.floor_ready=true;hidden._physics_process(0)
	check(not hidden.freeze and not hidden._release_pending and hidden.angular_velocity==Vector3.ZERO,"available restore clears stale release impulse")
	map.set_physics_activity_source(anchors);map.set_physics_process(false)
	hidden.queue_free();ordinary.queue_free();remote.queue_free();await process_frame

func character_simulation_activity(map:QuietMap,recovery:Node,anchors:Node)->void:
	recovery.set_physics_process(false)
	var remote:=prop_at(map,Vector3(8000,0,0))
	var body:StaticBody3D=remote.get_node("Collision")
	var actor:=PassiveActor.new();actor.position=remote.global_position;actor.velocity=Vector3(2,0,3)
	var before:=map.prepare_calls
	root.add_child(actor);await process_frame;await process_frame
	check(not actor.is_physics_processing() and map.prepare_calls==before,"opt-in dormant NPC skips controller and eager floor preparation")
	var pose:=actor.global_transform;var age:=actor.age;var velocity:=actor.velocity;var calls:=actor.calls
	check(recovery._origins.has(actor.get_instance_id()) and not recovery.physics_activity_anchors(root.get_world_3d()).has(actor.global_position),"dormant NPC keeps registration without pinning floor")
	map.set_physics_activity_source(recovery);map.set_physics_process(false);map.invalidate_physics_activity();map._physics_process(0);await process_frame
	check(not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"dormant NPC permits distant static physics release")
	check(actor.global_transform==pose and actor.age==age and actor.velocity==velocity and actor.calls==calls,"dormancy retains controller state without simulating")
	map.floor_ready=false;actor.simulation_required=true;recovery._physics_process(0)
	check(not actor.is_physics_processing() and PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"wake restores collider but waits for streamed terrain before controller")
	check(recovery.physics_activity_anchors(root.get_world_3d()).has(actor.global_position),"waking NPC pins support while waiting")
	before=map.prepare_calls
	for i in 4:recovery._physics_process(0)
	check(map.prepare_calls==before and not actor.is_physics_processing(),"waiting NPC does not repeatedly request support")
	map.floor_ready=true;recovery._physics_process(0)
	check(actor.is_physics_processing() and actor.global_transform==pose and actor.age==age and actor.velocity==velocity,"ready floor resumes the same NPC state")
	await physics_frame;await process_frame
	check(actor.calls>calls,"resumed NPC controller runs again")
	actor.simulation_required=false;recovery._physics_process(0)
	map.floor_ready=false;actor.simulation_required=true;recovery._physics_process(0)
	actor.simulation_required=false;recovery._physics_process(0)
	map.floor_ready=true;recovery._physics_process(0)
	check(not actor.is_physics_processing() and not recovery.physics_activity_anchors(root.get_world_3d()).has(actor.global_position),"cancelled wake stays dormant after floor becomes ready")
	actor.simulation_required=true;recovery._physics_process(0)
	check(actor.is_physics_processing(),"second wake retains intended controller state across cancelled support wait")
	actor.set_physics_process(false);actor.simulation_required=false;recovery._physics_process(0)
	actor.simulation_required=true;recovery._physics_process(0)
	check(not actor.is_physics_processing(),"activity preserves an independently paused controller")
	var changing:CharacterBody3D=PassiveActor.new();changing.position=remote.global_position
	root.add_child(changing);await process_frame;await process_frame
	map.floor_ready=false;changing.set("simulation_required",true);recovery._physics_process(0)
	changing.set_script(Actor);recovery._physics_process(0)
	check(not changing.is_physics_processing(),"removing opt-in while waking preserves the floor hold")
	map.floor_ready=true;recovery._physics_process(0);recovery._physics_process(0)
	check(changing.is_physics_processing(),"controller without opt-in resumes after floor readiness")
	changing.queue_free();await process_frame
	actor.set_physics_process(true);actor.simulation_required=false;recovery._physics_process(0)
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var host:=Node3D.new();viewport.add_child(host)
	actor.reparent(host);await process_frame;await process_frame
	check(actor.is_physics_processing() and not recovery._origins.has(actor.get_instance_id()),"leaving the managed world restores controller ownership")
	var other=preload("res://scripts/ember_world_recovery.gd").new();host.add_child(other);await process_frame
	check(not actor.is_physics_processing(),"new world can independently acquire dormant NPC")
	host.remove_child(other);other.free()
	check(actor.is_physics_processing(),"removing the activity owner restores the prior controller tick")
	viewport.queue_free();await process_frame
	recovery._physics_process(0)
	map.set_physics_activity_source(anchors);map.set_physics_process(false);remote.queue_free();recovery.set_physics_process(true);await process_frame
