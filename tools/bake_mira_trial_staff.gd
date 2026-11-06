extends SceneTree

const STANCE := Vector3(-0.23, 0.91, 0.20)
const UPRIGHT := Vector3(-0.10, 1.0, 0.12)
const TIMES := [0.0, 0.13, 0.26, 0.38, 0.48, 0.70, 0.86]
const HANDS := [STANCE, Vector3(-0.18,1.00,0.22), Vector3(-0.12,1.29,0.15), Vector3(-0.10,1.00,0.29), Vector3(-0.12,0.89,0.26), Vector3(-0.19,0.93,0.23), STANCE]
const TIPS := [UPRIGHT, Vector3(0.25,0.95,0.1), Vector3(0.21,0.89,-0.41), Vector3(0.12,-0.31,0.94), Vector3(0.14,-0.70,0.70), Vector3(0.03,0.96,0.25), UPRIGHT]
const RIGHT_GRIP := Vector3(-0.067, -0.018, 0.0)
const LEFT_GRIP := Vector3(0.067, -0.018, 0.0)
const DRAW_SECONDS := 0.70
const BACK_OFFSET := Vector3(-0.13, 0.88, -0.16)
const BACK_TIP := Vector3(-0.52, 0.85, -0.05)

var skeleton: Skeleton3D
var player: AnimationPlayer
var bones: Dictionary

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 3]:
		push_error("Pass the base Mira AnimationLibrary path, a distinct output path, and optionally a traversal clip library.")
		quit(2)
		return
	var library := load(args[0]) as AnimationLibrary
	if library == null or args[0] == args[1] or library.has_animation(&"staff_strike"):
		push_error("Expected an unmodified Mira trial library and a distinct output path.")
		quit(2)
		return
	var actor := (load("res://assets/local_characters/hoshi/avatar.scn") as PackedScene).instantiate()
	root.add_child(actor)
	player = actor.get_node("Motion")
	skeleton = actor.get_node("Skeleton3D")
	bones = actor.get_meta("hoshi_bones")
	if player.has_animation_library(""): player.remove_animation_library("")
	player.add_animation_library("", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clips := {}
	for name in library.get_animation_list():
		clips[name] = bake(name, library.get_animation(name), false)
		clips[String(name) + "_stowed"] = bake_carry(name, library.get_animation(name), false)
	if args.size() == 3:
		var traversal := load(args[2]) as AnimationLibrary
		assert(traversal != null)
		player.add_animation_library("traversal", traversal)
		for name in traversal.get_animation_list():
			var clip := traversal.get_animation(name)
			if name == &"land":
				clip = soften_landing(clip, library.get_animation("idle"))
				traversal.remove_animation(name)
				traversal.add_animation(name, clip)
			clips[String(name) + "_stowed"] = bake_carry("traversal/" + String(name), clip, false)
	clips["staff_strike"] = bake("idle", library.get_animation("idle"), true)
	clips["staff_draw"] = bake_carry("idle", library.get_animation("idle"), true)
	var output := AnimationLibrary.new()
	for key in library.get_meta_list():
		output.set_meta(key, library.get_meta(key))
	player.play("idle")
	player.seek(0.0, true)
	var chest := skeleton.get_bone_global_pose(bones.chest)
	output.set_meta("back_weapon_socket", chest.affine_inverse() * Transform3D(shaft_basis(BACK_TIP.normalized(), deg_to_rad(76.0)), BACK_OFFSET))
	for name in clips:
		output.add_animation(name, clips[name])
	assert(ResourceSaver.save(output, args[1], ResourceSaver.FLAG_COMPRESS) == OK)
	quit()

func soften_landing(source: Animation, idle: Animation) -> Animation:
	var result := source.duplicate() as Animation
	for track in result.get_track_count():
		var kind := result.track_get_type(track)
		var reference := idle.find_track(result.track_get_path(track), kind)
		if reference < 0: continue
		for key in result.track_get_key_count(track):
			var base: Variant = idle.track_get_key_value(reference, 0)
			var value: Variant = result.track_get_key_value(track, key)
			if kind == Animation.TYPE_ROTATION_3D:
				result.track_set_key_value(track, key, base.slerp(value, 0.55))
			elif kind == Animation.TYPE_POSITION_3D:
				result.track_set_key_value(track, key, base.lerp(value, 0.55))
	return result

func bake_carry(name: String, source: Animation, draw: bool) -> Animation:
	var anim := source.duplicate() as Animation
	if draw:
		anim.length = DRAW_SECONDS
		anim.loop_mode = Animation.LOOP_NONE
	var position := add_track(anim, Animation.TYPE_POSITION_3D, ^"MiraStaff")
	var rotation := add_track(anim, Animation.TYPE_ROTATION_3D, ^"MiraStaff")
	var hint := add_track(anim, Animation.TYPE_POSITION_3D, ^"RightElbowHint")
	var right_ik := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/RightGripIK:influence")
	var right_roll := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/RightGripRotation:influence")
	var left_ik := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/LeftGripIK:influence")
	var left_roll := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/LeftGripRotation:influence")
	var fall_arms := {}
	if name == "traversal/fall":
		for bone: int in [bones.rightUpperArm, bones.rightLowerArm, bones.leftUpperArm, bones.leftLowerArm]:
			var track := anim.find_track(NodePath("Skeleton3D:" + skeleton.get_bone_name(bone)), Animation.TYPE_ROTATION_3D)
			if track >= 0:
				fall_arms[bone] = track
				while anim.track_get_key_count(track) > 0:
					anim.track_remove_key(track, 0)
	anim.track_insert_key(left_ik, 0.0, 0.0)
	anim.track_insert_key(left_roll, 0.0, 0.0)
	# The holster is defined in the standing chest frame. Swimming
	# starts with a lowered torso, so its first frame is not the bind pose.
	player.play("idle" if name.begins_with("traversal/swim") else name)
	player.seek(0.0, true)
	var chest_base := skeleton.get_bone_global_pose(bones.chest)
	player.play(name)
	player.seek(0.0, true)
	var back_basis := shaft_basis(BACK_TIP.normalized(), deg_to_rad(76.0))
	var frames := int(ceil(anim.length * 60.0))
	for frame in range(frames + 1):
		var time := anim.length * float(frame) / frames
		player.seek(time, true)
		if not fall_arms.is_empty():
			var sway := sin(TAU * time / anim.length) * 0.025
			pose_limb(bones.rightUpperArm, bones.rightLowerArm, bones.rightHand, Vector3(-0.27, 1.25 + sway, 0.12), Vector3(-1, -0.25, -0.25))
			pose_limb(bones.leftUpperArm, bones.leftLowerArm, bones.leftHand, Vector3(0.27, 1.25 - sway, 0.12), Vector3(1, -0.25, -0.25))
			for bone: int in fall_arms:
				anim.rotation_track_insert_key(fall_arms[bone], time, skeleton.get_bone_pose_rotation(bone))
		var chest_motion := skeleton.get_bone_global_pose(bones.chest) * chest_base.affine_inverse()
		var back := chest_motion * Transform3D(back_basis, BACK_OFFSET)
		var carry := back
		var grip := 0.0
		if draw:
			grip = smoothstep(0.0, 0.22, time)
			var out := Transform3D(shaft_basis(Vector3(-0.70, 0.64, -0.30).normalized(), deg_to_rad(76.0)), Vector3(-0.32, 1.32, 0.05))
			var ready := Transform3D(shaft_basis(UPRIGHT.normalized(), deg_to_rad(76.0)), STANCE)
			carry = back.interpolate_with(out, smoothstep(0.22, 0.47, time)) if time < 0.47 else out.interpolate_with(ready, smoothstep(0.47, DRAW_SECONDS, time))
		carry = skeleton.transform * carry
		anim.position_track_insert_key(position, time, carry.origin)
		anim.rotation_track_insert_key(rotation, time, carry.basis.get_rotation_quaternion())
		anim.position_track_insert_key(hint, time, skeleton.transform * Vector3(-0.56, 1.0, -0.12))
		anim.track_insert_key(right_ik, time, grip)
		anim.track_insert_key(right_roll, time, grip)
	return anim

func bake(name: String, source: Animation, strike: bool) -> Animation:
	var anim := source.duplicate() as Animation
	if strike:
		anim.clear()
		anim.length = TIMES[-1]
		anim.loop_mode = Animation.LOOP_NONE
	var tracks := {}
	var edited := [bones.rightUpperArm, bones.rightLowerArm, bones.rightHand]
	var curled := {}
	for side in ["right", "left"]:
		if side == "left" and not strike: continue
		for finger in ["Index", "Middle", "Ring", "Little"]:
			curled[bones[side + finger + "Proximal"]] = 38.0 if side == "right" else -38.0
			for segment in ["Intermediate", "Distal"]:
				curled[bones[side + finger + segment]] = 54.0 if side == "right" else -54.0
	if strike:
		edited.append_array([bones.chest, bones.leftUpperArm, bones.leftLowerArm, bones.leftHand,
			bones.leftUpperLeg, bones.leftLowerLeg, bones.leftFoot,
			bones.rightUpperLeg, bones.rightLowerLeg, bones.rightFoot])
	edited.append_array(curled.keys())
	if strike:
		for t in source.get_track_count():
			var path := source.track_get_path(t)
			var id := skeleton.find_bone(path.get_subname(0))
			if id < 0 or id in edited: continue
			var dst := anim.add_track(source.track_get_type(t))
			anim.track_set_path(dst, path)
			var value: Variant = source.track_get_key_value(t, 0)
			anim.track_insert_key(dst, 0.0, value)
			anim.track_insert_key(dst, anim.length, value)
	for id in edited:
		var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(id))
		var track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if track >= 0: anim.remove_track(track)
	for id in edited:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton3D:" + skeleton.get_bone_name(id)))
		tracks[id] = t
	var hips_track := -1
	if strike:
		var hips_path := NodePath("Skeleton3D:" + skeleton.get_bone_name(bones.hips))
		hips_track = anim.find_track(hips_path, Animation.TYPE_POSITION_3D)
		if hips_track < 0:
			hips_track = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(hips_track, hips_path)
		anim.track_remove_key_at_time(hips_track, 0.0)
		anim.track_remove_key_at_time(hips_track, anim.length)
	var staff_position := add_track(anim, Animation.TYPE_POSITION_3D, ^"MiraStaff")
	var staff_rotation := add_track(anim, Animation.TYPE_ROTATION_3D, ^"MiraStaff")
	var left_roll := add_track(anim, Animation.TYPE_ROTATION_3D, ^"MiraStaff/LeftGripFrame")
	var right_hint := add_track(anim, Animation.TYPE_POSITION_3D, ^"RightElbowHint")
	var left_hint := add_track(anim, Animation.TYPE_POSITION_3D, ^"LeftElbowHint")
	var left_weight := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/LeftGripIK:influence")
	var left_rotation_weight := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/LeftGripRotation:influence")
	var right_weight := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/RightGripIK:influence")
	var right_rotation_weight := add_track(anim, Animation.TYPE_VALUE, ^"Skeleton3D/RightGripRotation:influence")
	anim.track_insert_key(right_weight, 0.0, 1.0)
	anim.track_insert_key(right_rotation_weight, 0.0, 1.0)

	var frames := int(ceil(anim.length * 60.0))
	for frame in range(frames + 1):
		var time := anim.length * float(frame) / frames
		skeleton.reset_bone_poses()
		player.play(name)
		player.seek(0.0 if strike else time, true)
		var hand := STANCE
		var tip := UPRIGHT
		var grip := 0.0
		var roll := 0.0
		if strike:
			var segment := 0
			while segment < TIMES.size() - 2 and time > TIMES[segment + 1]:
				segment += 1
			var weight := clampf(inverse_lerp(TIMES[segment], TIMES[segment + 1], time), 0.0, 1.0)
			var before := maxi(0, segment - 1)
			var after := mini(TIMES.size() - 1, segment + 2)
			hand = HANDS[segment].cubic_interpolate(HANDS[segment + 1], HANDS[before], HANDS[after], weight)
			tip = TIPS[segment].normalized().slerp(TIPS[segment + 1].normalized(), smoothstep(0.0, 1.0, weight))
			var chest: int = bones.chest
			var accent := smoothstep(0.25, 0.40, time) * (1.0 - smoothstep(0.49, 0.81, time))
			var lean := Quaternion(Vector3.RIGHT, deg_to_rad(24.0 * accent))
			skeleton.set_bone_pose_rotation(chest, lean * skeleton.get_bone_pose_rotation(chest))
			pose_feet(time, accent)
			anim.position_track_insert_key(hips_track, time, skeleton.get_bone_pose_position(bones.hips))
			grip = smoothstep(0.02, 0.16, time) * (1.0 - smoothstep(0.58, 0.81, time))
			roll = deg_to_rad(76.0 - 76.0 * smoothstep(0.16, 0.40, time) * (1.0 - smoothstep(0.48, 0.84, time)))
		elif name not in ["idle", "idle_alt"]:
			hand += Vector3(0.0, -0.04, 0.02) + Vector3.UP * 0.035 * sin(TAU * time / anim.length)
			tip = Vector3(-0.16, 0.87, -0.42)
		pose_arm(hand, tip.normalized(), strike, roll)
		if strike and grip > 0.0:
			# Pull the shaft into the overlap of both arms' reach before closing the grip.
			for attempt in 4:
				var correction := support_reach_correction()
				if correction.length_squared() < 0.000001: break
				hand += correction * grip
				pose_arm(hand, tip.normalized(), strike, roll)
			pose_support_hand(grip)
		# Export prop motion separately. The grip markers themselves stay editable.
		var right := skeleton.get_bone_global_pose(bones.rightHand)
		var prop := skeleton.transform * right
		var left_basis := support_grip().basis
		anim.position_track_insert_key(staff_position, time, prop.origin)
		anim.rotation_track_insert_key(staff_rotation, time, prop.basis.get_rotation_quaternion())
		anim.rotation_track_insert_key(left_roll, time, (right.basis.inverse() * left_basis).get_rotation_quaternion())
		anim.position_track_insert_key(right_hint, time, skeleton.transform * skeleton.get_bone_global_pose(bones.rightLowerArm).origin)
		anim.position_track_insert_key(left_hint, time, skeleton.transform * skeleton.get_bone_global_pose(bones.leftLowerArm).origin)
		anim.track_insert_key(left_weight, time, grip)
		anim.track_insert_key(left_rotation_weight, time, grip)
		for id in edited:
			var q := skeleton.get_bone_pose_rotation(id)
			if curled.has(id):
				var weight := grip if skeleton.get_bone_name(id).begins_with("J_Bip_L_") else 1.0
				q = q * Quaternion(Vector3.BACK, deg_to_rad(float(curled[id]) * weight))
			anim.rotation_track_insert_key(tracks[id], time, q)
	return anim

func add_track(anim: Animation, type: Animation.TrackType, path: NodePath) -> int:
	var index := anim.add_track(type)
	anim.track_set_path(index, path)
	return index

func pose_arm(hand: Vector3, shaft: Vector3, strike: bool, roll: float) -> void:
	var upper: int = bones.rightUpperArm
	var lower: int = bones.rightLowerArm
	var wrist: int = bones.rightHand
	var forearm := pose_limb(upper, lower, wrist, hand, Vector3(-1.0, -0.65, -0.16))
	var hand_x := (-forearm).slide(shaft).normalized()
	if strike:
		# The shaft roll is authored independently so it stays stable when the
		# forearm and shaft briefly point along the same line.
		hand_x = shaft_basis(shaft, roll).x
	var wrist_basis := Basis(hand_x, shaft.cross(hand_x).normalized(), shaft)
	set_global_rotation(wrist, wrist_basis.get_rotation_quaternion())

func shaft_basis(shaft: Vector3, roll: float) -> Basis:
	var across := Vector3.RIGHT.slide(shaft).normalized().rotated(shaft, roll)
	return Basis(across, shaft.cross(across).normalized(), shaft)

func pose_support_hand(weight: float) -> void:
	var left := skeleton.get_bone_global_pose(bones.leftHand)
	var grip := support_grip()
	pose_limb(bones.leftUpperArm, bones.leftLowerArm, bones.leftHand,
		left.origin.lerp(grip.origin, weight), Vector3(1.0, -0.8, -0.18))
	set_global_rotation(bones.leftHand, left.basis.get_rotation_quaternion().slerp(grip.basis.get_rotation_quaternion(), weight))

func support_grip() -> Transform3D:
	var right := skeleton.get_bone_global_pose(bones.rightHand)
	var shaft := right.basis.z.normalized()
	var palm := right * (RIGHT_GRIP + Vector3.BACK * 0.19)
	var across := Vector3.RIGHT.slide(shaft).normalized()
	var basis := Basis(across, shaft.cross(across).normalized(), shaft)
	return Transform3D(basis, palm - basis * LEFT_GRIP)

func support_reach_correction() -> Vector3:
	var shoulder := skeleton.get_bone_global_pose(bones.leftUpperArm).origin
	var reach := skeleton.get_bone_rest(bones.leftLowerArm).origin.length()
	reach += skeleton.get_bone_rest(bones.leftHand).origin.length() - 0.025
	var offset := support_grip().origin - shoulder
	return offset.limit_length(reach) - offset

func pose_feet(time: float, accent: float) -> void:
	var step := smoothstep(0.10, 0.31, time) * (1.0 - smoothstep(0.55, 0.85, time))
	if step <= 0.0: return
	var front := skeleton.get_bone_global_pose(bones.leftFoot)
	var back := skeleton.get_bone_global_pose(bones.rightFoot)
	var hips: int = bones.hips
	var shift := Vector3(0.018, -0.055, 0.035) * accent
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + shift)
	pose_limb(bones.leftUpperLeg, bones.leftLowerLeg, bones.leftFoot, front.origin, Vector3(0.1, 0, 1))
	set_global_rotation(bones.leftFoot, front.basis.get_rotation_quaternion())
	var lift := 0.046 * step + 0.04 * sin(PI * step)
	var ankle := back.origin + Vector3(-0.025 * step, lift, -0.16 * step)
	pose_limb(bones.rightUpperLeg, bones.rightLowerLeg, bones.rightFoot, ankle, Vector3(-0.2, 0, 1))
	var pitch := Quaternion(Vector3.RIGHT, deg_to_rad(19.0 * step))
	set_global_rotation(bones.rightFoot, pitch * back.basis.get_rotation_quaternion())

func pose_limb(upper: int, lower: int, end: int, target: Vector3, bend: Vector3) -> Vector3:
	var start := skeleton.get_bone_global_pose(upper).origin
	var direction := start.direction_to(target)
	var a := skeleton.get_bone_rest(lower).origin.length()
	var b := skeleton.get_bone_rest(end).origin.length()
	var distance := clampf(start.distance_to(target), absf(a - b) + 0.002, a + b - 0.005)
	var along := (a*a - b*b + distance*distance) / (2.0 * distance)
	var pole := bend.slide(direction).normalized()
	var joint := start + direction * along + pole * sqrt(maxf(0.0, a*a - along*along))
	aim(upper, lower, start.direction_to(joint))
	var tip_direction := joint.direction_to(start + direction * distance)
	aim(lower, end, tip_direction)
	return tip_direction

func aim(id: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(id)
	var current := pose.origin.direction_to(skeleton.get_bone_global_pose(child).origin)
	set_global_rotation(id, Quaternion(current, target) * pose.basis.get_rotation_quaternion())

func set_global_rotation(id: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(id)).basis.orthonormalized()
	skeleton.set_bone_pose_rotation(id, (parent.get_rotation_quaternion().inverse() * rotation).normalized())

