extends SceneTree
const Visual=preload("res://scripts/ember_hoshi_visual.gd")
const Exchange=preload("res://addons/ember_animation/ember_blender_exchange.gd")
const Action=preload("res://scripts/ember_animation_action.gd")
class Snapshot extends SkeletonModifier3D:
	var poses:Array[Transform3D]=[]
	func _process_modification_with_delta(_delta:float)->void:
		var sk:=get_skeleton();poses.resize(sk.get_bone_count())
		for i in poses.size():poses[i]=sk.get_bone_global_pose(i)
var visual:Visual
var report:={}
func _initialize()->void:
	Engine.max_fps=60;create_timer(20.0).timeout.connect(func():push_error("Action test timeout");quit(3));run.call_deferred()
func tick()->void:
	visual._process(1.0/60.0)
	await process_frame
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var workshop:Node=(load("res://assets/local_characters/hoshi/mira_animation_workshop.scn") as PackedScene).instantiate()
	var clip:=Exchange.import_new_clip(workshop,args[0]);assert(clip!=null)
	clip=Action.configure(clip,workshop.get_node(workshop.get("skeleton_path")),"Помахать")
	var library:AnimationLibrary=(load("res://assets/local_characters/hoshi/mira_motion_editable.tres") as AnimationLibrary).duplicate()
	library.add_animation("wave_left",clip);workshop.free()
	var world:=Node3D.new();root.add_child(world)
	var actor:=Node3D.new();world.add_child(actor)
	visual=Visual.new();visual.important_character=true;actor.add_child(visual)
	assert(visual.setup(actor,1.0,library,true));visual.set_process(false)
	visual._staff_ready=true;visual._staff_idle_left=100.0
	var sk:=visual.skeleton;var before:=Snapshot.new();before.name="BeforeAction";sk.add_child(before)
	assert(visual.motion.has_animation("wave_left"),"Persisted action not routed to runtime")
	for mode in ["stand","walk"]:
		visual.follower_velocity=Vector3.ZERO if mode=="stand" else Vector3(0,0,1.2)
		for i in 45:await tick()
		assert(visual.animation_action_context()==StringName(mode))
		var phase_before:=visual.motion.current_animation_position;var current:=visual.current_motion
		var error:=visual.play_animation_action("wave_left");assert(error.is_empty(),error)
		assert(visual.motion.current_animation_position==phase_before and visual.current_motion==current,"Action reset locomotion")
		var after:=Snapshot.new();after.name="AfterAction";sk.add_child(after)
		var max_off_mask:=0.0;var left_travel:=0.0;var first_left:=Vector3.ZERO;var max_weight:=0.0;var max_step:=0.0;var prior_weight:=0.0;var last_phase:=phase_before;var phase_advanced:=0.0;var max_grip:=0.0
		for frame in 140:
			await tick()
			assert(before.poses.size()==136 and after.poses.size()==136)
			for i in sk.get_bone_count():
				if String(sk.get_bone_name(i)) not in Action.settings(clip).bones:
					max_off_mask=maxf(max_off_mask,before.poses[i].origin.distance_to(after.poses[i].origin)*1000.0)
					assert(before.poses[i].basis.is_equal_approx(after.poses[i].basis),"Off-mask rotation changed")
			var hand:=after.poses[sk.find_bone("J_Bip_L_Hand")].origin
			if frame==0:first_left=hand
			left_travel=maxf(left_travel,hand.distance_to(first_left)*1000.0)
			var weight:=visual._action_layer.current_weight;max_weight=maxf(max_weight,weight);max_step=maxf(max_step,absf(weight-prior_weight));prior_weight=weight
			var phase:=visual.motion.current_animation_position;phase_advanced+=fposmod(phase-last_phase,visual.motion.current_animation_length);last_phase=phase
			var right:=after.poses[sk.find_bone("J_Bip_R_Hand")].origin
			max_grip=maxf(max_grip,right.distance_to(before.poses[sk.find_bone("J_Bip_R_Hand")].origin)*1000.0)
		assert(max_off_mask<0.001 and max_grip<0.001 and left_travel>100.0 and max_weight>.99)
		assert(visual._action_layer.clip==null and prior_weight==0.0 and phase_advanced>1.0,"Action failed to fade back while base kept moving")
		assert(max_step<.4,"Unbounded transition step")
		report[mode]={"off_mask_origin_mm":max_off_mask,"right_grip_change_mm":max_grip,"left_hand_travel_mm":left_travel,"max_weight":max_weight,"max_weight_step":max_step,"base_phase_advanced_seconds":phase_advanced,"base_clip":current,"returned_to_base":true}
		after.free()
		# Keep the observer before the persistent action modifier in the next mode.
		sk.move_child(before,visual._action_layer.get_index())
	assert(not visual._action_layer.request(clip,"swim").is_empty())
	assert(not visual._action_layer.request(clip,"stand",PackedStringArray(["left_arm"])).is_empty())
	assert(visual.play_animation_action("wave_left").is_empty())
	for i in 12:await tick()
	assert(visual._action_layer.current_weight>.5)
	visual._action_layer.update_context("swim")
	for i in 20:await tick()
	assert(visual._action_layer.clip==null,"Context change did not fade the action out")
	var invalid:=clip.duplicate();var config:Dictionary=invalid.get_meta(Action.META).duplicate();config.bones=PackedStringArray(["J_Bip_R_Hand"]);invalid.set_meta(Action.META,config)
	assert(not Action.validate(invalid,sk).is_empty())
	report["context_and_occupation_rejected"]=true;report["right_mask_rejected"]=true;report["pass"]=true
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("LEFT_ACTION_RUNTIME_PASS ",JSON.stringify(report));quit()
