extends Node3D
## Presentation only: native Hoshi model and baked clips. EmberPlayer owns motion.
const AVATAR_PATH="res://assets/local_characters/hoshi/avatar.scn"
const MIRA_AVATAR_PATH := "res://assets/local_characters/hoshi/mira_avatar.scn"
const MOTION_PATH="res://assets/local_characters/hoshi/motion.res"
const PREWARM_PATH="res://shaders/ember_hoshi_prewarm.tres"
const Outline=preload("res://shaders/ember_hoshi_outline.gdshader")
const WorldToon=preload("res://shaders/ember_hoshi_toon.gdshader")
const AnimationDistanceLod=preload("res://scripts/ember_animation_distance_lod.gd")
const MIRA_STAFF_PATH := "res://scenes/props/ember_mira_trial_staff.tscn"
const MIRA_BACK_WEAPON_SOCKET_PATH := "res://scenes/props/mira_back_weapon_socket.tscn"
const MotionControls = preload("res://scripts/ember_mira_motion_controls.gd")
const StaffPoses = preload("res://scripts/ember_mira_staff_poses.gd")
const WorkshopCast = preload("res://scripts/ember_mira_workshop_cast.gd")
const CastHandModifier = preload("res://scripts/ember_mira_cast_hand_modifier.gd")
const AnimationAction = preload("res://scripts/ember_animation_action.gd")
const ActionModifier = preload("res://scripts/ember_animation_action_modifier.gd")
const StaffProfile = preload("res://scripts/ember_staff_profile.gd")
# ResourceLoader's cache does not keep an otherwise unreferenced PackedScene
# alive. Instances retain its meshes, not the scene used to construct them.
static var _avatar_scene:PackedScene
static var _motion_library:AnimationLibrary
static var _prewarm_material:ShaderMaterial
static var _resource_requests:Dictionary={}
## Hub/story heroes keep full animation and authored hair motion outside the party.
## Set on each visual; there is no roster size or active-party limit here.
@export var important_character:=false:
	set(value):
		important_character=value
		if loaded:_update_animation_importance()
var avatar:Node3D
var motion:AnimationPlayer
var skeleton:Skeleton3D
var actor: Node3D
var follower_velocity := Vector3.ZERO
var height_m:=1.48
var unit:=16.0
var speed_mps:=0.0
var _walk_clip_speed := 1.2
var _jog_clip_speed := 3.0
var _run_clip_speed := 3.0
var _use_alt_idle := false
var _use_original_walk := false
var _staff_ready := false
var _battle_staff := false
var _battle_previous_process_mode := Node.PROCESS_MODE_INHERIT
var _back_weapon_socket: Marker3D
var _back_weapon_bone := -1
var _back_weapon: Node3D
var _staff_poses: StaffPoses
class WallHand:
	var wrist: Marker3D
	var elbow: Marker3D
	var ik: TwoBoneIK3D
	var rotation: CopyTransformModifier3D
	var shoulder: int
	var arm_length: float
	var side: float
	var contact_id := 0
	var contact_point := Vector3.ZERO
	var pose := Transform3D.IDENTITY
	var clavicle: int
	var clavicle_raise := 0.0
	var clavicle_base := Quaternion.IDENTITY
	var clavicle_overlaid := false
	var support_fingers: PackedInt32Array

var _wall_hands: Array[WallHand] = []
var _cable_weight := 0.0
var _cable_phase := 0.0
var _pushed_crate: WeakRef
var _crate_push_normal := Vector3.ZERO
var _crate_push_left := 0.0
var _crate_push_contacts: Dictionary[float, Vector3] = {}
var _crate_magic_weight := 0.0
var _crate_magic_pose := Transform3D.IDENTITY
var _crate_magic_points: Array[MeshInstance3D] = []
var _crate_crouch := 0.0
var _crate_lean := 0.0
var _crate_look := 0.0
var _crate_body_clearance := Vector3.ZERO
var _contact_trace_kind := ""
var _contact_trace_frames: Array[Dictionary] = []
var _contact_trace_started := 0
var _fall_time := 0.0
var _falling := false
var _landing_requested := false
var _roll_requested := false
var _fall_peak_y := -INF
var _moving_land_left := 0.0
var _swimming_pose := false
var _swim_depth := 0.0
var _swim_visual_offset := 0.0
var _swim_entry_time := 0.0
var _terrain_step_has_support := Vector2.ZERO
var _terrain_step_weight := Vector2.ZERO
var _staff_idle_left := 0.0
var _staff_overlay_time := -1.0
var _workshop_cast_time := -1.0
var _workshop_cast: Dictionary = {}
var _workshop_authored_grip := Quaternion.IDENTITY
var _workshop_authored := false
var _workshop_cast_base: Dictionary = {}
var _workshop_right_arm: Dictionary = {}
var _workshop_ready_arm: Dictionary = {}
var _workshop_entry_arm: Dictionary = {}
var _workshop_ready_wrist: Marker3D
var _workshop_palm: Marker3D
var _workshop_staff_contact: Marker3D
var _workshop_hand_drives_staff := false
var _staff_drawing := false
var _strike_after_staff_draw := false
var _gait_braking := false
var _gait_stop_elapsed := -1.0
var _gait_stop_duration := 0.30
var _gait_support := 0
var _gait_ankles: Array[Marker3D] = []
var _gait_leg_ik: Array[TwoBoneIK3D] = []
var _gait_foot_bones: Array[int] = []
var _jog_turn_side := -1
var _jog_turn_foot := Transform3D.IDENTITY
var _jog_turn_lean := 0.0
var _jog_turn_chest := -1
var _jog_turn_chest_base := Quaternion.IDENTITY
var _jog_last_origin := Vector3.ZERO
var _jog_has_last_origin := false
var _mantle_palms: Array[Vector3] = []
var _mantle_facing := Vector3.ZERO
var _mantle_foot_start := Vector3.ZERO
var _mantle_back_ankle := Transform3D.IDENTITY
var _mantle_ankle_target := Vector3.ZERO
var _mantle_knee_target := Vector3.ZERO
var _mantle_left_knee_target := Vector3.ZERO
var _mantle_knee_weight := 0.0
var _mantle_active := false
var _mantle_step_upper_pose: Dictionary[int, Quaternion] = {}
var _right_gait_knee: Marker3D
var _mantle_knee_home := Vector3.ZERO
var _mantle_hands_first := false
var _mantle_jumps := false
var _ledge_jump_phase := 0.0
var _ledge_jump_start: Array[Vector3] = []
var _ledge_jump_landing: Array[Vector3] = []
var _jog_turn_input := Vector3.ZERO
var _jog_reverse_direction := 0.0
var _jog_reverse_rate := 0.0
var _stance_support: Array[Vector3] = []
var _stance_foot_basis: Array[Basis] = []
var _stance_toe_basis: Array[Basis] = []
var _stance_toes: Array[Marker3D] = []
var _stance_toe_bones: Array[int] = []
var _stance_rotations: Array[CopyTransformModifier3D] = []
var _stance_toe_only: Array[bool] = []
var _stance_surface_weight := 0.0
var _terrain_step_goal := Vector2.ZERO
var _terrain_step_offset := Vector2.ZERO
var _terrain_step_normals := [Vector3.UP, Vector3.UP]
var _terrain_step_contact := Vector2.ZERO
var _terrain_pelvis_offset := 0.0
var _terrain_exit_time := 0.0
var _terrain_stride := 1.0
var _terrain_travel := Vector3.FORWARD
var _terrain_head_pitch := 0.0
var _terrain_head_goal := 0.0
var _terrain_head := -1
var _terrain_shift_goal: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _terrain_shift: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_debug_mesh: ImmediateMesh
var _step_debug_view: MeshInstance3D
var _step_debug_label: Label
var _step_debug_samples: Array[Dictionary] = []
var _stance_weight := 0.0
var _stance_pelvis_offset := 0.0
var _avatar_base_y := 0.0
var _gait_foot_start: Array[Vector3] = []
var _gait_landing := Vector3.ZERO
var _gait_stop_committed := false
var _gait_waiting_contact := false
var _tempo_wait := 0.0
var _tempo_pending := ""
var _tempo_override := ""
var _tempo_contact := -1.0
var _tempo_plant_left := 0.0
var _tempo_plant_side := 0
var _tempo_plant_position := Vector3.ZERO
const STAFF_READY_SECONDS := 3.0
var current_motion:=""
var toon:Array[ShaderMaterial]=[]
var blink_targets:Array=[]
var age:=0.0
var loaded:=false
var _action_layer: ActionModifier
var _staff_profile: Dictionary = {}
var _profile_attached := false
var _profile_action: Animation
var _profile_slot: StringName
var _profile_action_time := 0.0
var _profile_action_emitted := false
var _profile_cancel := -1.0
var _profile_cancel_weight := 0.0
signal staff_profile_event(event: StringName, slot: StringName, seconds: float)
var _animation_lod=AnimationDistanceLod.new(get_instance_id())
var _animation_full_rate:=false

## Call ahead of a population reveal. Only completed background loads are read;
## scene instantiation and attachment still belong to the main thread.
static func prepare_resources(host:Node)->bool:
	if not is_instance_valid(host) or not host.is_inside_tree():return false
	if not ResourceLoader.exists(AVATAR_PATH) or not ResourceLoader.exists(MOTION_PATH):return false
	for path:String in [AVATAR_PATH,MOTION_PATH,PREWARM_PATH]:
		var ready:bool=_avatar_scene!=null if path==AVATAR_PATH else _motion_library!=null if path==MOTION_PATH else _prewarm_material!=null
		if ready or _resource_requests.has(path):continue
		var error:=ResourceLoader.load_threaded_request(path,"PackedScene" if path==AVATAR_PATH else "AnimationLibrary" if path==MOTION_PATH else "ShaderMaterial")
		if error!=OK:return false
		_resource_requests[path]=true
	while is_instance_valid(host) and host.is_inside_tree():
		for path:String in _resource_requests.keys():
			var status:=ResourceLoader.load_threaded_get_status(path)
			if status==ResourceLoader.THREAD_LOAD_FAILED or status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_resource_requests.erase(path);return false
			if status!=ResourceLoader.THREAD_LOAD_LOADED:continue
			var resource:=ResourceLoader.load_threaded_get(path)
			if path==AVATAR_PATH:_avatar_scene=resource as PackedScene
			elif path==MOTION_PATH:_motion_library=resource as AnimationLibrary
			else:_prewarm_material=resource as ShaderMaterial
			_resource_requests.erase(path)
		if _avatar_scene!=null and _motion_library!=null and _prewarm_material!=null:return true
		await host.get_tree().process_frame
	return false

func waterline_rig_segments() -> Array[Vector4]:
	var segments: Array[Vector4] = []
	if not is_instance_valid(skeleton) or not is_instance_valid(avatar):
		return segments
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	# Radii in metres. Both legs and arms keep independent sections as the pose changes.
	var links := [
		["hips", "chest", 0.115], ["chest", "neck", 0.085], ["neck", "head", 0.065],
		["head", "head", 0.092],
	]
	for side in ["left", "right"]:
		for link in [
			["UpperLeg", "LowerLeg", 0.065], ["LowerLeg", "Foot", 0.047], ["Foot", "Toes", 0.042],
			["UpperArm", "LowerArm", 0.048], ["LowerArm", "Hand", 0.036],
		]:
			links.append([side + link[0], side + link[1], link[2]])
	for link in links:
		if not bones.has(link[0]) or not bones.has(link[1]):
			continue
		for key in [link[0], link[1]]:
			var point := skeleton.to_global(skeleton.get_bone_global_pose(int(bones[key])).origin)
			segments.append(Vector4(point.x, point.y, point.z, float(link[2]) * unit))
	return segments


func setup(owner_actor: Node3D, units_per_metre: float, trial_clips: AnimationLibrary = null, use_mira_outfit: bool = false) -> bool:
	if not ResourceLoader.exists(AVATAR_PATH) or not ResourceLoader.exists(MOTION_PATH):return false
	actor=owner_actor;unit=units_per_metre
	_animation_full_rate=important_character or AnimationDistanceLod.is_party_visual(actor)
	# Synchronous compatibility for the existing one-player setup; streaming
	# callers prepare ahead, and all subsequent actors reuse the same resources.
	if _avatar_scene==null:_avatar_scene=load(AVATAR_PATH)
	if _motion_library==null:_motion_library=load(MOTION_PATH)
	var avatar_scene := _avatar_scene
	if use_mira_outfit and ResourceLoader.exists(MIRA_AVATAR_PATH):
		var mira_avatar := load(MIRA_AVATAR_PATH) as PackedScene
		if mira_avatar != null:
			avatar_scene = mira_avatar
	avatar=avatar_scene.instantiate();add_child(avatar)
	height_m=avatar.get_meta("hoshi_height",1.48)
	avatar.position=-avatar.get_meta("hoshi_center",Vector3.ZERO)-Vector3.UP*float(avatar.get_meta("hoshi_floor",0.0))
	_avatar_base_y = avatar.position.y
	scale=Vector3.ONE*unit
	motion=avatar.get_node("Motion");skeleton=avatar.find_children("*","Skeleton3D",true,false)[0]
	motion.remove_animation_library("")
	var selected_library := _motion_library
	if trial_clips != null:
		selected_library = AnimationLibrary.new()
		for name in _motion_library.get_animation_list():
			var clip := _motion_library.get_animation(name)
			if trial_clips.has_animation(name):
				var candidate := trial_clips.get_animation(name)
				if candidate.loop_mode == Animation.LOOP_LINEAR:
					clip = candidate
					if name == &"walk":
						_walk_clip_speed = maxf(0.1, float(trial_clips.get_meta("walk_speed_mps", 1.2)))
					elif name == &"run":
						_run_clip_speed = maxf(0.1, float(trial_clips.get_meta("run_speed_mps", 3.0)))
			selected_library.add_animation(name, clip)
		for name in [&"idle_alt", &"walk_adventure", &"jog"]:
			if trial_clips.has_animation(name):
				var candidate := trial_clips.get_animation(name)
				if candidate.loop_mode == Animation.LOOP_LINEAR:
					selected_library.add_animation(name, candidate)
		_jog_clip_speed = maxf(0.1, float(trial_clips.get_meta("jog_speed_mps", 3.0)))
		if trial_clips.has_animation(&"staff_strike") and ResourceLoader.exists(MIRA_STAFF_PATH):
			var strike := trial_clips.get_animation(&"staff_strike")
			if strike.loop_mode == Animation.LOOP_NONE:
				var staff_scene := load(MIRA_STAFF_PATH) as PackedScene
				selected_library.add_animation(&"staff_strike", strike)
				var staff := staff_scene.instantiate() as Node3D
				if strike.find_track(^"MiraStaff", Animation.TYPE_POSITION_3D) >= 0:
					avatar.add_child(staff)
					if ResourceLoader.exists(MIRA_BACK_WEAPON_SOCKET_PATH) or trial_clips.has_meta("back_weapon_socket"):
						_back_weapon = staff
						var bones: Dictionary = avatar.get_meta("hoshi_bones")
						_back_weapon_bone = int(bones.chest)
						var attachment := BoneAttachment3D.new()
						attachment.bone_idx = _back_weapon_bone
						skeleton.add_child(attachment)
						var socket_scene := load(MIRA_BACK_WEAPON_SOCKET_PATH) as PackedScene if ResourceLoader.exists(MIRA_BACK_WEAPON_SOCKET_PATH) else null
						_back_weapon_socket = socket_scene.instantiate() as Marker3D if socket_scene != null else null
						if _back_weapon_socket == null:
							_back_weapon_socket = Marker3D.new()
							_back_weapon_socket.name = "BackWeaponSocket"
							_back_weapon_socket.transform = trial_clips.get_meta("back_weapon_socket", Transform3D.IDENTITY)
						attachment.add_child(_back_weapon_socket)
					_install_grip_ik("Right", staff.get_node("RightGrip/Wrist"))
					_install_grip_ik("Left", staff.get_node("LeftGripFrame/LeftGrip/Wrist"))
				else:
					var hand := BoneAttachment3D.new()
					var bones: Dictionary = avatar.get_meta("hoshi_bones")
					hand.bone_idx = int(bones.rightHand)
					skeleton.add_child(hand)
					hand.add_child(staff)
				for name in [&"staff_draw", &"idle_stowed", &"idle_alt_stowed", &"walk_stowed", &"walk_adventure_stowed", &"jog_stowed", &"run_stowed",
						&"fall_stowed", &"land_stowed", &"roll_stowed", &"swim_stowed", &"swim_idle_stowed"]:
					if trial_clips.has_animation(name):
						selected_library.add_animation(name, trial_clips.get_animation(name))
	if is_instance_valid(_back_weapon):
		_staff_poses = load(StaffPoses.PATH) as StaffPoses if ResourceLoader.exists(StaffPoses.PATH) else StaffPoses.new()
		var controls := MotionControls.new()
		controls.name = String(MotionControls.CHANNELS)
		motion.get_node(motion.root_node).add_child(controls)
		for clip_name: StringName in [MotionControls.DRAW, MotionControls.DOOR, MotionControls.CABLE, MotionControls.MANTLE, &"crate_lift", &"crate_place", &"crate_throw", &"crate_push"]:
			if trial_clips.has_animation(clip_name):
				selected_library.add_animation(clip_name, trial_clips.get_animation(clip_name))
		MotionControls.add_missing(selected_library)
	if trial_clips != null:
		for name in trial_clips.get_animation_list():
			var action_clip := trial_clips.get_animation(name)
			if not AnimationAction.settings(action_clip).is_empty() and AnimationAction.validate(action_clip, skeleton).is_empty() and not selected_library.has_animation(name):
				selected_library.add_animation(name, action_clip)
	motion.add_animation_library("",selected_library)
	if motion.has_animation(&"idle_stowed") or actor.has_method("carried_crate"):
		_install_stop_ik()
	if is_instance_valid(_back_weapon) or actor.has_method("cable_hand_targets"):
		_install_wall_hand()
	set_process_unhandled_key_input(trial_clips != null)
	var styling:Dictionary=avatar.get_meta("hoshi_styling",{})
	for mesh:MeshInstance3D in avatar.find_children("*","MeshInstance3D",true,false):
		# Serialized '..' is the companion project's legacy default and may be
		# omitted from the packed file. Resolve explicitly in the target engine.
		if mesh.skin!=null:mesh.skeleton=mesh.get_path_to(skeleton)
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var both:=mesh.find_blend_shape_by_name("Fcl_EYE_Close")
		for name in (["Fcl_EYE_Close"] if both>=0 else ["Fcl_EYE_Close_L","Fcl_EYE_Close_R"]):
			var index:=mesh.find_blend_shape_by_name(name)
			if index>=0:blink_targets.append([mesh,index])
		for surface in mesh.mesh.get_surface_count():
			var original=mesh.get_active_material(surface)
			var source_toon:bool=original is ShaderMaterial and original.get_meta("hoshi_toon",false)
			var facial:bool=original is BaseMaterial3D and original.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED
			if not source_toon and not facial:continue
			var mat:ShaderMaterial=original.duplicate() if source_toon else ShaderMaterial.new()
			mat.shader=WorldToon
			if facial:
				mat.set_shader_parameter("base_texture",original.albedo_texture)
				mat.set_shader_parameter("base_factor",original.albedo_color)
				mat.set_shader_parameter("alpha_cutoff",original.alpha_scissor_threshold)
				mat.set_shader_parameter("shadow_strength",0.73)
			mat.set_shader_parameter("hoshi_edge_strength",styling.get("edge_strength",0.16));mat.set_shader_parameter("hoshi_edge_width",styling.get("edge_width",0.4))
			var edge:Color=styling.get("edge_color",Color.WHITE);mat.set_shader_parameter("hoshi_edge_color",Vector3(edge.r,edge.g,edge.b))
			var outline:=ShaderMaterial.new();outline.shader=Outline
			outline.set_shader_parameter("base_texture",mat.get_shader_parameter("base_texture"))
			outline.set_shader_parameter("alpha_cutoff",mat.get_shader_parameter("alpha_cutoff"))
			var color:Color=styling.get("outline_color",Color(0.2,0.16,0.27));outline.set_shader_parameter("outline_color",Vector3(color.r,color.g,color.b))
			outline.set_shader_parameter("outline_strength",styling.get("outline_strength",0.45));outline.set_shader_parameter("outline_width",styling.get("outline_width",0.35))
			if source_toon and original.get_meta("hoshi_toon_outline", true):
				mat.next_pass=outline
			mesh.set_surface_override_material(surface,mat);toon.append(mat)
	if is_instance_valid(_back_weapon):
		_install_workshop_hand_attachment()
	if not Engine.is_editor_hint():
		motion.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_animation_lod.bind_skeleton(skeleton,_animation_full_rate)
	loaded = true
	if OS.has_feature("editor") and not Engine.is_editor_hint() and actor.has_method("door_is_swinging"):
		skeleton.skeleton_updated.connect(_record_contact_frame)
	current_motion = _select_motion()
	motion.play(current_motion)
	return true

func _install_grip_ik(side: String, wrist: Node3D) -> void:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var prefix := side.to_lower()
	var hint := Marker3D.new()
	hint.name = side + "ElbowHint"
	avatar.add_child(hint)
	var ik := _install_arm_ik(side + "GripIK", prefix, wrist, hint)
	ik.influence = 1.0 if side == "Right" else 0.0
	_install_bone_rotation(side + "GripRotation", bones[prefix + "Hand"], wrist).influence = ik.influence

func _install_arm_ik(label: String, prefix: String, wrist: Node3D, hint: Node3D) -> TwoBoneIK3D:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var ik := TwoBoneIK3D.new()
	ik.name = label
	ik.influence = 0.0
	ik.setting_count = 1
	skeleton.add_child(ik)
	ik.set_root_bone_name(0, skeleton.get_bone_name(bones[prefix + "UpperArm"]))
	ik.set_middle_bone_name(0, skeleton.get_bone_name(bones[prefix + "LowerArm"]))
	ik.set_end_bone_name(0, skeleton.get_bone_name(bones[prefix + "Hand"]))
	ik.set_extend_end_bone(0, false)
	ik.set_target_node(0, ik.get_path_to(wrist))
	ik.set_pole_node(0, ik.get_path_to(hint))

	return ik

func _install_wall_hand() -> void:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	for side: String in ["Right", "Left"]:
		var prefix := side.to_lower()
		var hand := WallHand.new()
		hand.side = -1.0 if side == "Right" else 1.0
		hand.shoulder = int(bones[prefix + "UpperArm"])
		hand.clavicle = skeleton.get_bone_parent(hand.shoulder)
		var wrist_bone: int = bones[prefix + "Hand"]
		var finger_prefix := "J_Bip_R_" if side == "Right" else "J_Bip_L_"
		for digit in ["Index", "Middle", "Ring", "Little"]:
			for joint in [1, 2, 3]:
				var finger := skeleton.find_bone(finger_prefix + digit + str(joint))
				if finger >= 0:
					hand.support_fingers.append(finger)
		hand.arm_length = skeleton.get_bone_rest(bones[prefix + "LowerArm"]).origin.length()
		hand.arm_length += skeleton.get_bone_rest(wrist_bone).origin.length()
		hand.wrist = Marker3D.new()
		hand.wrist.name = side + "WallWrist"
		avatar.add_child(hand.wrist)
		hand.elbow = Marker3D.new()
		avatar.add_child(hand.elbow)
		hand.ik = _install_arm_ik(side + "WallIK", prefix, hand.wrist, hand.elbow)
		hand.rotation = _install_bone_rotation(side + "WallRotation", wrist_bone, hand.wrist)
		_wall_hands.append(hand)

func supports_crate_pose() -> bool:
	return _wall_hands.size() == 2

func note_crate_push(body: Node3D, normal: Vector3) -> void:
	normal = body.heavy_crate_face(actor.global_position) if body.has_method("heavy_crate_face") else normal
	if _crate_push_left <= 0.0 or _pushed_crate == null or _pushed_crate.get_ref() != body or not normal.is_equal_approx(_crate_push_normal):
		_crate_push_contacts.clear()
	_pushed_crate = weakref(body)
	_crate_push_normal = normal
	_crate_push_left = 0.12

func prepare_crate_magic(direction: Vector3) -> bool:
	if not has_trial_staff() or staff_strike_active():
		return false
	if _staff_overlay_time < 0.0 and staff_needs_draw():
		begin_staff_action(direction, false)
	if not _staff_ready or _staff_overlay_time >= 0.0:
		return false
	_staff_idle_left = STAFF_READY_SECONDS
	return true

func face_crate(direction: Vector3) -> void:
	rotation.y = atan2(direction.x, direction.z)

func _apply_crate_magic(box: CollisionShape3D, body: Node3D, pushing: bool, dt: float) -> void:
	var active := box != null and _staff_ready and _staff_overlay_time < 0.0 and not staff_strike_active()
	_crate_magic_weight = move_toward(_crate_magic_weight, 1.0 if active else 0.0, dt * 8.0)
	for point: MeshInstance3D in _crate_magic_points:
		point.hide()
	if _crate_magic_weight <= 0.0 or not _staff_ready or _staff_overlay_time >= 0.0:
		return
	var staff := _back_weapon
	if not active:
		staff.transform = staff.transform.interpolate_with(_crate_magic_pose, _crate_magic_weight)
		return
	var cast: Transform3D = _staff_poses.staff_pose(_staff_chest_motion(), true)
	var hold := cast.origin + cast.basis.z * _staff_poses.grip
	var wrist := staff.get_node("RightGrip/Wrist") as Marker3D
	var aim := Vector3.BACK
	var target := Vector3.ZERO
	if active:
		target = box.global_position
		if pushing:
			var local_normal := box.global_basis.inverse() * _crate_push_normal
			var face := Vector3(signf(local_normal.x), 0, 0) if absf(local_normal.x) > absf(local_normal.z) else Vector3(0, 0, signf(local_normal.z))
			var half: Vector3 = box.shape.size * 0.5
			target = box.to_global(face * half)
			target += global_basis.x.normalized() * (-0.20 * unit)
			target.y = clampf(avatar.to_global(Vector3(0, 1.75, 0)).y, box.global_position.y - half.y * 0.8, box.global_position.y + half.y * 0.8)
		aim = cast.basis.z
		if not pushing and body.crate_action == "lift":
			aim = aim.lerp((avatar.to_local(target) - hold).normalized(), 1.0 - crate_motion_weight("lift", &"aim_forward", body.crate_action_phase, smoothstep(0.0, 0.8, body.crate_action_phase)))
		if body.crate_action == "throw":
			var release := crate_motion_weight("throw", &"aim_forward", body.crate_action_phase, smoothstep(0.15, 0.8, body.crate_action_phase))
			aim = aim.normalized().lerp(Vector3.BACK, release)
	else:
		aim = Vector3.BACK
	if aim.length_squared() > 0.001:
		aim = Vector3(0, 0.97, 0.24).normalized() if pushing and active else aim.normalized()
		if active and not pushing:
			var bottom := box.to_global(Vector3.DOWN * box.shape.size.y * 0.5).y
			var space_below := (bottom - avatar.to_global(hold).y) / unit
			var rise_limit := (space_below - 0.06) / (1.02 - wrist.position.z)
			if space_below > 0.05 and aim.y > rise_limit:
				var horizontal := Vector3(aim.x, 0.0, aim.z).normalized()
				if horizontal.is_zero_approx():
					horizontal = Vector3.BACK
				var rise := clampf(rise_limit, 0.0, 0.9)
				aim = horizontal * sqrt(1.0 - rise * rise) + Vector3.UP * rise
		var up := Vector3.UP if absf(aim.y) < 0.95 else Vector3.BACK
		var orientation := Basis.looking_at(aim, up, true)
		if pushing and active:
			hold = avatar.to_local(target + _crate_push_normal * (0.11 * unit)) - orientation * Vector3(-0.067, -0.018, 0.96)
		else:
			if active and body.crate_action in ["lift", "place"]:
				orientation = _clear_crate_shaft(box, hold, orientation, wrist.position.z)
			hold -= orientation.z * wrist.position.z
		_crate_magic_pose = Transform3D(orientation, hold)
		staff.transform = staff.transform.interpolate_with(_crate_magic_pose, _crate_magic_weight)
	(avatar.get_node("RightElbowHint") as Node3D).position = Vector3(-0.48, 0.87, -0.05)
	if active and pushing:
		_show_crate_force(staff.to_global(Vector3(-0.067, -0.018, 0.96)), target)

func _clear_crate_shaft(box: CollisionShape3D, hand: Vector3, orientation: Basis, grip: float) -> Basis:
	var half: Vector3 = box.shape.size * 0.5
	var bounds := AABB(-half, half * 2.0).grow(0.3)
	for index in 5:
		var hold := hand - orientation.z * grip
		var foot := hold + orientation * Vector3(-0.067, -0.018, -0.24)
		var tip := hold + orientation * Vector3(-0.067, -0.018, 1.02)
		if bounds.intersects_segment(box.to_local(avatar.to_global(foot)), box.to_local(avatar.to_global(tip))) == null:
			break
		orientation = orientation.rotated(Vector3.UP, -0.28)
	return orientation

func _show_crate_force(start: Vector3, target: Vector3) -> void:
	if _crate_magic_points.is_empty():
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.52, 0.76, 1.0)
		var sphere := SphereMesh.new()
		sphere.radius = 0.026
		sphere.height = 0.052
		sphere.radial_segments = 6
		sphere.rings = 3
		for index in 3:
			var point := MeshInstance3D.new()
			point.mesh = sphere
			point.material_override = material
			point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(point)
			_crate_magic_points.append(point)
	if (target - start).dot(-_crate_push_normal) <= 0.0:
		return
	for index in _crate_magic_points.size():
		var point := _crate_magic_points[index]
		var phase := fposmod(age * 4.0 + index / 3.0, 1.0)
		point.global_position = start.lerp(target, phase)
		point.scale = Vector3.ONE * lerpf(0.6, 1.4, sin(PI * phase))
		point.show()

func _apply_crate_pose(dt: float) -> bool:
	if _wall_hands.is_empty() or not actor.has_method("carried_crate"):
		return false
	_crate_push_left = maxf(0.0, _crate_push_left - dt)
	var body: Node3D = actor.carried_crate() if supports_crate_pose() else null
	var pushing := body == null and _crate_push_left > 0.0 and _pushed_crate != null
	if pushing:
		body = _pushed_crate.get_ref() as Node3D
	var box: CollisionShape3D = body.crate_box() if is_instance_valid(body) and not _swimming_pose else null
	var magic: bool = actor.uses_crate_magic()
	if magic:
		if box != null and not pushing:
			prepare_crate_magic(actor.interaction_forward())
		_apply_crate_magic(box, body, pushing, dt)
		# The existing overhead trajectory still drives the crate. Mira's hand
		# follows the staff grip throughout the spell.
		if box != null:
			for hand: WallHand in _wall_hands:
				hand.ik.influence = move_toward(hand.ik.influence, 0.0, dt * 12.0)
				hand.rotation.influence = hand.ik.influence
		return box != null
	var crouch := 0.0
	var lean := 0.0
	var brace := 0.0
	if box != null:
		var phase: float = body.crate_action_phase
		brace = 0.0 if pushing else 1.0
		match body.crate_action:
			"lift":
				crouch = smoothstep(0.0, 0.35, phase) * (1.0 - smoothstep(0.35, 1.0, phase))
				brace = smoothstep(0.65, 1.0, phase)
			"place":
				crouch = smoothstep(0.0, 0.85, phase)
				brace = 1.0 - smoothstep(0.0, 0.40, phase)
			"throw":
				lean = 0.30 * smoothstep(0.48, 1.0, phase) - 0.19 * sin(PI * smoothstep(0.0, 0.55, phase))
				brace = 1.0 - smoothstep(0.0, 0.40, phase)
		if pushing:
			lean = 0.26
	_crate_crouch = lerpf(_crate_crouch, crouch, 1.0 - exp(-16.0 * dt))
	_crate_lean = lerpf(_crate_lean, lean + crouch * 0.36 - brace * 0.13, 1.0 - exp(-22.0 * dt))
	_crate_look = lerpf(_crate_look, brace * deg_to_rad(32.0), 1.0 - exp(-12.0 * dt))
	if absf(_crate_lean) > 0.001:
		if pushing:
			var chest: int = avatar.get_meta("hoshi_bones").chest
			var pose := skeleton.get_bone_pose_rotation(chest)
			skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, _crate_lean) * pose)
		else:
			_bend_mantle_chest(_crate_lean)
	if absf(_crate_look) > 0.001:
		_rotate_mantle_pose(_terrain_head, _crate_look, Vector3.UP)
	if _crate_crouch > 0.005 and actor.is_on_floor():
		var feet: Array[Vector3] = []
		for bone in _gait_foot_bones:
			feet.append(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))
		avatar.position.y -= _crate_crouch * 0.30
		for side in feet.size():
			_gait_ankles[side].global_position = feet[side]
			_gait_leg_ik[side].influence = maxf(_gait_leg_ik[side].influence, smoothstep(0.0, 0.2, _crate_crouch))
	if box == null:
		for hand: WallHand in _wall_hands:
			_raise_crate_clavicle(hand, 0.0, dt)
		return false
	var half: Vector3 = box.shape.size * 0.5
	var forward := global_basis.z.normalized()
	if pushing:
		forward = -_crate_push_normal
		face_crate(forward)
	else:
		var direction: Vector3 = actor.interaction_forward()
		rotation.y = atan2(direction.x, direction.z)
		forward = direction
	for hand: WallHand in _wall_hands:
		var clearance := 0.022
		var overhead := 0.0
		var normal: Vector3 = body.heavy_crate_face(actor.global_position) if not pushing else _crate_push_normal
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
		var rear_height := clampf(box.to_local(shoulder - Vector3.UP * unit * 0.14).y, -half.y * 0.84, half.y * 0.84)
		var face := (box.global_basis.inverse() * normal).normalized()
		var across_face := Vector3.UP.cross(face)
		if (box.global_basis * across_face).dot(global_basis.x) < 0.0:
			across_face = -across_face
		var side_offset := across_face * half * hand.side * 0.36
		var point := box.to_global(face * half + side_offset + Vector3.UP * rear_height)
		var fingers := Vector3.UP.slide(normal).normalized()
		if not pushing:
			overhead = 1.0
			match body.crate_action:
				"lift": overhead = smoothstep(0.69, 0.91, body.crate_action_phase)
				"place": overhead = 1.0 - smoothstep(0.13, 0.33, body.crate_action_phase)
			# Keep the forearm outside the box and support its bottom near the lip.
			var support_depth := 0.015 if hand.side < 0.0 else 0.035
			var support_width := 0.36 if hand.side < 0.0 else 0.42
			var support := box.to_global(face * (half - Vector3.ONE * unit * support_depth)
				+ across_face * half * hand.side * support_width - Vector3.UP * half.y)
			point = point.lerp(support, overhead)
			normal = normal.lerp(-box.global_basis.y.normalized(), overhead).normalized()
			fingers = Vector3.UP.lerp(forward, overhead).slide(normal).normalized()
			clearance = lerpf(clearance, 0.026, overhead)
		if pushing:
			normal = _crate_push_normal.normalized()
			if not _crate_push_contacts.has(hand.side):
				_crate_push_contacts[hand.side] = _crate_face_contact(box, hand, normal, half)
			point = box.to_global(_crate_push_contacts[hand.side])
			fingers = Vector3.UP.slide(normal).normalized()
		var hand_x := fingers * hand.side
		var grip_basis := Basis(hand_x, normal, hand_x.cross(normal))
		var target := Transform3D(grip_basis, point + normal * (unit * clearance) - fingers * (unit * 0.04))
		_raise_crate_clavicle(hand, overhead * 0.15, dt)
		shoulder = skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
		var ratio := shoulder.distance_to(target.origin) / (hand.arm_length * unit)
		var grasp := 1.0 - smoothstep(lerpf(0.92, 0.98, overhead), 1.08, ratio)
		if overhead > 0.0:
			for finger in hand.support_fingers:
				var rest := skeleton.get_bone_rest(finger).basis.get_rotation_quaternion()
				var finger_pose := skeleton.get_bone_pose_rotation(finger)
				skeleton.set_bone_pose_rotation(finger, finger_pose.slerp(rest, overhead * grasp * 0.85))
		hand.pose = target
		hand.contact_id = 0
		_set_hand_pose(hand, shoulder, forward, global_basis.x.normalized(), move_toward(hand.ik.influence, grasp, dt * 12.0))
	return true


func _record_contact_frame() -> void:
	if not visible or _wall_hands.size() != 2:
		return
	var kind := ""
	if actor.door_is_swinging():
		kind = "door"
	elif _crate_push_left > 0.0 and not actor.uses_crate_magic():
		kind = "crate"
	if _contact_trace_kind != "" and kind != _contact_trace_kind:
		if kind.is_empty() and _contact_trace_kind == "crate" and _wall_hands[0].ik.influence > 0.01:
			_append_contact_frame("Отпускание")
			return
		_append_contact_frame("Отпускание")
		var traces := ConfigFile.new()
		traces.load(MotionControls.CONTACT_TRACE_PATH)
		traces.set_value(_contact_trace_kind, "frames", _contact_trace_frames)
		traces.save(MotionControls.CONTACT_TRACE_PATH)
		_contact_trace_frames.clear()
		_contact_trace_kind = ""
	if kind.is_empty():
		return
	if _contact_trace_kind.is_empty():
		_contact_trace_kind = kind
		_contact_trace_started = Time.get_ticks_msec()
	var grip := _wall_hands[0].ik.influence
	var phase := "Контакт" if grip >= 0.9 else "Подход"
	if kind == "door" and actor.door_reach_phase() >= 0.57:
		phase = "Отпускание"
	_append_contact_frame(phase)


func _append_contact_frame(phase: String) -> void:
	var hands: Array[Dictionary] = []
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	for index in 2:
		var hand := _wall_hands[index]
		var wrist_bone: int = bones["rightHand" if index == 0 else "leftHand"]
		var wrist := skeleton.to_global(skeleton.get_bone_global_pose(wrist_bone).origin)
		var elbow := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.get_bone_parent(wrist_bone)).origin)
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
		hands.append({"wrist": to_local(wrist), "elbow": to_local(elbow), "shoulder": to_local(shoulder),
			"target": to_local(hand.pose.origin), "ik": hand.ik.influence})
	var frame := {"ms": Time.get_ticks_msec() - _contact_trace_started, "phase": phase, "hands": hands}
	if _contact_trace_frames.size() < 300:
		_contact_trace_frames.append(frame)
	else:
		_contact_trace_frames[-1] = frame


func _crate_face_contact(box: CollisionShape3D, hand: WallHand, normal: Vector3, half: Vector3) -> Vector3:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
	var local := box.to_local(shoulder - Vector3.UP * unit * 0.10).clamp(-half * 0.85, half * 0.85)
	var axis := 0 if absf(normal.dot(box.global_basis.x.normalized())) > absf(normal.dot(box.global_basis.z.normalized())) else 2
	local[axis] = half[axis] * signf(normal.dot(box.global_basis[axis]))
	return local

func _raise_crate_clavicle(hand: WallHand, amount: float, dt: float) -> void:
	hand.clavicle_raise = move_toward(hand.clavicle_raise, amount, dt * 7.0)
	if hand.clavicle_raise <= 0.0:
		return
	hand.clavicle_base = skeleton.get_bone_pose_rotation(hand.clavicle)
	hand.clavicle_overlaid = true
	var pose := skeleton.get_bone_global_pose(hand.clavicle)
	pose.basis = Basis(Vector3.BACK, hand.side * hand.clavicle_raise * 0.64) * pose.basis
	skeleton.set_bone_global_pose(hand.clavicle, pose)

func _update_wall_hand(dt: float) -> void:
	if _wall_hands.is_empty():
		return
	var forward := global_basis.z.normalized()
	var across := global_basis.x.normalized()
	var selected: WallHand
	var hit := {}
	var side_contact := false
	if visible and current_motion.ends_with("_stowed") and actor.is_on_floor() and not _swimming_pose \
			and not _staff_ready and not staff_action_active() and not actor.has_meta("ember_carried_item"):
		var right := _wall_hands[0]
		hit = _wall_hand_hit(right, forward, Vector3.ZERO, 0.47)
		if not hit.is_empty():
			selected = right
		else:
			var closest := INF
			for hand: WallHand in _wall_hands:
				var outward := across * hand.side
				var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
				# Start inside the capsule even if the shoulder overlaps the wall.
				var inset := maxf(0.0, (shoulder - global_position).dot(outward))
				var lead := forward * (0.19 * unit) - outward * inset
				var candidate := _wall_hand_hit(hand, outward, lead, 0.38 + inset / unit)
				if not candidate.is_empty() and float(candidate.distance) < closest:
					selected = hand
					hit = candidate
					closest = candidate.distance
			side_contact = selected != null
	for hand: WallHand in _wall_hands:
		_apply_wall_hand(hand, hit if hand == selected else {}, side_contact, forward, across, dt)

func _wall_hand_hit(hand: WallHand, direction: Vector3, lead: Vector3, reach: float) -> Dictionary:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
	var start := shoulder + lead - Vector3.UP * (0.10 * unit)
	var ray := PhysicsRayQueryParameters3D.create(start, start + direction * (reach * unit), actor.collision_mask, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		if hit.collider is StaticBody3D and absf(normal.y) <= 0.25 and direction.dot(normal) <= -0.60:
			hit.distance = start.distance_to(hit.position)
			return hit
	return {}

func _apply_wall_hand(hand: WallHand, hit: Dictionary, sliding: bool, forward: Vector3, across: Vector3, dt: float) -> void:
	var weight := hand.ik.influence
	var goal := 0.0
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
	if not hit.is_empty():
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var collider_id: int = hit.collider_id
		var left_plane := absf(normal.dot(hand.contact_point - point)) > 0.02 * unit
		if sliding or collider_id != hand.contact_id or left_plane or hand.contact_point.distance_to(point) > 0.12 * unit:
			hand.contact_point = point
		hand.contact_id = collider_id
		var finger_direction := Vector3.UP + forward * (0.65 if sliding else 0.0)
		var fingers := finger_direction.slide(normal).normalized()
		# The fingers run along mirrored X axes and the back of each hand faces +Y.
		var hand_x := fingers * hand.side
		var basis := Basis(hand_x, normal, hand_x.cross(normal))
		var target := Transform3D(basis, hand.contact_point + normal * (0.025 * unit) - fingers * (0.04 * unit))
		var reach_ratio := shoulder.distance_to(target.origin) / (hand.arm_length * unit)
		goal = smoothstep(0.18, 0.36, reach_ratio) * (1.0 - smoothstep(0.90, 1.0, reach_ratio))
		hand.pose = target if is_zero_approx(weight) else hand.pose.interpolate_with(target, 1.0 - exp(-30.0 * dt))
	else:
		hand.contact_id = 0
	weight = move_toward(weight, goal, dt * (6.0 if goal > weight else 9.0))
	_set_hand_pose(hand, shoulder, forward, across, weight)

func _set_hand_pose(hand: WallHand, shoulder: Vector3, forward: Vector3, across: Vector3, weight: float) -> void:
	if weight > 0.0:
		hand.wrist.global_transform = hand.pose
		# Keep the elbow down and back, with a pole perpendicular to the reach.
		var reach_axis := shoulder.direction_to(hand.pose.origin)
		var bend := (Vector3.DOWN - forward * 0.42 + across * hand.side * 0.24).slide(reach_axis)
		if bend.length_squared() < 0.04:
			bend = (-forward).slide(reach_axis)
		hand.elbow.global_position = shoulder + bend.normalized() * (0.35 * unit)
	hand.ik.influence = weight
	hand.rotation.influence = weight

func _apply_cable_grip(dt: float) -> bool:
	if _wall_hands.is_empty() or not actor.has_method("cable_hand_targets"):
		return false
	var contact: Dictionary = actor.cable_hand_targets()
	var goal: float = contact.get("weight", 0.0)
	if _cable_weight <= 0.0 and contact.is_empty():
		return false
	_cable_weight = move_toward(_cable_weight, goal, dt * (8.0 if goal > _cable_weight else 12.0))
	if _gait_leg_ik.is_empty():
		avatar.position.y = _avatar_base_y
	if _cable_weight <= 0.0:
		_cable_phase = 0.0
		return false
	var forward := global_basis.z.normalized()
	var across := global_basis.x.normalized()
	if not contact.is_empty():
		var tangent: Vector3 = contact.tangent
		var facing := tangent.cross(Vector3.UP).normalized()
		if not facing.is_zero_approx():
			rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-20.0 * dt))
			forward = global_basis.z.normalized()
			across = global_basis.x.normalized()
		var points: PackedVector3Array = contact.points
		var rise := 0.0
		for side in _wall_hands.size():
			var hand := _wall_hands[side]
			var palm := points[side] - Vector3.UP * (0.035 * unit) - forward * (0.04 * unit)
			var fingers := forward * hand.side
			hand.pose = Transform3D(Basis(fingers, Vector3.DOWN, fingers.cross(Vector3.DOWN)), palm)
			var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
			var span := palm - shoulder
			var reach := hand.arm_length * unit * 0.96
			var vertical_reach := sqrt(maxf(0.0, reach * reach - Vector2(span.x, span.z).length_squared()))
			rise = maxf(rise, span.y - vertical_reach)
		avatar.position.y += minf(rise / unit, 0.19) * _cable_weight
	for hand: WallHand in _wall_hands:
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
		var span := shoulder.distance_to(hand.pose.origin) / (hand.arm_length * unit)
		_set_hand_pose(hand, shoulder, forward, across, _cable_weight * (1.0 - smoothstep(1.01, 1.24, span)))
	var tuck := 0.35
	if motion.has_animation(MotionControls.CABLE):
		var clip := motion.get_animation(MotionControls.CABLE)
		_cable_phase = fposmod(_cable_phase + dt / clip.length, 1.0)
		tuck = MotionControls.weight(clip, &"hang_tuck", _cable_phase, tuck)
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	for key in ["leftLowerLeg", "rightLowerLeg"]:
		if bones.has(key):
			var bone: int = bones[key]
			var pose := skeleton.get_bone_pose_rotation(bone)
			skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, tuck * _cable_weight) * pose)
	return true

func prepare_cable_grip() -> bool:
	if staff_action_active():
		return false
	_staff_ready = false
	_staff_idle_left = 0.0
	return true

func can_reach_door() -> bool:
	return visible and not _wall_hands.is_empty() and motion.has_animation(MotionControls.DOOR) and not _staff_ready and not staff_action_active()

func door_reach_duration() -> float:
	return motion.get_animation(MotionControls.DOOR).length

func _apply_door_reach() -> bool:
	if not actor.has_method("door_hand_contact"):
		return false
	var contact: Marker3D = actor.door_hand_contact()
	if not is_instance_valid(contact) or not can_reach_door():
		return false
	var hand := _wall_hands[0]
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
	var normal := contact.global_basis.z.normalized()
	var phase: float = actor.door_reach_phase()
	var grip := MotionControls.weight(motion.get_animation(MotionControls.DOOR), &"grip_weight", phase, phase)
	if actor.door_is_swinging():
		grip = smoothstep(0.12, 0.35, phase) * (1.0 - smoothstep(0.56, 0.74, phase))
	var fingers := Vector3.UP.slide(normal).normalized()
	var hand_x := -fingers
	hand.pose = Transform3D(Basis(hand_x, normal, hand_x.cross(normal)), contact.global_position + normal * (0.025 * unit) - fingers * (0.04 * unit))
	var reach := shoulder.distance_to(hand.pose.origin) / (hand.arm_length * unit)
	_set_hand_pose(hand, shoulder, -normal, global_basis.x.normalized(), grip * (1.0 - smoothstep(0.93, 1.12, reach)))
	_apply_wall_hand(_wall_hands[1], {}, false, -normal, global_basis.x.normalized(), get_process_delta_time())
	return true

func _install_bone_rotation(label: String, bone: int, target: Node3D) -> CopyTransformModifier3D:
	var modifier := CopyTransformModifier3D.new()
	modifier.name = label
	modifier.influence = 0.0
	modifier.setting_count = 1
	skeleton.add_child(modifier)
	modifier.set_apply_bone_name(0, skeleton.get_bone_name(bone))
	modifier.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	modifier.set_reference_node(0, modifier.get_path_to(target))
	modifier.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
	modifier.set_axis_flags(0, CopyTransformModifier3D.AXIS_FLAG_ALL)
	modifier.set_amount(0, 1.0)
	modifier.set_relative(0, false)
	modifier.set_additive(0, false)
	return modifier

func _install_stop_ik() -> void:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	_terrain_head = int(bones.head)
	for side: String in ["left", "right"]:
		var ankle := Marker3D.new()
		avatar.add_child(ankle)
		var knee := Marker3D.new()
		avatar.add_child(knee)
		knee.position = Vector3(-0.12 if side == "right" else 0.12, 0.45, 0.55)
		if side == "right":
			_right_gait_knee = knee
		var ik := TwoBoneIK3D.new()
		ik.setting_count = 1
		ik.influence = 0.0
		skeleton.add_child(ik)
		var foot: int = bones[side + "Foot"]
		ik.set_root_bone_name(0, skeleton.get_bone_name(bones[side + "UpperLeg"]))
		ik.set_middle_bone_name(0, skeleton.get_bone_name(bones[side + "LowerLeg"]))
		ik.set_end_bone_name(0, skeleton.get_bone_name(foot))
		ik.set_extend_end_bone(0, false)
		ik.set_target_node(0, ik.get_path_to(ankle))
		ik.set_pole_node(0, ik.get_path_to(knee))
		_gait_ankles.append(ankle)
		_gait_leg_ik.append(ik)
		_gait_foot_bones.append(foot)
		var toe := Marker3D.new()
		avatar.add_child(toe)
		var toe_bone: int = bones[side + "Toes"]
		_stance_toes.append(toe)
		_stance_toe_bones.append(toe_bone)
		_stance_rotations.append(_install_bone_rotation(side + "StanceFoot", foot, ankle))
		_stance_rotations.append(_install_bone_rotation(side + "StanceToe", toe_bone, toe))

func _update_animation_importance()->void:
	var full_rate:=important_character or AnimationDistanceLod.is_party_visual(actor)
	if full_rate==_animation_full_rate:return
	_animation_full_rate=full_rate
	_animation_lod.set_secondary_motion_enabled(full_rate)

func _locomotion_clip() -> String:
	var gait_speed := speed_mps / _terrain_stride
	if gait_speed < 0.08:
		return "idle_alt" if _use_alt_idle else "idle"
	if gait_speed < 1.8:
		return "walk_adventure" if not _use_original_walk and motion.has_animation(&"walk_adventure") else "walk"
	if gait_speed < 3.7 and motion.has_animation(&"jog"):
		return "jog"
	return "run"

func _select_motion() -> String:
	if _mantle_active:
		return MotionControls.MANTLE
	if _swimming_pose and motion.has_animation(&"swim_stowed"):
		return "swim_stowed" if speed_mps > 0.12 else "swim_idle_stowed"
	if _falling and motion.has_animation(&"fall_stowed"):
		return "fall_stowed"
	if traversal_roll_active():
		return "roll_stowed"
	if (_landing_requested or (current_motion == "land_stowed" and motion.is_playing())) and motion.has_animation(&"land_stowed"):
		return "land_stowed"
	if staff_strike_active():
		return current_motion
	if _gait_waiting_contact:
		return current_motion
	if _jog_reverse_direction != 0.0:
		return current_motion
	var clip := ("idle_alt" if _use_alt_idle else "idle") if _gait_braking else _locomotion_clip()
	if not _tempo_override.is_empty():
		if _gait_band(clip) == _tempo_override:
			_tempo_override = ""
		elif _tempo_override == "walk":
			clip = "walk_adventure" if not _use_original_walk and motion.has_animation(&"walk_adventure") else "walk"
		else:
			clip = _tempo_override
	if (not _staff_ready or not _staff_profile.is_empty()) and motion.has_animation(clip + "_stowed"):
		return clip + "_stowed"
	return clip


func mantle_duration() -> float:
	if _wall_hands.size() != 2 or _gait_ankles.size() != 2 or not has_trial_staff() or _staff_ready or staff_action_active() or not motion.has_animation(MotionControls.MANTLE):
		return 0.0
	return motion.get_animation(MotionControls.MANTLE).length


func mantle_unassisted_height() -> float:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var frame := avatar.global_transform.affine_inverse() * skeleton.global_transform
	var hip := frame * skeleton.get_bone_global_rest(bones.rightUpperLeg).origin
	# With the thigh horizontal and the shin vertical, the ankle sits
	# one shin length below the hip. Measure to the sole, not the ankle.
	var shin := skeleton.get_bone_rest(bones.rightFoot).origin.length()
	return (hip.y + _avatar_base_y - shin - 0.09) * unit


func mantle_waist_height() -> float:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var frame := avatar.global_transform.affine_inverse() * skeleton.global_transform
	var hips := frame * skeleton.get_bone_global_rest(bones.hips).origin
	return (hips.y + _avatar_base_y) * unit


func begin_mantle(points: Array[Vector3], forward: Vector3, supports: Array[Vector3], hands_first: bool, jumps: bool) -> void:
	_mantle_active = true
	_mantle_palms = points
	_mantle_facing = forward
	_mantle_hands_first = hands_first
	_mantle_jumps = jumps
	_ledge_jump_phase = 0.0
	rotation.y = atan2(forward.x, forward.z)
	_mantle_foot_start = skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[1]).origin)
	_mantle_ankle_target = supports[0] + Vector3.UP * unit * 0.09
	_mantle_knee_target = supports[0] + Vector3.UP * unit * 0.065
	if hands_first:
		_mantle_left_knee_target = supports[1] + Vector3.UP * unit * 0.065
	else:
		var bones: Dictionary = avatar.get_meta("hoshi_bones")
		_mantle_back_ankle = skeleton.global_transform * skeleton.get_bone_global_pose(_gait_foot_bones[0])
		for key in ["chest", "rightUpperArm", "rightLowerArm", "rightHand", "leftUpperArm", "leftLowerArm", "leftHand"]:
			var bone: int = bones[key]
			_mantle_step_upper_pose[bone] = skeleton.get_bone_pose_rotation(bone)
	if jumps:
		for index in 2:
			_ledge_jump_start.append(skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[index]).origin))
			_ledge_jump_landing.append(supports[1 - index] + Vector3.UP * unit * 0.09)
	_mantle_knee_home = _right_gait_knee.position
	wait_for_gait_stop_contact(false)
	set_gait_braking(false)
	_clear_tempo_plant()
	_falling = false
	_landing_requested = false


func set_ledge_jump_phase(phase: float) -> void:
	_ledge_jump_phase = phase


func finish_mantle() -> void:
	_mantle_active = false
	_mantle_step_upper_pose.clear()
	_mantle_palms.clear()
	_ledge_jump_start.clear()
	_ledge_jump_landing.clear()
	_mantle_knee_weight = 0.0
	_gait_leg_ik[1].influence = 0.0
	_gait_leg_ik[0].influence = 0.0
	_stance_rotations[0].influence = 0.0
	_stance_rotations[2].influence = 0.0
	_right_gait_knee.position = _mantle_knee_home
	for hand: WallHand in _wall_hands:
		hand.ik.influence = 0.0
		hand.rotation.influence = 0.0


func _apply_mantle_hands() -> bool:
	if not _mantle_active:
		return false
	var clip := motion.get_animation(MotionControls.MANTLE)
	var time := motion.current_animation_position
	var phase := time / clip.length
	if not _mantle_hands_first:
		for bone: int in _mantle_step_upper_pose:
			skeleton.set_bone_pose_rotation(bone, _mantle_step_upper_pose[bone])
		for hand: WallHand in _wall_hands:
			hand.ik.influence = 0.0
			hand.rotation.influence = 0.0
		if _mantle_jumps:
			_apply_ledge_jump(_ledge_jump_phase)
		else:
			avatar.position.y -= _mantle_foot_crouch(phase)
			_apply_mantle_foot(phase)
		return true
	_lean_into_mantle(phase)
	var touch := clip.get_marker_time(&"palms_down")
	var release := clip.get_marker_time(&"palms_release")
	var weight := smoothstep(touch - 0.12, touch, time) * (1.0 - smoothstep(release, release + 0.12, time))
	var across := Vector3.UP.cross(_mantle_facing)
	var crouch := 0.0
	for i in _wall_hands.size():
		var hand: WallHand = _wall_hands[i]
		var offset := (skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin) - _mantle_palms[i]) / unit
		var vertical_reach := sqrt(maxf(0.025, pow(hand.arm_length * 0.91, 2) - Vector2(offset.x, offset.z).length_squared()))
		crouch = maxf(crouch, offset.y - minf(0.24, vertical_reach))
	crouch = minf(crouch, 0.92)
	avatar.position.y -= crouch * weight
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var straighten := smoothstep(0.05, 0.22, phase)
	for key in ["rightUpperLeg", "rightLowerLeg", "rightFoot", "leftUpperLeg", "leftLowerLeg", "leftFoot"]:
		var bone: int = bones[key]
		var neutral := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(neutral, straighten))
	_apply_mantle_knee(phase)
	for i in _wall_hands.size():
		var hand: WallHand = _wall_hands[i]
		var fingers := _mantle_facing * hand.side
		hand.pose = Transform3D(Basis(fingers, Vector3.UP, fingers.cross(Vector3.UP)), _mantle_palms[i])
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(hand.shoulder).origin)
		_set_hand_pose(hand, shoulder, _mantle_facing, across, weight)
	return true


func _apply_ledge_jump(phase: float) -> void:
	var takeoff := MotionControls.LEDGE_JUMP_TAKEOFF
	var land := MotionControls.LEDGE_JUMP_LAND
	var crouch := smoothstep(0.0, 0.13, phase) * (1.0 - smoothstep(0.13, takeoff, phase))
	var recovered := MotionControls.LEDGE_JUMP_RECOVERED
	var absorb := smoothstep(land - 0.04, land + 0.07, phase) * (1.0 - smoothstep(land + 0.07, recovered, phase))
	var tuck := smoothstep(takeoff, 0.46, phase) * (1.0 - smoothstep(0.52, land, phase))
	avatar.position.y -= 0.14 * crouch + 0.13 * absorb
	var ground := (get_parent() as Node3D).global_position
	var across := Vector3.UP.cross(_mantle_facing)
	for index in 2:
		var air_ankle := ground + (Vector3.UP * (0.09 + 0.15 * tuck)
			+ across * (0.095 if index == 0 else -0.095) + _mantle_facing * 0.05 * tuck) * unit
		var goal := _ledge_jump_start[index].lerp(air_ankle, smoothstep(takeoff, 0.33, phase))
		goal = goal.lerp(_ledge_jump_landing[index], smoothstep(0.66, land, phase))
		_gait_ankles[index].global_position = goal
		_gait_ankles[index].global_basis = (skeleton.global_basis * skeleton.get_bone_global_rest(_gait_foot_bones[index]).basis).orthonormalized()
		_gait_leg_ik[index].influence = 1.0
		_stance_rotations[index * 2].influence = 1.0
	_bend_mantle_chest((0.55 * crouch + 0.6 * tuck + absorb) * deg_to_rad(17.0))
	var swing := 12.0 * crouch - 25.0 * tuck - 12.0 * absorb
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	for upper_arm: int in [bones.rightUpperArm, bones.leftUpperArm]:
		_rotate_mantle_pose(upper_arm, deg_to_rad(swing))


func _lean_into_mantle(phase: float) -> void:
	var lean := smoothstep(0.53, 0.77, phase) * (1.0 - smoothstep(0.88, 1.0, phase))
	_bend_mantle_chest(deg_to_rad(20.0) * lean)


func _bend_mantle_chest(angle: float) -> void:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	_rotate_mantle_pose(bones.chest, angle)


func _rotate_mantle_pose(bone: int, angle: float, direction := Vector3.RIGHT) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var axis := skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse() * direction
	var pose := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, Quaternion(axis.normalized(), angle) * pose)


func _mantle_foot_crouch(phase: float) -> float:
	var plant := MotionControls.MANTLE_FOOT_PHASE
	var support := smoothstep(plant - 0.08, plant, phase) * (1.0 - smoothstep(0.84, 0.96, phase))
	if support <= 0.0:
		return 0.0
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var hip := skeleton.to_global(skeleton.get_bone_global_pose(bones.rightUpperLeg).origin)
	var offset := (hip - _mantle_ankle_target) / unit
	var leg := skeleton.get_bone_rest(bones.rightLowerLeg).origin.length() + skeleton.get_bone_rest(bones.rightFoot).origin.length()
	var reach := sqrt(maxf(0.025, pow(leg * 0.94, 2) - Vector2(offset.x, offset.z).length_squared()))
	return clampf(offset.y - reach, 0.0, 0.30) * support


func _apply_mantle_foot(phase: float) -> void:
	var plant := MotionControls.MANTLE_FOOT_PHASE
	var lift := smoothstep(0.16, 0.33, phase)
	var step := smoothstep(0.31, plant, phase)
	var raised := _mantle_foot_start
	raised.y = maxf(raised.y, _mantle_ankle_target.y + unit * 0.12)
	var goal := _mantle_foot_start.lerp(raised, lift).lerp(_mantle_ankle_target, step)
	var weight := smoothstep(0.16, 0.29, phase) * (1.0 - smoothstep(0.84, 0.96, phase))
	# Guide the knee above the lip while the ankle moves over it.
	_right_gait_knee.global_position = _mantle_ankle_target + (Vector3.UP * 0.32 - _mantle_facing * 0.24) * unit
	_gait_ankles[1].global_position = goal
	_gait_ankles[1].global_basis = (skeleton.global_basis * skeleton.get_bone_global_rest(_gait_foot_bones[1]).basis).orthonormalized()
	_gait_leg_ik[1].influence = weight
	_stance_rotations[2].influence = weight
	var back_weight := 1.0 - smoothstep(plant, 0.60, phase)
	_gait_ankles[0].global_transform = _mantle_back_ankle
	_gait_leg_ik[0].influence = back_weight
	_stance_rotations[0].influence = back_weight


func _apply_mantle_knee(phase: float) -> void:
	var plant := MotionControls.MANTLE_KNEE_PHASE
	var weight := smoothstep(0.65, plant, phase) * (1.0 - smoothstep(0.88, 1.0, phase))
	_mantle_knee_weight = weight
	if weight <= 0.0:
		return
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var thigh: int = bones.rightUpperLeg
	var knee: int = bones.rightLowerLeg
	var foot: int = bones.rightFoot
	var hip := skeleton.to_global(skeleton.get_bone_global_pose(thigh).origin)
	var offset := (_mantle_knee_target - hip) / unit
	var thigh_length := skeleton.get_bone_rest(knee).origin.length()
	var vertical := sqrt(maxf(0.0025, thigh_length * thigh_length - Vector2(offset.x, offset.z).length_squared()))
	# Place the knee by adjusting the height of the hips and aiming the thigh.
	# The shin trails back towards the lip, leaving the ankle off the platform.
	avatar.position.y += clampf(offset.y + vertical, -0.52, 0.22) * weight
	_aim_mantle_bone(thigh, knee, _mantle_knee_target, weight)
	var shin_direction := (-_mantle_facing - Vector3.UP * 0.12).normalized()
	var shin_origin := skeleton.to_global(skeleton.get_bone_global_pose(knee).origin)
	_aim_mantle_bone(knee, foot, shin_origin + shin_direction * unit, weight)
	# Fold the trailing leg as the hips cross the lip, so it cannot hang
	# straight through the platform while the leading knee takes weight.
	var trailing := smoothstep(0.73, 0.83, phase) * (1.0 - smoothstep(0.88, 1.0, phase))
	if trailing > 0.0:
		_aim_mantle_bone(bones.leftUpperLeg, bones.leftLowerLeg, _mantle_left_knee_target, trailing)
		var left_shin := skeleton.to_global(skeleton.get_bone_global_pose(bones.leftLowerLeg).origin)
		_aim_mantle_bone(bones.leftLowerLeg, bones.leftFoot, left_shin + shin_direction * unit, trailing)


func _aim_mantle_bone(bone: int, tip: int, target: Vector3, weight: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := (skeleton.get_bone_global_pose(tip).origin - pose.origin).normalized()
	var desired := (skeleton.to_local(target) - pose.origin).normalized()
	if not desired.is_zero_approx() and not current.is_zero_approx():
		var turn := Quaternion.IDENTITY.slerp(Quaternion(current, desired), weight)
		pose.basis = Basis(turn) * pose.basis
		skeleton.set_bone_global_pose(bone, pose)

func update_traversal_pose(grounded: bool, swimming: bool, descending: float, dt: float, surface_y: float, previous_y: float, moving: bool) -> void:
	_swimming_pose = swimming
	_swim_entry_time = _swim_entry_time + dt if swimming else 0.0
	_swim_depth = maxf(0.0, (surface_y - actor.global_position.y) / unit) if swimming else 0.0
	if swimming:
		_fall_time = 0.0
		_falling = false
		_landing_requested = false
		_roll_requested = false
		_fall_peak_y = -INF
		_moving_land_left = 0.0
	elif grounded:
		if _falling:
			var drop := (_fall_peak_y - actor.global_position.y) / unit
			_roll_requested = drop >= 1.8 and motion.has_animation(&"roll_stowed")
			if not _roll_requested:
				if moving:
					_moving_land_left = 0.30
				else:
					_landing_requested = true
		_fall_time = 0.0
		_falling = false
		_fall_peak_y = -INF
	else:
		_fall_peak_y = maxf(_fall_peak_y, previous_y)
		if descending > unit * 0.55:
			_fall_time += dt
			_falling = _fall_time >= 0.11
	if swimming or _falling:
		_workshop_cast_time = -1.0
		_staff_overlay_time = -1.0
		_staff_idle_left = 0.0
		_staff_ready = false
		if current_motion == "staff_strike":
			current_motion = ""

func can_swim_in_trial() -> bool:
	return loaded and visible and motion.has_animation(&"swim_stowed")

func swim_entry_depth() -> float:
	var head_rest := skeleton.get_bone_global_rest(_terrain_head).origin
	return ((skeleton.transform * head_rest).y + _avatar_base_y - 0.075) * unit

func traversal_roll_active() -> bool:
	return _roll_requested or (current_motion == "roll_stowed" and motion.is_playing())

func traversal_roll_speed() -> float:
	var phase := motion.current_animation_position / maxf(motion.current_animation_length, 0.001) if current_motion == "roll_stowed" else 0.0
	return 0.7 + 1.3 * sin(PI * clampf(phase, 0.0, 1.0))

func moving_landing_speed() -> float:
	return lerpf(1.0, 0.72, _moving_land_left / 0.30)

func uses_gait_transitions() -> bool:
	return loaded and visible and motion.has_animation(&"idle_stowed")

func _gait_band(clip: String) -> String:
	var base := clip.trim_suffix("_stowed")
	return "walk" if base.begins_with("walk") else base

func clear_gait_tempo() -> void:
	_tempo_pending = ""
	_tempo_override = ""
	_tempo_contact = -1.0

func gait_speed_for_input(requested: float, previous: float, dt: float) -> float:
	var next := "walk" if requested < 1.8 * unit else "jog" if requested < 3.7 * unit else "run"
	var old := "walk" if previous < 1.8 * unit else "jog" if previous < 3.7 * unit else "run"
	if next == old or next == "run" or old == "run" or _gait_band(current_motion) != old:
		if not _tempo_pending.is_empty():
			_tempo_pending = ""
			_tempo_contact = -1.0
		return requested
	if _tempo_pending != next:
		_animation_lod.flush(motion)
		var length := motion.current_animation_length
		if length <= 0.0: return requested
		var phase := fposmod(motion.current_animation_position / length - _gait_contact_phase(current_motion), 1.0)
		var progress := fposmod(phase, 0.5)
		_tempo_pending = next
		_tempo_contact = fposmod(phase - progress + (0.5 if progress > 0.025 else 0.0), 1.0)
		_tempo_wait = (0.5 - progress) * length / maxf(motion.speed_scale, 0.45) if progress > 0.025 else 0.0
	_tempo_wait -= dt
	if _tempo_wait > 0.0: return previous
	_tempo_pending = ""
	_tempo_override = next
	return requested

func try_commit_gait_stop(velocity: Vector3) -> float:
	if _gait_braking or _gait_ankles.size() != 2 or velocity.is_zero_approx(): return -1.0
	var contact := _gait_contact_phase(current_motion)
	if contact < 0.0: return -1.0
	_animation_lod.flush(motion)
	var length := motion.current_animation_length
	if length <= 0.0: return -1.0
	var phase := fposmod(motion.current_animation_position / length, 1.0)
	var progress := fposmod(phase, 0.5)
	# The first pose of each half-cycle has the incoming foot low and
	# ahead. Later support poses have already passed that placement.
	if progress > 0.045: return -1.0
	var side := 0 if phase < 0.5 else 1
	var front := skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[side]).origin)
	var ground := _gait_ground(front)
	if ground.is_empty() or front.y - ground.position.y > unit * 0.135: return -1.0
	var direction := velocity.normalized()
	var distance := (front - actor.global_position).dot(direction)
	if distance < 0.025 * unit: return -1.0
	var duration := maxf(0.22, 2.0 * distance / velocity.length())
	if duration > 0.58: return -1.0
	set_gait_braking(true, direction * distance, duration, side)
	if _gait_stop_elapsed >= 0.0:
		return distance
	set_gait_braking(false)
	return -1.0

func wait_for_gait_stop_contact(waiting: bool) -> bool:
	_gait_waiting_contact = waiting and _gait_contact_phase(current_motion) >= 0.0
	return _gait_waiting_contact

func set_gait_braking(braking: bool, travel := Vector3.ZERO, duration := 0.30, committed_side := -1) -> void:
	if braking:
		_gait_waiting_contact = false
	if braking == _gait_braking: return
	_gait_braking = braking
	if not braking:
		_gait_stop_elapsed = -1.0
		for ik in _gait_leg_ik: ik.influence = 0.0
		return
	_clear_tempo_plant()
	var clip := current_motion.trim_suffix("_stowed")
	if _gait_ankles.size() != 2 or travel.is_zero_approx() or clip not in ["walk", "walk_adventure", "jog", "run"]: return
	_animation_lod.flush(motion)
	_gait_foot_start.clear()
	for foot in _gait_foot_bones:
		_gait_foot_start.append(skeleton.to_global(skeleton.get_bone_global_pose(foot).origin))
	var difference := _gait_foot_start[0] - _gait_foot_start[1]
	_gait_support = 0 if difference.y < -0.025 * unit or (absf(difference.y) <= 0.025 * unit and difference.dot(travel) >= 0.0) else 1
	if committed_side >= 0:
		_gait_support = committed_side
	var swing := 1 - _gait_support
	var rest := skeleton.get_bone_global_rest(_gait_foot_bones[swing]).origin
	var stance := global_basis.orthonormalized() * Vector3(rest.x, 0.0, rest.z) * unit
	var target := actor.global_position + travel + stance
	if committed_side >= 0:
		var direction := travel.normalized()
		var anchor := _gait_foot_start[_gait_support]
		target += direction * (anchor - target).dot(direction)
	var support_ground := _gait_ground(_gait_foot_start[_gait_support])
	var landing_ground := _gait_ground(target)
	if support_ground.is_empty() or landing_ground.is_empty(): return
	_gait_foot_start[_gait_support].y = support_ground.position.y + unit * 0.09
	_gait_landing = landing_ground.position + Vector3.UP * unit * 0.09
	_gait_stop_duration = duration
	_gait_stop_committed = committed_side >= 0
	_gait_stop_elapsed = 0.0

func _gait_ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * unit * 0.4, at - Vector3.UP * unit * 0.6, 1, [actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray)

func sample_stance_support(standing: bool) -> void:
	_stance_support.clear()
	_stance_foot_basis.clear()
	_stance_toe_basis.clear()
	_stance_toe_only.clear()
	_stance_surface_weight = 0.0
	if not standing or not uses_gait_transitions() or not current_motion.begins_with("idle"):
		return
	if _gait_stop_elapsed >= 0.0 or _tempo_plant_left > 0.0:
		return
	for side in 2:
		var foot_pose := skeleton.global_transform * skeleton.get_bone_global_pose(_gait_foot_bones[side])
		var toe_pose := skeleton.global_transform * skeleton.get_bone_global_pose(_stance_toe_bones[side])
		var ankle := foot_pose.origin
		var forward := global_basis.z.normalized()
		var heel := _gait_ground(ankle - forward * unit * 0.035)
		var toe := _gait_ground(toe_pose.origin)
		if toe.is_empty() or toe.normal.y < 0.7:
			_stance_support.clear()
			return
		var toe_height: float = toe.position.y
		var toe_only: bool = heel.is_empty() or toe_height - heel.position.y > unit * 0.055
		var normal: Vector3 = toe.normal
		if not toe_only:
			normal = (normal + heel.normal).normalized()
		var tilt := Quaternion(Vector3.UP, normal)
		_stance_surface_weight = maxf(_stance_surface_weight, smoothstep(0.05, 0.15, tilt.get_angle()))
		var surface := Quaternion.IDENTITY.slerp(tilt, minf(1.0, deg_to_rad(18.0) / maxf(tilt.get_angle(), 0.001)))
		var lift := Quaternion(global_basis.x.normalized(), deg_to_rad(16.0)) if toe_only else Quaternion.IDENTITY
		var foot_basis := Basis(surface * lift) * foot_pose.basis.orthonormalized()
		var toe_basis := Basis(surface) * toe_pose.basis.orthonormalized()
		var contact_height := toe_height if heel.is_empty() else maxf(toe_height, float(heel.position.y))
		var toe_contact := Vector3(toe_pose.origin.x, contact_height + unit * 0.045, toe_pose.origin.z)
		var toe_offset := skeleton.get_bone_rest(_stance_toe_bones[side]).origin
		var target := toe_contact - foot_basis * toe_offset * unit
		if absf(contact_height - actor.global_position.y) > unit * 0.26:
			_stance_support.clear()
			return
		_stance_support.append(target)
		_stance_foot_basis.append(foot_basis)
		_stance_toe_basis.append(toe_basis)
		_stance_toe_only.append(toe_only)

func _apply_stance_support(dt: float) -> void:
	var owns_feet := current_motion.begins_with("idle") and _gait_stop_elapsed < 0.0 and _tempo_plant_left <= 0.0
	var has_support: bool = owns_feet and _stance_support.size() == 2 and visible and actor.is_on_floor()
	var amount := 0.0
	var pelvis_goal := 0.0
	if has_support:
		var left := _stance_support[0].y
		var right := _stance_support[1].y
		var height_gap := absf(left - right) / unit
		amount = maxf(smoothstep(0.03, 0.07, height_gap), _stance_surface_weight)
		if _stance_toe_only.has(true):
			amount = 1.0
		var low_ground := (minf(left, right) - actor.global_position.y) / unit - 0.09
		# The lower leg limits how high the hips can sit without stretching.
		pelvis_goal = clampf(low_ground - height_gap * 0.18, -0.23, 0.0) * amount
	_stance_pelvis_offset = move_toward(_stance_pelvis_offset, pelvis_goal, dt * 0.8)
	avatar.position.y = _avatar_base_y + _stance_pelvis_offset
	if not owns_feet:
		if _stance_weight > 0.0:
			for ik in _gait_leg_ik: ik.influence = 0.0
			for modifier in _stance_rotations: modifier.influence = 0.0
			_stance_weight = 0.0
		return
	if amount > 0.0:
		for side in 2:
			_gait_ankles[side].global_position = _stance_support[side]
			_gait_ankles[side].global_basis = _stance_foot_basis[side]
			_stance_toes[side].global_basis = _stance_toe_basis[side]
	_stance_weight = move_toward(_stance_weight, amount, dt * 7.0)
	for ik in _gait_leg_ik: ik.influence = _stance_weight
	for modifier in _stance_rotations: modifier.influence = _stance_weight

func terrain_stride_for(travel: Vector3, floor_normal: Vector3) -> float:
	var grade := absf(floor_normal.dot(travel.normalized()))
	return lerpf(1.0, 0.82, smoothstep(0.055, 0.35, grade))

func _terrain_stride_ankle(ankle: Vector3) -> Vector3:
	var along := (ankle - actor.global_position).dot(_terrain_travel)
	return ankle - _terrain_travel * along * (1.0 - _terrain_stride)

func _terrain_support(at: Vector3, direction: Vector3, allow_fallback: bool, debug_side := -1, next := false) -> Dictionary:
	var hit := _gait_ground(at)
	if not hit.is_empty() and hit.normal.y >= 0.70:
		_record_step_probe(at, hit, debug_side, next, false)
		return hit
	if allow_fallback:
		var toward_actor := actor.global_position - at
		toward_actor.y = 0.0
		for offset in [toward_actor.limit_length(unit * 0.14), -direction * unit * 0.18]:
			hit = _gait_ground(at + offset)
			if not hit.is_empty() and hit.normal.y >= 0.70:
				_record_step_probe(at, hit, debug_side, next, true)
				return hit
	_record_step_probe(at, {}, debug_side, next, false)
	return {}

func _record_step_probe(at: Vector3, hit: Dictionary, side: int, next: bool, fallback: bool) -> void:
	if side < 0 or not is_instance_valid(_step_debug_view) or not _step_debug_view.visible: return
	_step_debug_samples.append({"from": at, "to": hit.get("position", at - Vector3.UP * unit * 0.20),
		"side": side, "next": next, "status": "промах" if hit.is_empty() else "запасная" if fallback else "опора"})

func sample_terrain_step(travel: Vector3, floor_normal: Vector3, dt: float, stepping: bool) -> void:
	_step_debug_samples.clear()
	_terrain_step_goal = Vector2.ZERO
	_terrain_step_has_support = Vector2.ZERO
	_terrain_step_contact = Vector2.ZERO
	_terrain_shift_goal = [Vector3.ZERO, Vector3.ZERO]
	_terrain_head_goal = 0.0
	_terrain_stride = 1.0
	_terrain_exit_time = maxf(0.0, _terrain_exit_time - dt)
	var gait := _gait_band(current_motion)
	if gait not in ["walk", "jog", "run"] or travel.is_zero_approx() or _gait_stop_elapsed >= 0.0 or _gait_waiting_contact:
		return
	var direction := travel.normalized()
	if floor_normal.y < 0.70:
		return
	_terrain_travel = direction
	_terrain_stride = terrain_stride_for(travel, floor_normal)
	_terrain_head_goal = clampf(floor_normal.dot(direction) * 0.60, -0.17, 0.17)
	var length := motion.current_animation_length
	if length <= 0.0: return
	var phase := fposmod(motion.current_animation_position / length - _gait_contact_phase(current_motion), 1.0)
	var stance_end := 0.46 if gait == "walk" else 0.25
	var ankles: Array[Vector3] = []
	var supports: Array[Dictionary] = []
	var uneven := floor_normal.y < 0.998 or stepping
	for side in 2:
		var ankle := skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[side]).origin)
		ankle.y -= _terrain_pelvis_offset * unit
		ankle = _terrain_stride_ankle(ankle)
		ankles.append(ankle)
		supports.append(_terrain_support(ankle, direction, uneven or _terrain_exit_time > 0.0, side))
	if not uneven and not supports[0].is_empty() and not supports[1].is_empty():
		uneven = absf(supports[0].position.y - supports[1].position.y) > unit * 0.03
	if uneven:
		_terrain_exit_time = 0.18
	var adjusts_feet := uneven or _terrain_exit_time > 0.0
	if not adjusts_feet and not (is_instance_valid(_step_debug_view) and _step_debug_view.visible): return
	for side in 2:
		var foot_phase := fposmod(phase - side * 0.5, 1.0)
		var ankle := ankles[side]
		var under := supports[side]
		var lookahead := clampf(travel.length() * 0.15, unit * 0.14, unit * 0.35)
		var next_support := {}
		var swing := 0.0
		if foot_phase > stance_end:
			swing = inverse_lerp(stance_end, 1.0, foot_phase)
			next_support = _terrain_support(ankle + direction * lookahead, direction, adjusts_feet, side, true)
		if not adjusts_feet: continue
		# At a crest the foot can be over the edge while its predicted
		# landing is already on top. Use that hit near touchdown.
		if under.is_empty() and swing >= 0.55 and not next_support.is_empty():
			under = next_support
		if under.is_empty(): continue
		_terrain_step_has_support[side] = 1.0
		var support_position: Vector3 = under.position
		_terrain_shift_goal[side] = Vector3(support_position.x - ankle.x, 0.0, support_position.z - ankle.z)
		var support_offset := float(under.position.y) + unit * 0.09 - ankle.y
		var contact := 1.0 - smoothstep(stance_end - 0.08, stance_end, foot_phase)
		var lift := lerpf(maxf(0.0, support_offset), support_offset, contact)
		if foot_phase > stance_end:
			contact = smoothstep(0.78, 1.0, swing)
			lift = lerpf(maxf(0.0, support_offset), support_offset, contact)
			if not next_support.is_empty() and next_support.normal.y >= 0.70:
				var rise := maxf(0.0, float(next_support.position.y - under.position.y))
				lift += rise * sin(PI * swing)
		_terrain_step_goal[side] = clampf(lift, -unit * 0.12, unit * 0.16)
		_terrain_step_normals[side] = under.normal
		_terrain_step_contact[side] = contact

func _apply_terrain_step(dt: float) -> void:
	var gait := _gait_band(current_motion)
	var smoothing := 1.0 - exp(-18.0 * dt)
	_terrain_head_pitch = lerpf(_terrain_head_pitch, _terrain_head_goal, smoothing)
	if absf(_terrain_head_pitch) > 0.001:
		var head_parent := skeleton.get_bone_parent(_terrain_head)
		var parent_basis := skeleton.get_bone_global_pose(head_parent).basis.orthonormalized()
		var axis := parent_basis.inverse() * Vector3.RIGHT
		var head_rotation := skeleton.get_bone_pose_rotation(_terrain_head)
		skeleton.set_bone_pose_rotation(_terrain_head, Quaternion(axis.normalized(), _terrain_head_pitch) * head_rotation)
	if gait not in ["walk", "jog", "run"] or _gait_stop_elapsed >= 0.0 or _tempo_plant_left > 0.0 or _gait_waiting_contact:
		_terrain_shift = [Vector3.ZERO, Vector3.ZERO]
		_terrain_step_weight = Vector2.ZERO
		_terrain_pelvis_offset = move_toward(_terrain_pelvis_offset, 0.0, 0.75 * dt)
		avatar.position.y += _terrain_pelvis_offset
		_terrain_step_offset = Vector2.ZERO
		if _gait_stop_elapsed < 0.0 and _tempo_plant_left <= 0.0 and _stance_weight <= 0.0:
			for ik in _gait_leg_ik: ik.influence = 0.0
		if _stance_weight <= 0.0:
			for modifier in _stance_rotations: modifier.influence = 0.0
		return
	_terrain_step_offset = _terrain_step_offset.lerp(_terrain_step_goal, 1.0 - exp(-22.0 * dt))
	var pelvis_goal := clampf(minf(_terrain_step_goal.x, _terrain_step_goal.y) / unit * 0.8, -0.075, 0.0)
	_terrain_pelvis_offset = move_toward(_terrain_pelvis_offset, pelvis_goal, 0.75 * dt)
	avatar.position.y += _terrain_pelvis_offset
	if _terrain_step_offset.length() < unit * 0.0005 and _terrain_step_contact.is_zero_approx() and is_equal_approx(_terrain_stride, 1.0) and _terrain_shift[0].length_squared() + _terrain_shift[1].length_squared() < 0.00001:
		_terrain_step_offset = Vector2.ZERO
		_terrain_step_weight = Vector2.ZERO
		for ik in _gait_leg_ik: ik.influence = 0.0
		for modifier in _stance_rotations: modifier.influence = 0.0
		return
	for side in 2:
		_terrain_shift[side] = _terrain_shift[side].lerp(_terrain_shift_goal[side], smoothing)
		_terrain_step_weight[side] = move_toward(_terrain_step_weight[side], _terrain_step_has_support[side], dt * 8.0)
		var foot := skeleton.global_transform * skeleton.get_bone_global_pose(_gait_foot_bones[side])
		var target := _terrain_stride_ankle(foot.origin) + _terrain_shift[side]
		target.y += _terrain_step_offset[side] - _terrain_pelvis_offset * unit
		_gait_ankles[side].global_position = target
		_gait_leg_ik[side].influence = _terrain_step_weight[side] * smoothstep(0.0, unit * 0.012, target.distance_to(foot.origin))
		var tilt := Quaternion(Vector3.UP, _terrain_step_normals[side])
		var rotation := Quaternion.IDENTITY.slerp(tilt, minf(1.0, deg_to_rad(18.0) / maxf(tilt.get_angle(), 0.001)))
		_gait_ankles[side].global_basis = Basis(rotation) * foot.basis.orthonormalized()
		_stance_rotations[side * 2].influence = _terrain_step_contact[side] * _terrain_step_weight[side]

func set_jog_turn_input(wish: Vector3) -> void:
	var pace := wish.length() / unit
	_jog_turn_input = wish.normalized() if pace >= 1.8 and pace < 3.7 else Vector3.ZERO


func _face_jog_reversal(dt: float) -> float:
	if (
		_jog_turn_input.is_zero_approx() or _gait_band(current_motion) != "jog" or not actor.is_on_floor()
		or _swimming_pose or _cable_weight > 0.0 or staff_action_active()
	):
		_jog_reverse_direction = 0.0
		_jog_reverse_rate = 0.0
		return 0.0
	var target := atan2(_jog_turn_input.x, _jog_turn_input.z)
	var error := angle_difference(rotation.y, target)
	if _jog_reverse_direction == 0.0:
		if absf(error) < deg_to_rad(135.0):
			return 0.0
		# An exact reversal has two equivalent arcs. Use the current support
		# to choose once instead of letting floating-point yaw choose each frame.
		_jog_reverse_direction = signf(error)
		if absf(error) > deg_to_rad(175.0):
			_jog_reverse_direction = -1.0 if _jog_support_side() == 1 else 1.0
	var remaining := fposmod(error * _jog_reverse_direction, TAU) if absf(error) > deg_to_rad(175.0) else error * _jog_reverse_direction
	if remaining <= deg_to_rad(0.5):
		_jog_reverse_direction = 0.0
		_jog_reverse_rate = 0.0
		return 0.0
	const ACCELERATION := TAU * 4.0
	var rate_goal := minf(deg_to_rad(420.0), sqrt(2.0 * ACCELERATION * remaining))
	_jog_reverse_rate = move_toward(_jog_reverse_rate, rate_goal, ACCELERATION * dt)
	var turn := _jog_reverse_direction * remaining
	_sample_jog_turn(turn)
	rotation.y += _jog_reverse_direction * minf(remaining, _jog_reverse_rate * dt)
	# Lean follows the speed of the body, not the full angle still to travel.
	return _jog_reverse_direction * minf(remaining, _jog_reverse_rate * 0.10)


func _jog_support_side() -> int:
	if (
		_gait_leg_ik.size() != 2 or _gait_band(current_motion) != "jog" or not actor.is_on_floor()
		or _gait_stop_elapsed >= 0.0 or _gait_waiting_contact or _tempo_plant_left > 0.0
		or _swimming_pose or _cable_weight > 0.0 or staff_action_active()
	):
		return -1
	var length := motion.current_animation_length
	if length <= 0.0:
		return -1
	var phase := fposmod(motion.current_animation_position / length - _gait_contact_phase(current_motion), 1.0)
	var side := int(phase >= 0.5)
	return side if phase - side * 0.5 < 0.25 else -1


func _sample_jog_turn(turn: float) -> void:
	var side := _jog_support_side()
	if side != _jog_turn_side:
		_jog_turn_side = -1
	if side >= 0 and _jog_turn_side < 0 and absf(turn) >= deg_to_rad(9.0):
		_jog_turn_side = side
		# Capture before yaw and undo this frame's inherited actor translation.
		_jog_turn_foot = skeleton.global_transform * skeleton.get_bone_global_pose(_gait_foot_bones[side])
		if _jog_has_last_origin:
			_jog_turn_foot.origin -= global_position - _jog_last_origin
		if _terrain_exit_time > 0.0:
			var support := _gait_ground(_jog_turn_foot.origin)
			if support.is_empty() or support.normal.y < 0.70:
				_jog_turn_side = -1
			else:
				_jog_turn_foot.origin.y = support.position.y + unit * 0.09
				var tilt := Quaternion(Vector3.UP, support.normal)
				var weight := minf(1.0, deg_to_rad(18.0) / maxf(tilt.get_angle(), 0.001))
				_jog_turn_foot.basis = Basis(Quaternion.IDENTITY.slerp(tilt, weight)) * _jog_turn_foot.basis
	_jog_last_origin = global_position
	_jog_has_last_origin = true


func _apply_jog_turn(turn: float, dt: float) -> void:
	var jogging: bool = (
		uses_gait_transitions() and _gait_band(current_motion) == "jog" and actor.is_on_floor()
		and not _gait_waiting_contact and _gait_stop_elapsed < 0.0
		and not _swimming_pose and not staff_action_active()
	)
	var goal := clampf(turn * 0.13, -deg_to_rad(7.0), deg_to_rad(7.0)) if jogging else 0.0
	_jog_turn_lean = lerpf(_jog_turn_lean, goal, 1.0 - exp(-11.0 * dt))
	if absf(_jog_turn_lean) > 0.0005:
		var bones: Dictionary = avatar.get_meta("hoshi_bones")
		_jog_turn_chest = bones.chest
		var parent := skeleton.get_bone_parent(_jog_turn_chest)
		var axis := skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse() * Vector3.FORWARD
		_jog_turn_chest_base = skeleton.get_bone_pose_rotation(_jog_turn_chest)
		skeleton.set_bone_pose_rotation(_jog_turn_chest, Quaternion(axis.normalized(), _jog_turn_lean) * _jog_turn_chest_base)
	var side := _jog_turn_side
	if side < 0 or _jog_support_side() != side:
		_jog_turn_side = -1
		return
	var foot := skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[side]).origin)
	var reach := Vector2(foot.x - _jog_turn_foot.origin.x, foot.z - _jog_turn_foot.origin.z).length() / unit
	var phase := fposmod(motion.current_animation_position / motion.current_animation_length - _gait_contact_phase(current_motion), 0.5)
	# Ease out before swing or before the turn would overextend the leg.
	var weight := (1.0 - smoothstep(0.18, 0.25, phase)) * (1.0 - smoothstep(0.18, 0.30, reach))
	if weight <= 0.0:
		return
	var terrain_weight := _gait_leg_ik[side].influence
	var ankle := _gait_ankles[side]
	# On a slope the terrain correction stays active as the planted foot releases.
	ankle.global_transform = ankle.global_transform.interpolate_with(_jog_turn_foot, weight) if terrain_weight > 0.0 else _jog_turn_foot
	_gait_leg_ik[side].influence = maxf(terrain_weight, weight)
	_stance_rotations[side * 2].influence = maxf(_stance_rotations[side * 2].influence, weight)


func _apply_gait_stop(dt: float) -> void:
	if _gait_stop_elapsed < 0.0: return
	_gait_stop_elapsed += dt
	var progress := clampf(_gait_stop_elapsed / _gait_stop_duration, 0.0, 1.0)
	var release := 1.0 - smoothstep(_gait_stop_duration, _gait_stop_duration + 0.18, _gait_stop_elapsed)
	var blend := smoothstep(0.0, 0.055, _gait_stop_elapsed) * release
	var swing := 1 - _gait_support
	_gait_ankles[_gait_support].global_position = _gait_foot_start[_gait_support]
	var arc := Vector3.UP * unit * 0.055 * sin(progress * PI)
	_gait_ankles[swing].global_position = _gait_foot_start[swing].lerp(_gait_landing, smoothstep(0.0, 1.0, progress)) + arc
	for ik in _gait_leg_ik: ik.influence = blend
	if _gait_stop_committed:
		_gait_leg_ik[_gait_support].influence = release
	if _gait_stop_elapsed >= _gait_stop_duration + 0.18:
		_gait_stop_elapsed = -1.0

func _gait_contact_phase(clip: String) -> float:
	if motion != null and motion.has_animation(clip):
		var animation := motion.get_animation(clip)
		if animation.has_marker(&"left_contact"):
			return fposmod(animation.get_marker_time(&"left_contact") / animation.length, 1.0)
	match clip.trim_suffix("_stowed"):
		"walk", "walk_adventure": return 0.0
		"jog", "run": return 1.0 / 24.0
	return -1.0

func _match_gait_phase(next: String) -> float:
	var outgoing_contact := _gait_contact_phase(current_motion)
	var incoming_contact := _gait_contact_phase(next)
	if not uses_gait_transitions() or outgoing_contact < 0.0 or incoming_contact < 0.0:
		return -1.0
	var length := motion.current_animation_length
	if length <= 0.0: return -1.0
	# Both cycles use left contact first. Preserve the side and progress
	# through its half-cycle, even when the clip durations differ.
	var phase := fposmod(motion.current_animation_position / length - outgoing_contact, 1.0)
	if _tempo_contact >= 0.0:
		phase = _tempo_contact
		_tempo_contact = -1.0
	_clear_tempo_plant()
	var support_progress := fposmod(phase, 0.5)
	if _gait_leg_ik.size() == 2 and _gait_stop_elapsed < 0.0 and support_progress < 0.17 and actor.is_on_floor():
		_tempo_plant_side = 0 if phase < 0.5 else 1
		_tempo_plant_position = skeleton.to_global(skeleton.get_bone_global_pose(_gait_foot_bones[_tempo_plant_side]).origin)
		# Release before the outgoing foot would lift again.
		_tempo_plant_left = minf(0.14, (0.20 - support_progress) * length / maxf(motion.speed_scale, 0.45))
	return fposmod(phase + incoming_contact, 1.0) * motion.get_animation(next).length

func _clear_tempo_plant() -> void:
	if _tempo_plant_left > 0.0:
		_gait_leg_ik[_tempo_plant_side].influence = 0.0
		_tempo_plant_left = 0.0

func _apply_tempo_plant(dt: float) -> void:
	if _tempo_plant_left <= 0.0: return
	if not actor.is_on_floor() or staff_strike_active():
		_clear_tempo_plant()
		return
	_tempo_plant_left = maxf(0.0, _tempo_plant_left - dt)
	_gait_ankles[_tempo_plant_side].global_position = _tempo_plant_position
	_gait_leg_ik[_tempo_plant_side].influence = smoothstep(0.0, 0.09, _tempo_plant_left)

func staff_strike_active() -> bool:
	return loaded and visible and current_motion == "staff_strike"

func staff_action_active() -> bool:
	return staff_strike_active() or (visible and (_staff_overlay_time >= 0.0 or _workshop_cast_time >= 0.0 or _profile_action != null))

func configure_staff_profile(library: AnimationLibrary) -> String:
	if not loaded or not is_instance_valid(_back_weapon):return "У персонажа нет посоха с креплением."
	if staff_action_active():return "Сначала заверши действие."
	var profile := StaffProfile.read(library)
	var error := StaffProfile.validate(library, profile)
	if not error.is_empty():return error
	_staff_profile = profile.duplicate(true)
	_staff_poses = profile.poses.duplicate()
	var target := motion.get_animation_library("")
	for name: StringName in [profile.draw] + profile.actions.values():
		if not name.is_empty():target.add_animation(name,library.get_animation(name))
	_staff_overlay_time = -1.0
	_staff_idle_left = 0.0
	_profile_attached = _staff_ready
	return ""

func staff_profile_state() -> String:
	if _profile_action != null:return String(_profile_slot) + (" · отмена" if _profile_cancel>=0.0 else "")
	if _staff_overlay_time>=0.0:return "доставание" if _staff_drawing else "уборка"
	return "в руке" if _staff_ready else "за спиной"

func set_staff_equipped(held: bool) -> String:
	if _staff_profile.is_empty():return "Профиль не подключён."
	if _profile_action != null:return "Сначала отмени или заверши действие."
	if animation_action_context().is_empty():return "Доступно стоя или на ходу."
	if _staff_profile_hand_busy():return "Правая рука занята другим взаимодействием."
	if _staff_overlay_time<0.0:
		if held==_staff_ready:return ""
		_staff_overlay_time = 0.0 if held else motion.get_animation(_staff_profile.draw).length
	_staff_drawing = held
	return ""

func play_staff_profile_action(slot: StringName) -> String:
	if _staff_profile.is_empty() or slot not in StaffProfile.SLOTS:return "Неизвестный слот."
	if not _staff_ready or _staff_overlay_time>=0.0:return "Сначала достань посох."
	if _profile_action != null:return "Действие уже выполняется."
	if animation_action_context().is_empty():return "Доступно стоя или на ходу."
	if _staff_profile_hand_busy():return "Правая рука занята другим взаимодействием."
	var name: StringName = _staff_profile.actions.get(slot,&"")
	if name.is_empty():return "Слот пока не назначен."
	_profile_action = motion.get_animation(name)
	_profile_action_time = 0.0;_profile_action_emitted = false;_profile_slot = slot;_profile_cancel = -1.0
	return ""

func _staff_profile_hand_busy() -> bool:
	if actor.has_meta("ember_carried_item"):return true
	if actor.has_method("carried_crate") and actor.carried_crate()!=null:return true
	for hand:WallHand in _wall_hands:
		if hand.side<0.0 and hand.ik.influence>0.001:return true
	return false

func cancel_staff_profile_action() -> void:
	if _profile_action!=null and _profile_cancel<0.0:
		_profile_cancel_weight = StaffProfile.pose_weight(_profile_action,_profile_action_time)
		_profile_cancel = 0.0

func _update_staff_profile(dt: float) -> void:
	if _profile_action != null:
		if _swimming_pose or _falling or _mantle_active or _cable_weight>0.0 or _staff_profile_hand_busy():cancel_staff_profile_action()
		if _profile_cancel>=0.0:_profile_cancel += dt
		else:_profile_action_time = minf(_profile_action_time+dt,_profile_action.length)
	if _staff_overlay_time>=0.0:
		var length := motion.get_animation(_staff_profile.draw).length
		_staff_overlay_time = clampf(_staff_overlay_time + (dt if _staff_drawing else -dt),0.0,length)
		if (_staff_drawing and _staff_overlay_time>=length) or (not _staff_drawing and _staff_overlay_time<=0.0):
			_staff_ready = _staff_drawing
			_staff_overlay_time = -1.0

func _apply_staff_profile() -> void:
	_set_workshop_hand_driver(false)
	var draw := motion.get_animation(_staff_profile.draw)
	var seconds := _staff_overlay_time if _staff_overlay_time>=0.0 else (draw.length if _staff_ready else 0.0)
	var phase := seconds/draw.length
	var attached := seconds>=draw.get_marker_time(_staff_profile.attach_marker)
	var chest := skeleton.global_transform*skeleton.get_bone_global_pose(_back_weapon_bone)
	var holstered := avatar.global_transform.affine_inverse()*chest*_back_weapon_socket.transform
	# Both binding rules share the exact holster transform at the marker.
	# Keep the common parent: reparenting mid-frame would create a second owner.
	_back_weapon.transform = MotionControls.draw_pose(draw,phase,holstered,_staff_ready_pose()) if attached else holstered
	var ready := MotionControls.weight(draw,&"ready_blend",phase,phase)
	(_back_weapon.get_node("RightGrip/Wrist") as Marker3D).position.z = lerpf(_staff_profile.pickup_grip,_staff_poses.grip,ready)
	(avatar.get_node("RightElbowHint") as Node3D).position = MotionControls.sample(draw,&"elbow_hint",phase,Vector3(-0.49,0.83,-0.15))
	_set_staff_grip(MotionControls.weight(draw,&"grip_weight",phase,phase))
	if attached != _profile_attached:
		_profile_attached = attached
		staff_profile_event.emit(&"grip" if attached else &"release",&"equipment",draw.get_marker_time(_staff_profile.attach_marker))
	if _profile_action==null:return
	var weight := StaffProfile.pose_weight(_profile_action,_profile_action_time)
	if _profile_cancel>=0.0:weight = _profile_cancel_weight*(1.0-smoothstep(0.0,0.20,_profile_cancel))
	var delta := _staff_chest_motion()
	var contact := _back_weapon.to_local((_back_weapon.get_node("RightGrip/Wrist") as Node3D).global_position)
	_back_weapon.transform = StaffProfile.interpolate_at_contact(_staff_poses.staff_pose(delta,false),_staff_poses.staff_pose(delta,true),contact,weight)
	if _profile_cancel<0.0 and not _profile_action_emitted and _profile_slot!=&"guard" and _profile_action_time>=_profile_action.get_marker_time(&"impact"):
		_profile_action_emitted = true
		staff_profile_event.emit(&"impact",_profile_slot,_profile_action.get_marker_time(&"impact"))
	if _profile_cancel>=0.20 or (_profile_cancel<0.0 and _profile_action_time>=_profile_action.length):
		_profile_action = null;_profile_cancel = -1.0

func has_trial_staff() -> bool:
	return loaded and visible and motion.has_animation(&"staff_strike")

func staff_needs_draw() -> bool:
	return has_trial_staff() and not _staff_ready and motion.has_animation(&"staff_draw")

func crate_motion_duration(action: String, fallback: float) -> float:
	var name: StringName = MotionControls.ACTIONS.get(action, &"")
	return motion.get_animation(name).length if not name.is_empty() and motion.has_animation(name) else fallback

func crate_motion_weight(action: String, channel: StringName, phase: float, fallback: float) -> float:
	var name: StringName = MotionControls.ACTIONS.get(action, &"")
	return MotionControls.weight(motion.get_animation(name), channel, phase, fallback) if not name.is_empty() and motion.has_animation(name) else fallback

func _staff_draw_seconds() -> float:
	return motion.get_animation(MotionControls.DRAW).length if motion.has_animation(MotionControls.DRAW) else motion.get_animation(&"staff_draw").length

func staff_impact_delay() -> float:
	var draw := _staff_draw_seconds() if _staff_overlay_time >= 0.0 and _staff_drawing else 0.0
	return staff_contact_time() + draw

func staff_contact_time() -> float:
	var clip := motion.get_animation(&"staff_strike")
	return clampf(clip.get_marker_time(&"impact"), 0.0, clip.length) if clip.has_marker(&"impact") else minf(0.38, clip.length)

func begin_battle_staff_strike(direction: Vector3) -> bool:
	if _battle_staff or not has_trial_staff():
		return false
	_battle_previous_process_mode = process_mode
	_battle_staff = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if staff_strike_active():
		motion.stop()
	if staff_action_active() and not _staff_ready:
		_staff_overlay_time = -1.0
	return begin_staff_action(direction, true)

func battle_staff_at_contact() -> bool:
	if not staff_strike_active():
		return not staff_action_active()
	return not motion.is_playing() or motion.current_animation_position >= staff_contact_time()

func end_battle_staff_strike() -> void:
	if not _battle_staff:
		return
	_battle_staff = false
	process_mode = _battle_previous_process_mode

signal spell_released(origin: Vector3, direction: Vector3)
var spell_aim_point := Vector3.INF
var _spell_released := false

func begin_staff_action(direction: Vector3, strike: bool, allow_workshop_cast := false) -> bool:
	if not has_trial_staff():
		return false
	_spell_released = false
	_workshop_cast_time = -1.0
	var layer := WorkshopCast.read_for(skeleton) if allow_workshop_cast and not _battle_staff else {}
	_workshop_cast = layer.get("tracks", {})
	_workshop_authored = layer.has("grip")
	_workshop_authored_grip = layer.get("grip", Quaternion.IDENTITY)
	rotation.y = atan2(direction.x, direction.z)
	wait_for_gait_stop_contact(false)
	set_gait_braking(false)
	_animation_lod.flush(motion)
	motion.speed_scale = 1.0
	_staff_idle_left = 0.0
	if staff_needs_draw():
		_staff_overlay_time = 0.0
		_staff_drawing = true
		_strike_after_staff_draw = strike
	else:
		_start_staff_cast()
	return true

func _start_staff_cast() -> void:
	if not _workshop_cast.is_empty():
		_workshop_entry_arm = _workshop_ready_arm.duplicate() if _staff_overlay_time < 0.0 else {}
		_workshop_cast_time = 0.0
	else:
		current_motion = "staff_strike"
		motion.play(current_motion, 0.09)

func _update_staff(dt: float) -> void:
	if not _staff_profile.is_empty():
		_update_staff_profile(dt)
		return
	if _workshop_cast_time >= 0.0:
		_workshop_cast_time = minf(_workshop_cast_time + dt, motion.get_animation(StaffPoses.CAST).length)
		return
	if _staff_overlay_time >= 0.0:
		_staff_overlay_time += dt
		if _staff_overlay_time >= _staff_draw_seconds():
			_staff_overlay_time = -1.0
			if _staff_drawing:
				_staff_ready = true
				if _strike_after_staff_draw:
					_start_staff_cast()
				else:
					_staff_idle_left = STAFF_READY_SECONDS
		return
	if current_motion == "staff_strike" and not motion.is_playing():
		current_motion = ""
		_staff_idle_left = STAFF_READY_SECONDS if _staff_ready else 0.0
	elif _staff_idle_left > 0.0:
		_staff_idle_left -= dt
		if _staff_idle_left <= 0.0:
			_staff_ready = false
			_staff_overlay_time = 0.0
			_staff_drawing = false

func _apply_staff_overlay() -> void:
	if not _staff_profile.is_empty():
		_apply_staff_profile()
		return
	if _workshop_cast_time >= 0.0:
		var clip := motion.get_animation(StaffPoses.CAST)
		for bone: int in _workshop_cast:
			if _workshop_right_arm.has(bone):
				continue
			var pose := skeleton.get_bone_pose_rotation(bone)
			_workshop_cast_base[bone] = pose
			skeleton.set_bone_pose_rotation(bone, _workshop_bone_pose(bone, pose, _workshop_cast_time / clip.length))
		_prepare_workshop_ready_hand()
		return
	if _workshop_authored and _staff_ready and _staff_overlay_time < 0.0 and not staff_strike_active() and not _swimming_pose:
		_prepare_workshop_ready_hand()
		return
	_set_workshop_hand_driver(false)
	if is_instance_valid(_back_weapon) and staff_strike_active():
		var clip := motion.get_animation(StaffPoses.CAST)
		var seconds := motion.current_animation_position
		_staff_poses.apply_spell_pose(_back_weapon, skeleton, _back_weapon_bone, clip, seconds, spell_aim_point)
		_release_staff_spell(seconds)
		return
	if is_instance_valid(_back_weapon_socket) and not _staff_ready and not staff_strike_active():
		var chest := skeleton.global_transform * skeleton.get_bone_global_pose(_back_weapon_bone)
		_back_weapon.global_transform = chest * _back_weapon_socket.transform
	if is_instance_valid(_back_weapon):
		var wrist := _back_weapon.get_node("RightGrip/Wrist") as Marker3D
		wrist.position.z = 0.0
		if _staff_ready and not staff_strike_active() and not _swimming_pose:
			_back_weapon.transform = _staff_ready_pose()
			wrist.position.z = _staff_poses.grip
			_set_staff_grip(1.0)
	if _staff_overlay_time < 0.0: return
	if not motion.has_animation(MotionControls.DRAW):
		return
	var clip := motion.get_animation(MotionControls.DRAW)
	var phase := clampf(_staff_overlay_time / clip.length, 0.0, 1.0)
	if not _staff_drawing:
		phase = 1.0 - phase
	var staff := _back_weapon
	staff.transform = MotionControls.draw_pose(clip, phase, staff.transform, _staff_ready_pose())
	var ready_weight := MotionControls.weight(clip, &"ready_blend", phase, phase)
	(staff.get_node("RightGrip/Wrist") as Marker3D).position.z = lerpf(0.18, _staff_poses.grip, ready_weight)
	var elbow: Vector3 = MotionControls.sample(clip, &"elbow_hint", phase, Vector3(-0.49, 0.83, -0.15))
	(avatar.get_node("RightElbowHint") as Node3D).position = elbow
	_set_staff_grip(MotionControls.weight(clip, &"grip_weight", phase, phase))

func _install_workshop_hand_attachment() -> void:
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	_workshop_right_arm = {bones.rightUpperArm: 0.85, bones.rightLowerArm: 0.75, bones.rightHand: 0.30}
	_workshop_ready_wrist = Marker3D.new()
	_workshop_ready_wrist.name = "WorkshopReadyWrist"
	avatar.add_child(_workshop_ready_wrist)
	var palm_mount := BoneAttachment3D.new()
	palm_mount.name = "RightPalmAttachment"
	palm_mount.bone_name = skeleton.get_bone_name(bones.rightHand)
	skeleton.add_child(palm_mount)
	_workshop_palm = Marker3D.new()
	_workshop_palm.name = "GripContact"
	_workshop_palm.position = _staff_poses.right_palm_contact
	palm_mount.add_child(_workshop_palm)
	_workshop_staff_contact = _back_weapon.get_node("RightGrip/Contact") as Marker3D
	var modifier := CastHandModifier.new()
	modifier.name = "WorkshopCastHand"
	modifier.apply_hand_pose = _apply_workshop_hand_pose
	skeleton.add_child(modifier)

func _set_workshop_hand_driver(enabled: bool) -> void:
	if enabled == _workshop_hand_drives_staff:
		return
	_workshop_hand_drives_staff = enabled
	var wrist := _back_weapon.get_node("RightGrip/Wrist") as Marker3D
	var target := _workshop_ready_wrist if enabled else wrist
	var ik := skeleton.get_node("RightGripIK") as TwoBoneIK3D
	var copy := skeleton.get_node("RightGripRotation") as CopyTransformModifier3D
	ik.set_target_node(0, ik.get_path_to(target))
	copy.set_reference_node(0, copy.get_path_to(target))

func _prepare_workshop_ready_hand() -> void:
	_set_workshop_hand_driver(true)
	var wrist := _back_weapon.get_node("RightGrip/Wrist") as Marker3D
	wrist.position.z = _staff_poses.grip
	var grip_from_staff := _back_weapon.global_transform.affine_inverse() * wrist.global_transform
	# The neutral IK target is independent of the actual staff transform.
	_workshop_ready_wrist.transform = _staff_ready_pose() * grip_from_staff
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(bones.rightUpperArm).origin)
	var hint := avatar.get_node("RightElbowHint") as Marker3D
	hint.position = avatar.to_local(shoulder) + Vector3(-0.24, -0.36, -0.14)
	_set_staff_grip(1.0)

func _apply_workshop_hand_pose() -> void:
	var active := _workshop_cast_time >= 0.0 and _workshop_hand_drives_staff
	var bones: Dictionary = avatar.get_meta("hoshi_bones")
	var hand: int = bones.rightHand
	if not active:
		if _staff_ready and not staff_strike_active():
			if _workshop_authored and _workshop_hand_drives_staff and _workshop_cast.has(hand):
				skeleton.set_bone_pose_rotation(hand, _workshop_grasp_pose(hand, 0.0))
				_attach_workshop_staff(hand)
			for bone: int in _workshop_right_arm:
				_workshop_ready_arm[bone] = skeleton.get_bone_pose_rotation(bone)
		else:
			_workshop_ready_arm.clear()
		return
	var clip := motion.get_animation(StaffPoses.CAST)
	var seconds := _workshop_cast_time
	var phase := seconds / clip.length
	var entry_weight := smoothstep(0.0, 0.16, seconds)
	for bone: int in _workshop_right_arm:
		var pose := skeleton.get_bone_pose_rotation(bone)
		if _workshop_entry_arm.has(bone):
			var entry: Quaternion = _workshop_entry_arm[bone]
			pose = entry.slerp(pose, entry_weight)
		if _workshop_cast.has(bone):
			if _workshop_authored and bone == hand:
				pose = _workshop_grasp_pose(bone, phase)
			else:
				pose = _workshop_bone_pose(bone, pose, phase, _workshop_right_arm[bone])
		skeleton.set_bone_pose_rotation(bone, pose)
	_attach_workshop_staff(hand)
	_release_staff_spell(seconds, true)
	if seconds >= clip.length:
		_workshop_cast_time = -1.0
		_staff_idle_left = STAFF_READY_SECONDS

func _attach_workshop_staff(hand: int) -> void:
	var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	var wrist := _back_weapon.get_node("RightGrip/Wrist") as Marker3D
	var grip_from_staff := _back_weapon.global_transform.affine_inverse() * wrist.global_transform
	var grip_basis := grip_from_staff.basis.inverse()
	if _workshop_authored:
		var clearance := Quaternion(Vector3.UP, deg_to_rad(_staff_poses.right_palm_grip_yaw_degrees))
		grip_basis = Basis(_workshop_grasp_tilt() * _workshop_authored_grip * clearance)
	_workshop_staff_contact.position.z = _staff_poses.grip
	var object_contact := _back_weapon.global_transform.affine_inverse() * _workshop_staff_contact.global_transform
	_back_weapon.global_transform = StaffPoses.align_grip(hand_world, _workshop_palm.transform, object_contact, grip_basis)

func _workshop_grasp_tilt() -> Quaternion:
	return Quaternion(Vector3.BACK, deg_to_rad(_staff_poses.right_palm_grip_tilt_degrees))

func _workshop_grasp_pose(hand: int, phase: float) -> Quaternion:
	return WorkshopCast.sample(_workshop_cast[hand], phase) * _workshop_grasp_tilt().inverse()

func _workshop_authored_weight(phase: float) -> float:
	return smoothstep(0.0, 0.32, phase) * (1.0 - smoothstep(0.76, 1.0, phase))

func _workshop_bone_pose(bone: int, base: Quaternion, phase: float, influence := 1.0) -> Quaternion:
	if _workshop_authored:
		return base.slerp(WorkshopCast.sample(_workshop_cast[bone], phase), _workshop_authored_weight(phase))
	var delta := WorkshopCast.sample_cast(_workshop_cast[bone], phase)
	return Quaternion.IDENTITY.slerp(delta, influence) * base

func _release_staff_spell(seconds: float, hand_driven := false) -> void:
	if _spell_released or seconds < staff_contact_time():
		return
	_spell_released = true
	var gem := _back_weapon.get_node("Geometry/Gem") as Node3D
	var direction := _back_weapon.global_basis.z.normalized()
	if hand_driven and spell_aim_point.is_finite() and gem.global_position.distance_squared_to(spell_aim_point) > 0.000001:
		direction = gem.global_position.direction_to(spell_aim_point)
	spell_released.emit(gem.global_position, direction)

func _staff_ready_pose() -> Transform3D:
	return _staff_poses.staff_pose(_staff_chest_motion(), false)

func _staff_chest_motion() -> Transform3D:
	return _staff_poses.chest_motion(avatar, skeleton, _back_weapon_bone)

func _set_staff_grip(grip: float) -> void:
	(skeleton.get_node("RightGripIK") as SkeletonModifier3D).influence = grip
	(skeleton.get_node("RightGripRotation") as SkeletonModifier3D).influence = grip
	(skeleton.get_node("LeftGripIK") as SkeletonModifier3D).influence = 0.0
	(skeleton.get_node("LeftGripRotation") as SkeletonModifier3D).influence = 0.0

func _unhandled_key_input(event: InputEvent) -> void:
	if not loaded or not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_K and motion.has_animation(&"idle_alt"):
		_use_alt_idle = not _use_alt_idle
	elif event.physical_keycode == KEY_L and motion.has_animation(&"walk_adventure"):
		_use_original_walk = not _use_original_walk
	elif event.physical_keycode == KEY_F9 and uses_gait_transitions():
		_toggle_step_debug()
		get_viewport().set_input_as_handled()

func _toggle_step_debug() -> void:
	if is_instance_valid(_step_debug_view):
		_step_debug_view.visible = not _step_debug_view.visible
		_step_debug_label.visible = _step_debug_view.visible
		return
	_step_debug_mesh = ImmediateMesh.new()
	_step_debug_view = MeshInstance3D.new()
	_step_debug_view.top_level = true
	_step_debug_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_step_debug_view.mesh = _step_debug_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_step_debug_view.material_override = material
	add_child(_step_debug_view)
	_step_debug_view.global_transform = Transform3D.IDENTITY
	var overlay := CanvasLayer.new()
	overlay.layer = 12
	add_child(overlay)
	_step_debug_label = Label.new()
	overlay.add_child(_step_debug_label)
	_step_debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_step_debug_label.position = Vector2(20, get_viewport().get_visible_rect().size.y - 105)
	_step_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step_debug_label.add_theme_constant_override("outline_size", 5)

func _draw_step_debug() -> void:
	if not is_instance_valid(_step_debug_view) or not _step_debug_view.visible: return
	_step_debug_label.visible = is_visible_in_tree()
	if not _step_debug_label.visible: return
	var phase := motion.current_animation_position / maxf(motion.current_animation_length, 0.001)
	var state := "финальный шаг" if _gait_stop_elapsed >= 0.0 else "ждём касания" if _gait_waiting_contact else "движение"
	var notes := PackedStringArray()
	var has_stop := _gait_stop_elapsed >= 0.0 and _gait_foot_start.size() == 2
	var has_ik := _gait_leg_ik.size() == 2 and (_gait_leg_ik[0].influence > 0.05 or _gait_leg_ik[1].influence > 0.05)
	_step_debug_mesh.clear_surfaces()
	if not _step_debug_samples.is_empty() or has_stop or has_ik:
		_step_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for sample in _step_debug_samples:
			var status: String = sample.status
			var color := Color.TOMATO if status == "промах" else Color.GOLD if status == "запасная" else Color.PALE_GREEN
			var target: Vector3 = sample.to
			_debug_step_line(sample.from, target, color)
			_debug_step_cross(target, color, 0.22 if sample.next else 0.10)
			if sample.next:
				_debug_step_line(target, target + Vector3.UP * unit * 0.30, color)
			notes.append("%s %s: %s" % ["Л" if sample.side == 0 else "П", "след." if sample.next else "сейчас", status])
		if has_stop:
			_debug_step_cross(_gait_foot_start[_gait_support], Color.DEEP_SKY_BLUE, 0.14)
			_debug_step_cross(_gait_landing, Color.VIOLET, 0.14)
		elif has_ik:
			for side in 2:
				if _gait_leg_ik[side].influence > 0.05:
					_debug_step_cross(_gait_ankles[side].global_position, Color.DEEP_SKY_BLUE if side == 0 else Color.VIOLET, 0.09)
		_step_debug_mesh.surface_end()
	_step_debug_label.text = "F9 · Шаги    %s    фаза %.2f    %s\n%s\nЗелёный: опора · жёлтый: запасная · красный: промах · синий/фиолетовый: цели IK" % [
		_gait_band(current_motion), phase, state, "   ".join(notes)]

func _debug_step_line(start: Vector3, finish: Vector3, color: Color) -> void:
	_step_debug_mesh.surface_set_color(color)
	_step_debug_mesh.surface_add_vertex(start)
	_step_debug_mesh.surface_add_vertex(finish)

func _debug_step_cross(at: Vector3, color: Color, radius: float) -> void:
	at.y += unit * 0.012
	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		var offset: Vector3 = axis * unit * radius
		_debug_step_line(at - offset, at + offset, color)

func animation_action_context() -> StringName:
	if _mantle_active or _cable_weight > 0.0 or (staff_action_active() and _staff_profile.is_empty()) or _swimming_pose or _falling:
		return &""
	if current_motion.begins_with("idle"):
		return &"stand"
	if current_motion.begins_with("walk"):
		return &"walk"
	return &""

func animation_action_occupied() -> PackedStringArray:
	var occupied := PackedStringArray()
	var left := skeleton.get_node_or_null("LeftGripIK") as SkeletonModifier3D
	if left != null and left.influence > 0.001:
		occupied.append(String(AnimationAction.LEFT))
	for hand: WallHand in _wall_hands:
		if hand.side > 0.0 and hand.ik.influence > 0.001 and String(AnimationAction.LEFT) not in occupied:
			occupied.append(String(AnimationAction.LEFT))
	return occupied

func play_animation_action(clip_name: StringName) -> String:
	if not loaded or not motion.has_animation(clip_name):
		return "Клип действия не загружен."
	if _action_layer == null:
		_action_layer = ActionModifier.new()
		_action_layer.name = "AnimationAction"
		skeleton.add_child(_action_layer)
	return _action_layer.request(motion.get_animation(clip_name), animation_action_context(), animation_action_occupied())

func _process(dt:float)->void:
	if not loaded or not is_instance_valid(actor):return
	if _action_layer != null:
		_action_layer.update_context(animation_action_context(), animation_action_occupied())
	for bone: int in _workshop_cast_base:
		skeleton.set_bone_pose_rotation(bone, _workshop_cast_base[bone])
	_workshop_cast_base.clear()
	avatar.position -= _crate_body_clearance
	var bracing: bool = _crate_push_left > 0.0 and _pushed_crate != null and is_instance_valid(_pushed_crate.get_ref()) and not actor.uses_crate_magic()
	# The exploration capsule is narrower than a forward step.
	var brace_offset := global_basis.inverse() * _crate_push_normal * (unit * 0.24) if bracing else Vector3.ZERO
	_crate_body_clearance = _crate_body_clearance.move_toward(brace_offset, dt * (4.0 if bracing else 1.6))
	avatar.position += _crate_body_clearance
	if _jog_turn_chest >= 0:
		skeleton.set_bone_pose_rotation(_jog_turn_chest, _jog_turn_chest_base)
		_jog_turn_chest = -1
	for hand: WallHand in _wall_hands:
		if hand.clavicle_overlaid:
			skeleton.set_bone_pose_rotation(hand.clavicle, hand.clavicle_base)
			hand.clavicle_overlaid = false
	_update_animation_importance()
	_update_staff(dt)
	_moving_land_left = maxf(0.0, _moving_land_left - dt)
	age+=dt
	var body := actor as CharacterBody3D
	var velocity := Vector3.ZERO if _battle_staff else (body.get_real_velocity() if body != null else follower_velocity) / unit
	velocity.y=0
	speed_mps=lerpf(speed_mps,velocity.length(),1.0-exp(-12.0*dt))
	var pushing_with_magic: bool = actor.has_method("magic_push_active") and actor.magic_push_active()
	var turn := _face_jog_reversal(dt) if uses_gait_transitions() and not pushing_with_magic and not _mantle_active else 0.0
	if body != null and not _mantle_active and _jog_reverse_direction == 0.0 and velocity.length()>0.08 and not staff_strike_active() and not pushing_with_magic and _cable_weight <= 0.0:
		var heading := atan2(velocity.x, velocity.z)
		turn = angle_difference(rotation.y, heading)
		if uses_gait_transitions():
			_sample_jog_turn(turn)
		rotation.y=lerp_angle(rotation.y,heading,1.0-exp(-12.0*dt))
	elif _jog_reverse_direction == 0.0 and uses_gait_transitions():
		_sample_jog_turn(0.0)
	var next:=_select_motion()
	if next!=current_motion:
		_animation_lod.flush(motion)
		var matched_time := _match_gait_phase(next)
		var blend := 0.18
		if uses_gait_transitions() and (current_motion.begins_with("idle") or next.begins_with("idle")):
			blend = 0.26
		if next.begins_with("swim") != current_motion.begins_with("swim"):
			blend = 0.40
		motion.play(next, blend)
		if next == "land_stowed":
			_landing_requested = false
		elif next == "roll_stowed":
			_roll_requested = false
		if matched_time >= 0.0:
			motion.seek(matched_time, false)
		current_motion = next
	var clip_speed := 0.0
	match next.trim_suffix("_stowed"):
		"walk", "walk_adventure": clip_speed = _walk_clip_speed
		"jog": clip_speed = _jog_clip_speed
		"run": clip_speed = _run_clip_speed
	motion.speed_scale = clampf(speed_mps / (clip_speed * _terrain_stride), 0.45, 1.5) if clip_speed > 0.0 else 1.0
	if next == "land_stowed":
		motion.speed_scale = 2.35
	elif next == "roll_stowed":
		motion.speed_scale = 1.4
	if _gait_waiting_contact and motion.current_animation_length > 0.0:
		var half_cycle := motion.current_animation_length * 0.5
		var contact_offset := maxf(0.0, _gait_contact_phase(current_motion)) * motion.current_animation_length
		var until_contact := half_cycle - fposmod(motion.current_animation_position - contact_offset, half_cycle)
		if until_contact > 0.0001:
			motion.speed_scale = minf(motion.speed_scale, until_contact / maxf(dt, 0.00001))
	if not Engine.is_editor_hint():
		# Always resolve this viewport's current camera: map/camera changes are normal.
		var camera:=get_viewport().get_camera_3d()
		if is_instance_valid(camera) and camera.get_world_3d()!=get_world_3d():camera=null
		var center:=global_position+Vector3.UP*height_m*unit*0.5
		if _animation_lod.advance(motion,dt,camera,center,height_m*unit,unit,_animation_full_rate,is_visible_in_tree())<0.0:return
		if not _gait_leg_ik.is_empty():
			_apply_stance_support(dt)
			_apply_terrain_step(dt)
			_apply_jog_turn(turn, dt)
			if _moving_land_left > 0.0 and _gait_contact_phase(current_motion) >= 0.0:
				var impact := sin(PI * _moving_land_left / 0.30)
				avatar.position.y -= impact * 0.065
				var bones: Dictionary = avatar.get_meta("hoshi_bones")
				var chest: int = bones.chest
				var chest_pose := skeleton.get_bone_pose_rotation(chest)
				skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, impact * 0.13) * chest_pose)
			var swim_offset_goal := _swim_depth
			if _swimming_pose and _swim_entry_time < 0.52:
				var head := skeleton.to_global(skeleton.get_bone_global_pose(_terrain_head).origin)
				var head_height := (head.y - actor.global_position.y) / unit
				var at_waterline := maxf(0.0, _swim_depth + 0.07 - head_height)
				swim_offset_goal = lerpf(at_waterline, _swim_depth, smoothstep(0.34, 0.52, _swim_entry_time))
			_swim_visual_offset = lerpf(_swim_visual_offset, swim_offset_goal, 1.0 - exp(-18.0 * dt))
			avatar.position.y += _swim_visual_offset
		_apply_staff_overlay()
		_apply_tempo_plant(dt)
		_apply_gait_stop(dt)
		if not _apply_mantle_hands() and not _apply_cable_grip(dt) and not _apply_door_reach() and not _apply_crate_pose(dt):
			_update_wall_hand(dt)
		_draw_step_debug()
	# Native morph targets are kept; no replacement face or exported rest edits.
	var blink:=pow(maxf(0.0,cos(age*TAU/4.6)),80.0)
	for target in blink_targets:target[0].set_blend_shape_value(target[1],blink)
