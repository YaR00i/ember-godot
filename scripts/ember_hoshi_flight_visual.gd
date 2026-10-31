extends Node3D
## Trial-only attachment; does not modify Hoshi's source, materials or ground rig.
const Hoshi := preload("res://scripts/ember_hoshi_visual.gd")
const Flap := preload("res://scripts/ember_wing_flap_motion.gd")
const WINGS_PATH := "res://assets/local_characters/flight_wings/wing-a001.glb"
var hoshi: Node3D
var wings: Node3D
var wing_animation: AnimationPlayer
var loaded := false
var _lean := 0.0
var wing_skeleton: Skeleton3D

func setup(actor: CharacterBody3D) -> bool:
	hoshi = Hoshi.new()
	add_child(hoshi)
	if not hoshi.setup(actor, 1.0):
		return false
	hoshi.set_process(false)
	hoshi.motion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hoshi.motion.play("idle")
	hoshi.motion.advance(0.0)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(ProjectSettings.globalize_path(WINGS_PATH), state) != OK:
		push_error("Private wing reference missing: " + WINGS_PATH)
		return false
	wings = gltf.generate_scene(state)
	hoshi.add_child(wings)
	wings.position = Vector3(0, 0.98, -0.12)
	wings.scale = Vector3.ONE * 0.72
	var human: Dictionary = hoshi.avatar.get_meta("hoshi_bones", {})
	var chest := int(human.get("chest", human.get("spine", -1)))
	if chest >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "FlightWingAttachment"
		attachment.bone_idx = chest
		hoshi.skeleton.add_child(attachment)
		attachment.transform = hoshi.skeleton.get_bone_global_pose(chest)
		wings.reparent(attachment, true)
	wing_animation = wings.find_child("AnimationPlayer", true, false)
	wing_skeleton = wings.find_children("*", "Skeleton3D", true, false)[0]
	if wing_animation == null or not wing_animation.has_animation("flap"):
		return false
	wing_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in ["start", "flap", "hover", "glide", "dash"]:
		if not wing_animation.has_animation(name):
			return false
		wing_animation.get_animation(name).loop_mode = Animation.LOOP_NONE
	loaded = true
	return true

func update_pose(dt: float, motion: RefCounted) -> void:
	if not loaded:
		return
	var airborne: bool = motion.phase == Flap.Phase.FLYING
	var deploying: bool = motion.phase == Flap.Phase.DEPLOYING
	var ground: bool = motion.phase in [Flap.Phase.STANDING, Flap.Phase.JUMPING]
	wings.visible = not ground
	_lean = lerpf(_lean, 1.0 if airborne or deploying else 0.0, 1.0 - exp(-4.0 * dt))
	# Hoshi has native ground clips only. Body lean is a trial pose, not an
	# extracted humanoid flight animation; the wing clips themselves are native.
	var body_clip := "idle"
	if ground:
		var local_velocity: Vector3 = hoshi.actor.global_basis.inverse() * hoshi.actor.velocity
		local_velocity.y = 0.0
		if local_velocity.length() > 0.1:
			hoshi.rotation.y = lerp_angle(hoshi.rotation.y, atan2(local_velocity.x, local_velocity.z), 1.0 - exp(-12.0 * dt))
			body_clip = "walk"
	else:
		hoshi.rotation.y = lerp_angle(hoshi.rotation.y, PI, 1.0 - exp(-10.0 * dt))
	hoshi.rotation.x = deg_to_rad(65.0) * _lean
	if hoshi.motion.current_animation != body_clip:
		hoshi.motion.play(body_clip, 0.18)
	hoshi.motion.advance(dt)
	var clip := "glide" if airborne else "hover"
	var time := 0.0
	var cocoon: float = motion.cocoon_progress()
	if cocoon >= 0.0:
		clip = "dash"
		time = cocoon
	elif motion.flap_age >= 0.0:
		clip = "flap"
		time = motion.flap_age / Flap.FLAP_SECONDS
	elif motion.brake_input > 0.1:
		clip = "hover"
	# Visual barrel roll around the torso; the physical pose and camera do not spin.
	rotation.z = TAU * smoothstep(0.08, 0.90, cocoon) if cocoon >= 0.0 else 0.0
	var pivot := Vector3(0, 0.7, 0)
	position = pivot - basis * pivot
	if wing_animation.current_animation != clip:
		wing_animation.play(clip, 0.14)
	wing_animation.advance(dt)
	wing_animation.seek(clampf(time, 0.0, 1.0) * wing_animation.get_animation(clip).length, true)
	if cocoon >= 0.0:
		var fold := smoothstep(0.0, 0.18, cocoon) * (1.0 - smoothstep(0.65, 1.0, cocoon))
		var human: Dictionary = hoshi.avatar.get_meta("hoshi_bones", {})
		for side in ["left", "right"]:
			for part in [["UpperLeg", -70.0], ["LowerLeg", 120.0]]:
				var bone := int(human.get(side + part[0], -1))
				if bone >= 0:
					hoshi.skeleton.set_bone_pose_rotation(bone, hoshi.skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, deg_to_rad(part[1]) * fold))
		_fold_cocoon(fold)

func _fold_cocoon(amount: float) -> void:
	# Adapted closure around Hoshi, not a claim that the game's post-process
	# constraints were recovered. Both spars curl in front, then down/back.
	var tangents := [Vector3(0.45, 0.1, 0.75), Vector3(0.05, -0.35, 0.4),
		Vector3(-0.15, -0.65, 0), Vector3(-0.2, -0.6, -0.35),
		Vector3(-0.15, -0.3, -0.6), Vector3(-0.05, -0.1, -0.6)]
	for side in ["L", "R"]:
		for joint in range(1, 7):
			var bone := wing_skeleton.find_bone(side + "_WingA00" + str(joint))
			var child := wing_skeleton.find_bone(side + "_WingA00" + str(joint + 1)) if joint < 6 else wing_skeleton.find_bone(side + "_WingA_end")
			if bone < 0 or child < 0:
				continue
			var current := wing_skeleton.get_bone_global_pose(bone)
			var direction := wing_skeleton.get_bone_global_pose(child).origin - current.origin
			if direction.length() < 0.0001:
				continue
			var tangent: Vector3 = tangents[joint - 1]
			if side == "R": tangent.x *= -1.0
			var swing := Quaternion(direction.normalized(), tangent.normalized())
			var wanted := Basis(Quaternion.IDENTITY.slerp(swing, amount)) * current.basis
			var parent := wing_skeleton.get_bone_parent(bone)
			if parent >= 0:
				wanted = wing_skeleton.get_bone_global_pose(parent).basis.inverse() * wanted
			wing_skeleton.set_bone_pose_rotation(bone, wanted.get_rotation_quaternion())
