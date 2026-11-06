extends SceneTree
## Real AnimationPlayer bone/morph evaluation, not a duplicate tier calculator.
const Lod = preload("res://scripts/ember_animation_distance_lod.gd")
const Hoshi = preload("res://scripts/ember_hoshi_visual.gd")
const Player = preload("res://scripts/ember_player.gd")
const Followers = preload("res://scripts/ember_party_followers.gd")

class Leader extends Player:
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class Party extends Followers:
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class Body extends CharacterBody3D:
	var physics_ticks := 0
	func _physics_process(_delta: float) -> void: physics_ticks += 1

class SpringProbe extends RefCounted:
	# The modifier signal also fires when inactive. Count actual local bone
	# changes against the just-evaluated animation, not signal emissions.
	var rig: Skeleton3D
	var joints: Dictionary = {}
	var animated_pose: Dictionary = {}
	var changed_samples := 0
	var max_deviation := 0.0
	var finite_pose := true
	func bind(visual: Node3D) -> void:
		rig = visual.skeleton
		for spring: SpringBoneSimulator3D in rig.find_children("*", "SpringBoneSimulator3D", true, false):
			for setting in spring.setting_count:
				for joint in spring.get_joint_count(setting):
					joints[spring.get_joint_bone(setting, joint)] = true
			spring.modification_processed.connect(observe)
		visual.motion.mixer_applied.connect(remember_pose)
		remember_pose()
	func remember_pose() -> void:
		for bone in joints:
			animated_pose[bone] = rig.get_bone_pose_rotation(bone)
	func observe() -> void:
		var changed := false
		for bone in joints:
			var reference: Quaternion = animated_pose[bone]
			var rotation := rig.get_bone_pose_rotation(bone)
			finite_pose = finite_pose and reference.is_finite() and rotation.is_finite()
			var difference := minf((reference - rotation).length(), (reference + rotation).length())
			var deviation := 4.0 * asin(clampf(difference * 0.5, 0.0, 1.0))
			max_deviation = maxf(max_deviation, deviation)
			changed = changed or deviation > 0.0001
		if changed: changed_samples += 1
	func clear() -> void:
		changed_samples = 0
		max_deviation = 0.0
		finite_pose = true

var errors: Array[String] = []
var counts: Dictionary = {}
var evaluations := 0
var body: Body
var visual: Node3D
var camera: Camera3D
var player: AnimationPlayer
var rig: Skeleton3D
var face: MeshInstance3D


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		printerr("ANIMATION_LOD_FAIL ", label)


func make_fixture() -> void:
	body = Body.new()
	root.add_child(body)
	visual = Hoshi.new()
	body.add_child(visual)
	visual.set_process(false)
	visual.actor = body
	visual.unit = 1.0
	visual.loaded = true
	visual.current_motion = "idle"
	rig = Skeleton3D.new()
	rig.name = "Rig"
	rig.add_bone("Root")
	visual.add_child(rig)
	visual.skeleton = rig
	face = MeshInstance3D.new()
	face.name = "Face"
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Fcl_EYE_Close")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var shape := arrays.duplicate(true)
	shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3(0, 0.8, 0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
	face.mesh = mesh
	visual.add_child(face)
	visual.blink_targets = [[face, 0]]
	player = AnimationPlayer.new()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.add_child(player)
	visual.motion = player
	var library := AnimationLibrary.new()
	for clip in ["idle", "walk", "run"]:
		var animation := Animation.new()
		animation.length = 10.0
		animation.loop_mode = Animation.LOOP_LINEAR
		var bone_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(bone_track, ^"Rig:Root")
		animation.position_track_insert_key(bone_track, 0.0, Vector3.ZERO)
		animation.position_track_insert_key(bone_track, 10.0, Vector3(10, 0, 0))
		var morph_track := animation.add_track(Animation.TYPE_BLEND_SHAPE)
		animation.track_set_path(morph_track, ^"Face:Fcl_EYE_Close")
		animation.blend_shape_track_insert_key(morph_track, 0.0, 0.0)
		animation.blend_shape_track_insert_key(morph_track, 10.0, 1.0)
		library.add_animation(clip, animation)
	player.add_animation_library("", library)
	player.mixer_applied.connect(func(): evaluations += 1)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.make_current()


func reset_motion() -> void:
	player.stop()
	player.speed_scale = 1.0
	player.play("idle")
	player.advance(0.0)
	evaluations = 0


func sample(label: String, distance: float, shown := true, protected := false,
		has_camera := true, behind := false, frames := 120) -> Lod:
	reset_motion()
	var scheduler := Lod.new(17)
	camera.position = Vector3(0, 0.74, -distance if behind else distance)
	camera.rotation = Vector3.ZERO
	for frame in frames:
		scheduler.advance(player, 1.0 / 120.0, camera if has_camera else null,
			Vector3(0, 0.74, 0), 1.48, 1.0, protected, shown)
	counts[label] = evaluations
	return scheduler


func run() -> void:
	root.size = Vector2i(1280, 720)
	make_fixture()
	var scheduler := sample("near", 8.0)
	check(evaluations == 120, "near character evaluates every frame")
	sample("near_offscreen",8.0,true,false,true,true)
	check(evaluations == 120,"near offscreen caster retains smooth animation")
	check(is_equal_approx(player.current_animation_position, 1.0), "near animation uses real elapsed time")
	check(absf(rig.get_bone_pose_position(0).x - 1.0) < 0.001, "bone track actually evaluates")
	check(absf(face.get_blend_shape_value(0) - 0.1) < 0.001, "native morph track actually evaluates")
	scheduler = sample("middle", 25.0)
	check(evaluations >= 29 and evaluations <= 31, "middle character evaluates at 30Hz")
	scheduler = sample("far", 65.0)
	check(evaluations >= 14 and evaluations <= 16, "far character evaluates at 15Hz")
	var before := player.current_animation_position
	var flushed := scheduler.flush(player)
	check(flushed < 1.0 / 15.0 + 0.001, "far sampling leaves bounded pending time")
	check(absf(player.current_animation_position - 1.0) < 0.001 and before <= 1.0, "far phase retains full elapsed time")
	scheduler = sample("offscreen", 25.0, true, false, true, true)
	check(evaluations >= 4 and evaluations <= 6, "offscreen character evaluates at 5Hz")
	scheduler = sample("hidden", 25.0, false)
	check(evaluations >= 1 and evaluations <= 3, "hidden character evaluates at 2Hz")
	# Return must immediately consume elapsed time, rather than wait for its old slot.
	for frame in 7:
		scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, false)
	camera.position.z = 8.0
	var old_count := evaluations
	scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, true)
	check(evaluations == old_count + 1, "visible near return refreshes pose immediately")
	check(absf(player.current_animation_position - 128.0 / 120.0) < 0.001, "return preserves elapsed animation phase")
	sample("no_camera", 65.0, false, false, false)
	check(evaluations == 120, "missing camera falls back to full rate even while hidden")
	sample("party_wide", 400.0, true, true, true, true)
	check(evaluations == 120, "party stays full rate with distant camera and offscreen")
	# Existing owner identity, including subclasses; do not invent party metadata.
	var leader := Leader.new()
	root.add_child(leader)
	check(Lod.is_party_visual(leader), "actual EmberPlayer subclass is protected")
	var party := Party.new()
	root.add_child(party)
	var follower := Node3D.new()
	party.add_child(follower)
	check(Lod.is_party_visual(follower), "actual EmberPartyFollowers descendant is protected")
	check(not Lod.is_party_visual(body), "ordinary CharacterBody is eligible for LOD")
	leader.free()
	party.free()
	# Hysteresis: movement around the same boundary must not promote to full rate.
	scheduler = sample("hysteresis_start", 20.0)
	evaluations = 0
	for frame in 120:
		camera.position.z = 15.9 if frame % 2 == 0 else 16.1
		scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, true)
	counts.hysteresis = evaluations
	check(evaluations >= 29 and evaluations <= 31, "boundary oscillation keeps 30Hz tier")
	# Playback speed is integrated at the original tick, not applied retroactively.
	reset_motion()
	scheduler = Lod.new(9)
	camera.position.z = 65.0
	for frame in 120:
		player.speed_scale = 0.5 if frame < 60 else 1.5
		scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, true)
	scheduler.flush(player)
	check(absf(player.current_animation_position - 1.0) < 0.001, "varying speed preserves integrated clip phase")
	check(player.speed_scale == 1.5, "sampling preserves speed_scale owner")
	# Clip switching uses the elapsed old clip, then starts the new one now.
	for frame in 3:
		scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, true)
	scheduler.flush(player)
	player.play("walk", 0.18)
	scheduler.advance(player, 1.0 / 120.0, null, Vector3.ZERO, 1.48, 1.0, false, true)
	check(absf(player.current_animation_position - 1.5 / 120.0) < 0.001, "new clip does not inherit old clip's pending time")
	var traces: Array = []
	for seed_value in [1, 2]:
		reset_motion()
		scheduler = Lod.new(seed_value)
		var trace: Array[int] = []
		for frame in 120:
			var previous := evaluations
			scheduler.advance(player, 1.0 / 120.0, camera, Vector3(0, 0.74, 0), 1.48, 1.0, false, true)
			if evaluations > previous: trace.append(frame)
		traces.append(trace)
	check(traces[0] != traces[1] and absi(traces[0].size() - traces[1].size()) <= 1, "different characters distribute evaluations across frames")
	# Actual Hoshi presentation path: sampling gates both native bone and blink writes.
	reset_motion()
	visual._animation_lod = Lod.new(17)
	visual.age = 0.0
	visual.current_motion = "idle"
	camera.position.z = 65.0
	for frame in 120:
		visual._process(1.0 / 120.0)
	counts.hoshi_far = evaluations
	check(evaluations >= 14 and evaluations <= 16, "Hoshi path actually uses distance sampling")
	visual.important_character = true
	visual._process(1.0 / 120.0)
	check(absf(rig.get_bone_pose_position(0).x - 121.0 / 120.0) < 0.001, "Hoshi return updates native skeleton to current phase")
	var blink := pow(maxf(0.0, cos(visual.age * TAU / 4.6)), 80.0)
	check(absf(face.get_blend_shape_value(0) - blink) < 0.001, "Hoshi return updates native blink to elapsed age")
	var physics_before := body.physics_ticks
	await physics_frame
	await physics_frame
	await process_frame
	check(body.physics_ticks > physics_before and body.is_physics_processing(), "animation sampling leaves controller physics running")
	# Ignored local avatar is optional in other checkouts; verify the real setup here.
	var native_info := {"available": ResourceLoader.exists(Hoshi.AVATAR_PATH) and ResourceLoader.exists(Hoshi.MOTION_PATH)}
	if native_info.available:
		var native_leader := Leader.new()
		root.add_child(native_leader)
		var native_visual := Hoshi.new()
		native_leader.add_child(native_visual)
		native_visual.set_process(false)
		check(native_visual.setup(native_leader, 16.0), "native Hoshi setup succeeds")
		check(native_visual._animation_full_rate, "native setup protects the actual leader")
		check(native_visual.motion.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "native setup disables automatic double advancement")
		native_info.bones = native_visual.skeleton.get_bone_count()
		native_info.modifiers = native_visual.skeleton.find_children("*", "SkeletonModifier3D", true, false).size()
		native_info.modifier_classes = []
		var active_party_springs := 0
		for modifier in native_visual.skeleton.find_children("*", "SkeletonModifier3D", true, false):
			native_info.modifier_classes.append({"class": modifier.get_class(), "active": modifier.active})
			if modifier is SpringBoneSimulator3D and modifier.active: active_party_springs += 1
		check(active_party_springs > 0, "native party keeps authored active spring chains")
		native_info.active = native_visual.motion.active
		var rest := native_visual.skeleton.get_bone_rest(0)
		var cached_clip := native_visual.motion.get_animation("idle")
		var length_before := cached_clip.length
		native_visual.motion.advance(0.0)
		evaluations = 0
		native_visual.motion.mixer_applied.connect(func(): evaluations += 1)
		camera.position.z = 4000.0
		for frame in 120: native_visual._process(1.0 / 120.0)
		native_info.evaluations = evaluations
		check(evaluations == 120, "native Hoshi leader remains smooth at wide camera distance")
		check(native_visual.skeleton.get_bone_rest(0) == rest and cached_clip.length == length_before, "native sampling preserves original rest and source clip")
		check(native_visual.skeleton.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE, "party keeps native modifier callback mode")
		native_leader.free()
		var native_npc := Hoshi.new()
		body.add_child(native_npc)
		native_npc.set_process(false)
		check(native_npc.setup(body, 1.0), "native nonparty Hoshi setup succeeds")
		native_npc.motion.advance(0.0)
		var springs := native_npc.skeleton.find_children("*", "SpringBoneSimulator3D", true, false)
		check(not springs.is_empty(), "native avatar has actual spring chains")
		for spring: SpringBoneSimulator3D in springs:
			check(not spring.active, "ordinary NPC spring is disabled at setup")
			# RAM-only stimulus makes enabled springs a positive work control.
			spring.external_force = Vector3(6, 0, 0)
		var probe := SpringProbe.new()
		probe.bind(native_npc)
		native_npc.motion.mixer_applied.connect(func(): evaluations += 1)
		for distance in [65.0, 8.0]:
			camera.position.z = distance
			native_npc._process(1.0 / 120.0)
			await process_frame
			evaluations = 0
			probe.clear()
			for frame in 120:
				native_npc._process(1.0 / 120.0)
				await process_frame
			var label := "npc_far" if distance > 40.0 else "npc_near"
			native_info[label] = {"poses": evaluations, "spring_changed_samples": probe.changed_samples, "spring_max_radians": probe.max_deviation}
			check(evaluations >= 14 and evaluations <= 16 if distance > 40.0 else evaluations == 120, label + " retains body sampling")
			check(probe.changed_samples == 0, label + " has zero actual spring bone changes")
		# Hub hero is important independently of the active-party owner or count.
		native_npc.important_character = true
		check(native_npc._animation_full_rate and not Lod.is_party_visual(body), "explicit hub importance is independent of party")
		for spring: SpringBoneSimulator3D in springs:
			check(spring.active, "hub hero restores authored active springs")
		camera.position.z = 4000.0
		evaluations = 0
		probe.clear()
		for frame in 120:
			native_npc._process(1.0 / 120.0)
			await process_frame
		native_info.hub_hero = {"poses": evaluations, "spring_changed_samples": probe.changed_samples, "spring_max_radians": probe.max_deviation}
		check(evaluations == 120, "nonparty important hub hero retains full rate offscreen")
		check(probe.changed_samples > 0, "probe observes actual native hub hair simulation")
		check(native_npc.skeleton.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE, "hub hero retains native spring callback")
		native_npc.important_character = false
		for spring: SpringBoneSimulator3D in springs:
			check(not spring.active, "importance demotion immediately disables springs")
		# Hidden -> visible catch-up must keep secondary motion finite.
		native_npc.hide()
		for frame in 65:
			native_npc._process(1.0 / 120.0)
			await process_frame
		native_npc.show()
		body.position.x += 100.0
		native_npc.important_character = true
		camera.position.z = 8.0
		probe.clear()
		native_npc._process(1.0 / 120.0)
		await process_frame
		var finite_pose := true
		for bone in native_npc.skeleton.get_bone_count():
			finite_pose = finite_pose and native_npc.skeleton.get_bone_pose_rotation(bone).is_finite()
		check(finite_pose and probe.finite_pose, "importance return resets native history after hidden gap and teleport")
		native_info.importance_return_finite = finite_pose and probe.finite_pose
		native_npc.free()
	# Mixed authored states must survive repeated policy transitions.
	var policy_rig := Skeleton3D.new()
	root.add_child(policy_rig)
	var authored_on := SpringBoneSimulator3D.new()
	var authored_off := SpringBoneSimulator3D.new()
	policy_rig.add_child(authored_on)
	policy_rig.add_child(authored_off)
	authored_off.active = false
	var policy := Lod.new()
	policy.bind_skeleton(policy_rig, false)
	check(not authored_on.active and not authored_off.active, "NPC disables mixed authored springs")
	for transition in 3:
		policy.set_secondary_motion_enabled(true)
		check(authored_on.active and not authored_off.active, "importance restores only authored active state")
		policy.set_secondary_motion_enabled(false)
		check(not authored_on.active and not authored_off.active, "demotion keeps all springs off")
	policy_rig.free()
	body.free()
	camera.free()
	await process_frame
	print("ANIMATION_DISTANCE_LOD ", JSON.stringify({"pass": errors.is_empty(), "errors": errors, "evaluations_per_120_frames": counts, "native_hoshi": native_info}))
	quit(0 if errors.is_empty() else 1)
