extends SceneTree
const Visual=preload("res://scripts/ember_hoshi_visual.gd")
const Profile=preload("res://scripts/ember_staff_profile.gd")
const Exchange=preload("res://addons/ember_animation/ember_blender_exchange.gd")
const Action=preload("res://scripts/ember_animation_action.gd")
var subject:Visual
var control:Visual
var actors:Array[CharacterBody3D]=[]
var walking:=false
var events:Array=[]
var report:={}
var max_foot:=0.0
var max_phase:=0.0
var max_wrist:=0.0
var worst_contact:Dictionary={}
class Snapshot extends SkeletonModifier3D:
	var visual:Visual
	var poses:Array[Transform3D]=[]
	var wrist_error:=0.0
	var detail:Dictionary
	func _process_modification()->void:
		var sk:=get_skeleton();poses.resize(sk.get_bone_count())
		for i in poses.size():poses[i]=sk.get_bone_global_pose(i)
		var wrist:=visual._back_weapon.get_node("RightGrip/Wrist") as Node3D
		wrist_error=sk.to_global(poses[sk.find_bone("J_Bip_R_Hand")].origin).distance_to(wrist.global_position)*1000.0
		detail={"state":visual.staff_profile_state(),"action_time":visual._profile_action_time,"draw_time":visual._staff_overlay_time,"target":str(wrist.global_position-visual.actor.global_position),"shoulder":str(sk.to_global(poses[sk.find_bone("J_Bip_R_UpperArm")].origin)-visual.actor.global_position)}
var snapshots:Array[Snapshot]=[]
func _initialize():
	Engine.max_fps=60;create_timer(35.0).timeout.connect(func():push_error("Staff test timeout");quit(3));run.call_deferred()
func tick(count:=1)->void:
	for frame in count:
		await physics_frame
		for body in actors:body.velocity=Vector3(0,-.1,1.2 if walking else 0.0);body.move_and_slide()
		subject._process(1.0/60);control._process(1.0/60)
		await process_frame
		for bone in ["J_Bip_L_UpperLeg","J_Bip_L_LowerLeg","J_Bip_L_Foot","J_Bip_R_UpperLeg","J_Bip_R_LowerLeg","J_Bip_R_Foot"]:
			var a:=snapshots[0].poses[subject.skeleton.find_bone(bone)];var b:=snapshots[1].poses[control.skeleton.find_bone(bone)]
			max_foot=maxf(max_foot,a.origin.distance_to(b.origin)*1000);assert(a.basis.is_equal_approx(b.basis),"Profile changed legs")
		max_phase=maxf(max_phase,absf(subject.motion.current_animation_position-control.motion.current_animation_position))
		if subject._profile_attached:
			if snapshots[0].wrist_error>max_wrist:worst_contact=snapshots[0].detail
			max_wrist=maxf(max_wrist,snapshots[0].wrist_error)
func make_actor(world:Node3D,x:float,library:AnimationLibrary)->Visual:
	var body:=CharacterBody3D.new();body.position.x=x;world.add_child(body);actors.append(body)
	var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.3;capsule.radius=.22;collision.shape=capsule;collision.position.y=.66;body.add_child(collision)
	var visual:=Visual.new();visual.important_character=true;body.add_child(visual);assert(visual.setup(body,1.0,library,true));visual.set_process(false)
	assert(visual.configure_staff_profile(library).is_empty())
	var snapshot:=Snapshot.new();snapshot.visual=visual;visual.skeleton.add_child(snapshot);snapshots.append(snapshot)
	return visual
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var library:AnimationLibrary=load("res://assets/local_characters/hoshi/mira_motion_editable.tres").duplicate(true);Profile.Controls.add_missing(library)
	library.set_meta(Profile.META,Profile.create(library));var profile:=Profile.read(library)
	if "--legacy-arc" in args:
		var old:=library.get_animation(Profile.Controls.DRAW).duplicate() as Animation
		old.add_marker(&"grip",old.length*.27);library.add_animation(profile.draw,old);profile.pickup_grip=.18
	var workshop:Node=load("res://assets/local_characters/hoshi/mira_animation_workshop.scn").instantiate()
	var wave:=Exchange.import_new_clip(workshop,args[0]);wave=Action.configure(wave,workshop.get_node(workshop.get("skeleton_path")),"Помахать");library.add_animation("wave_left",wave);workshop.free()
	var world:=Node3D.new();root.add_child(world);var floor:=StaticBody3D.new();world.add_child(floor);var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(100,.2,100);collider.shape=shape;collider.position.y=-.1;floor.add_child(collider)
	subject=make_actor(world,0,library);control=make_actor(world,3,library)
	subject.staff_profile_event.connect(func(event,slot,seconds):events.append({"event":event,"slot":slot,"seconds":seconds}))
	await tick(25)
	var draw:=subject.motion.get_animation(profile.draw);var marker:=draw.get_marker_time(profile.attach_marker)
	# Frozen-base boundary proof: binding rules must meet without reparent/pop.
	subject._staff_overlay_time=marker-.000001;subject._apply_staff_overlay();var before:=subject._back_weapon.transform
	subject._staff_overlay_time=marker+.000001;subject._apply_staff_overlay();var after:=subject._back_weapon.transform
	var jump:=before.origin.distance_to(after.origin)*1000
	assert(jump<.05 and before.basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion())<.0001)
	subject._staff_overlay_time=-1;subject._staff_ready=false;subject._apply_staff_overlay();events.clear()
	for mode in ["stand","walk"]:
		walking=mode=="walk";await tick(35)
		assert(subject.set_staff_equipped(true).is_empty());await tick(60)
		if max_wrist>.5:
			push_error("Pickup loses wrist contact: %.3f mm; %s"%[max_wrist,JSON.stringify(worst_contact)]);quit(1);return
		assert(subject._staff_ready and subject._profile_attached)
		assert(events.count({"event":&"grip","slot":&"equipment","seconds":marker})==1)
		assert(subject.play_staff_profile_action(&"cast").is_empty());await tick(60)
		assert(events.filter(func(e):return e.event==&"impact").size()==1)
		assert(subject._profile_action==null)
		assert(subject.play_animation_action(&"wave_left").is_empty());await tick(25);assert(subject._action_layer.current_weight>.99)
		assert(subject.play_staff_profile_action(&"cast").is_empty());await tick(5);subject.cancel_staff_profile_action();await tick(20)
		assert(events.filter(func(e):return e.event==&"impact").size()==1,"Cancelled action emitted impact")
		assert(subject._profile_action==null)
		assert(subject.set_staff_equipped(false).is_empty());await tick(60)
		assert(not subject._profile_attached and not subject._staff_ready)
		assert(events.filter(func(e):return e.event==&"release").size()==1)
		report[mode]={"events":events.duplicate(),"base_phase_error_seconds":max_phase,"leg_pose_difference_mm":max_foot,"max_wrist_target_error_mm":max_wrist}
		events.clear()
	# Reverse before pickup: no false attachment event. Then reverse after pickup.
	assert(subject.set_staff_equipped(true).is_empty());await tick(4);assert(subject.set_staff_equipped(false).is_empty());await tick(20);assert(events.is_empty())
	assert(subject.set_staff_equipped(true).is_empty());await tick(15);assert(subject._profile_attached)
	var clock:=subject._staff_overlay_time;assert(subject.set_staff_equipped(false).is_empty());assert(subject._staff_overlay_time==clock);await tick(25)
	assert(events.size()==2 and events[0].event==&"grip" and events[1].event==&"release")
	assert(subject.play_staff_profile_action(&"cast")!="")
	assert(subject.set_staff_equipped(true).is_empty());await tick(60)
	assert(not subject.play_staff_profile_action(&"strike").is_empty())
	# Routing proof only: these aliases do NOT invent strike/guard choreography.
	var edited:=profile.duplicate(true);edited.actions[&"strike"]=profile.actions[&"cast"];edited.actions[&"guard"]=profile.actions[&"cast"];library.set_meta(Profile.META,edited)
	assert(subject.configure_staff_profile(library).is_empty());events.clear()
	assert(subject.play_staff_profile_action(&"strike").is_empty());await tick(60);assert(events.size()==1 and events[0].slot==&"strike")
	events.clear();assert(subject.play_staff_profile_action(&"guard").is_empty());await tick(60);assert(events.is_empty())
	subject.skeleton.get_node("LeftGripIK").influence=1.0
	assert(not subject.play_animation_action(&"wave_left").is_empty());subject.skeleton.get_node("LeftGripIK").influence=0.0
	subject._swimming_pose=true;assert(not subject.play_staff_profile_action(&"cast").is_empty());subject._swimming_pose=false
	subject._wall_hands[0].ik.influence=1.0;assert(not subject.play_staff_profile_action(&"cast").is_empty());subject._wall_hands[0].ik.influence=0.0
	assert(max_foot<.001 and max_phase<.000001)
	assert(max_wrist<.5,"Post-IK held contact regressed")
	report.merge({"pass":true,"attachment_boundary_jump_mm":jump,"reversal_before_after_pickup":true,"cancel_suppresses_impact":true,"slot_alias_routing_only":true,"wave_coexists":true})
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("STAFF_PROFILE_RUNTIME_PASS ",JSON.stringify(report));quit()
