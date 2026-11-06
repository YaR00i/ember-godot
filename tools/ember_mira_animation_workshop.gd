@tool
extends CharacterBody3D
## Uses Godot's AnimationPlayer timeline and transform gizmos.

const SOCKET_PATH := "res://scenes/props/mira_back_weapon_socket.tscn"
const LIBRARY_PATH := "res://assets/local_characters/hoshi/mira_motion_editable.tres"
const StaffPoses = preload("res://scripts/ember_mira_staff_poses.gd")
const MotionControls = preload("res://scripts/ember_mira_motion_controls.gd")
# Staff geometry center in weapon-local coordinates. The saved socket still uses
# the weapon origin expected by the runtime and the grip animations.
const STAFF_PIVOT := Vector3(-0.067, -0.018, 0.39)

@export_storage var player_path: NodePath
@export_storage var skeleton_path: NodePath
@export_storage var socket_path: NodePath
@export_storage var staff_path: NodePath
@export_storage var chest_bone := -1

@export_tool_button("Сохранить библиотеку клипов") var save_clips_action: Callable = save_clips
@export_tool_button("Применить крепление в игре") var save_socket_action: Callable = save_socket
@export_tool_button("Вернуть сохранённое крепление") var reload_socket_action: Callable = reload_socket
@export_group("Позы посоха")
@export_enum("Клип", "Посох сбоку", "Левитация") var staff_pose_preview := 0
@export var staff_poses: StaffPoses
@export_tool_button("Сохранить позы в игре") var save_staff_poses_action: Callable = save_staff_poses
@export_tool_button("Вернуть сохранённые позы") var reload_staff_poses_action: Callable = reload_staff_poses

var _socket_hash := ""
var _staff_poses_hash := ""
var _crate_preview: MeshInstance3D
var _door_preview_wrist: Transform3D
var _door_preview_active := false
var _cable_preview: MeshInstance3D
var _cable_preview_wrist: Transform3D
var _cable_preview_active := false
var _cable_preview_knees := {}

func _ready() -> void:
	process_priority = 50
	var motion := get_node_or_null(player_path) as AnimationPlayer
	if motion != null:
		var avatar := motion.get_node_or_null(motion.root_node)
		if avatar != null and not avatar.has_node(MotionControls.CHANNELS):
			var controls := MotionControls.new()
			controls.name = String(MotionControls.CHANNELS)
			avatar.add_child(controls)
			if Engine.is_editor_hint():
				controls.owner = self
		var library := motion.get_animation_library("")
		if library != null:
			MotionControls.add_missing(library)
			MotionControls.add_contact_markers(library)
		motion.mixer_applied.connect(_sync_stowed_staff)
	reload_socket()
	reload_staff_poses()
	if not Engine.is_editor_hint() and motion != null:
		motion.play(&"idle_stowed")

func _process(_dt: float) -> void:
	_sync_stowed_staff()

func _sync_stowed_staff() -> void:
	var motion := get_node_or_null(player_path) as AnimationPlayer
	var skeleton := get_node_or_null(skeleton_path) as Skeleton3D
	var socket := get_node_or_null(socket_path) as Marker3D
	var staff := get_node_or_null(staff_path) as Node3D
	if motion == null or skeleton == null or socket == null or staff == null or chest_bone < 0:
		return
	var wrist := staff.get_node("RightGrip/Wrist") as Marker3D
	var left_wrist := staff.get_node("LeftGripFrame/LeftGrip/Wrist") as Marker3D
	if _door_preview_active:
		wrist.transform = _door_preview_wrist
		_door_preview_active = false
	if _cable_preview_active:
		wrist.transform = _door_preview_wrist
		left_wrist.transform = _cable_preview_wrist
		for bone: int in _cable_preview_knees:
			skeleton.set_bone_pose_rotation(bone, _cable_preview_knees[bone])
		_cable_preview_knees.clear()
		_cable_preview_active = false
		_cable_preview.hide()
	if is_instance_valid(_crate_preview):
		_crate_preview.hide()
	if staff_pose_preview == 0 and motion.is_animation_active() and motion.assigned_animation == MotionControls.CABLE:
		var avatar := staff.get_parent() as Node3D
		staff.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(chest_bone) * socket.transform.translated_local(-STAFF_PIVOT)
		_door_preview_wrist = wrist.transform
		_cable_preview_wrist = left_wrist.transform
		_cable_preview_active = true
		for side: float in [-1.0, 1.0]:
			var hand := wrist if side < 0.0 else left_wrist
			var fingers := Vector3.BACK * side
			hand.global_transform = avatar.global_transform * Transform3D(
				Basis(fingers, Vector3.DOWN, fingers.cross(Vector3.DOWN)), Vector3(side * 0.105, 1.46, 0.0)
			)
		(avatar.get_node("RightElbowHint") as Marker3D).position = Vector3(-0.37, 1.09, -0.05)
		(avatar.get_node("LeftElbowHint") as Marker3D).position = Vector3(0.37, 1.09, -0.05)
		for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
			(skeleton.get_node(modifier_name) as SkeletonModifier3D).influence = 1.0
		var clip := motion.get_animation(MotionControls.CABLE)
		var tuck := MotionControls.weight(clip, &"hang_tuck", motion.current_animation_position / clip.length, 0.35)
		var bones: Dictionary = avatar.get_meta("hoshi_bones")
		for key in ["leftLowerLeg", "rightLowerLeg"]:
			var bone: int = bones[key]
			var pose := skeleton.get_bone_pose_rotation(bone)
			_cable_preview_knees[bone] = pose
			skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, tuck) * pose)
		if not is_instance_valid(_cable_preview):
			_cable_preview = MeshInstance3D.new()
			var line := CylinderMesh.new()
			line.top_radius = 0.03
			line.bottom_radius = 0.03
			line.height = 2.1
			_cable_preview.mesh = line
			_cable_preview.position = Vector3(0.0, 1.495, 0.0)
			_cable_preview.rotation.z = PI * 0.5
			avatar.add_child(_cable_preview)
		_cable_preview.show()
		return
	if staff_pose_preview == 0 and motion.is_animation_active() and motion.assigned_animation == MotionControls.DOOR:
		var avatar := staff.get_parent() as Node3D
		staff.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(chest_bone) * socket.transform.translated_local(-STAFF_PIVOT)
		_door_preview_wrist = wrist.transform
		_door_preview_active = true
		wrist.global_transform = avatar.global_transform * Transform3D(
			Basis(Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT), Vector3(-0.16, 0.90, 0.30)
		)
		(avatar.get_node("RightElbowHint") as Marker3D).position = Vector3(-0.48, 0.81, 0.03)
		var clip := motion.get_animation(MotionControls.DOOR)
		var phase := motion.current_animation_position / clip.length
		var grip := MotionControls.weight(clip, &"grip_weight", phase, phase)
		for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
			(skeleton.get_node(modifier_name) as SkeletonModifier3D).influence = grip if modifier_name.begins_with("Right") else 0.0
		return
	if staff_pose_preview == 0 and staff_poses != null and motion.is_animation_active() and motion.assigned_animation in MotionControls.ACTIONS.values():
		_preview_crate_action(motion, skeleton, staff)
		return
	if staff_pose_preview == 0 and staff_poses != null and motion.assigned_animation == StaffPoses.CAST:
		staff_poses.apply_spell_pose(staff, skeleton, chest_bone, motion.get_animation(StaffPoses.CAST), motion.current_animation_position)
		return
	if staff_pose_preview == 0 and staff_poses != null and motion.is_animation_active() and motion.assigned_animation == MotionControls.DRAW:
		var avatar := staff.get_parent() as Node3D
		var clip := motion.get_animation(MotionControls.DRAW)
		var phase := motion.current_animation_position / clip.length
		var chest := skeleton.global_transform * skeleton.get_bone_global_pose(chest_bone)
		var holstered := avatar.global_transform.affine_inverse() * chest * socket.transform.translated_local(-STAFF_PIVOT)
		var ready := staff_poses.staff_pose(staff_poses.chest_motion(avatar, skeleton, chest_bone), false)
		staff.transform = MotionControls.draw_pose(clip, phase, holstered, ready)
		var ready_weight := MotionControls.weight(clip, &"ready_blend", phase, phase)
		(staff.get_node("RightGrip/Wrist") as Marker3D).position.z = lerpf(0.18, staff_poses.grip, ready_weight)
		(avatar.get_node("RightElbowHint") as Marker3D).position = MotionControls.sample(clip, &"elbow_hint", phase, Vector3(-0.49, 0.83, -0.15))
		var grip := MotionControls.weight(clip, &"grip_weight", phase, phase)
		for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
			(skeleton.get_node(modifier_name) as SkeletonModifier3D).influence = grip if modifier_name.begins_with("Right") else 0.0
		return
	if staff_pose_preview != 0 and staff_poses != null and staff_poses.is_valid():
		var avatar := staff.get_parent() as Node3D
		staff.transform = staff_poses.staff_pose(staff_poses.chest_motion(avatar, skeleton, chest_bone), staff_pose_preview == 2)
		(staff.get_node("RightGrip/Wrist") as Marker3D).position.z = staff_poses.grip
		(avatar.get_node("RightElbowHint") as Marker3D).position = Vector3(-0.48, 0.87, -0.05)
		for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
			var modifier := skeleton.get_node(modifier_name) as SkeletonModifier3D
			modifier.influence = 1.0 if modifier_name.begins_with("Right") else 0.0
		return
	(staff.get_node("RightGrip/Wrist") as Marker3D).position.z = 0.0
	if motion.assigned_animation.is_empty() or motion.assigned_animation.ends_with("_stowed"):
		for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
			(skeleton.get_node(modifier_name) as SkeletonModifier3D).influence = 0.0
		staff.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(chest_bone) * socket.transform.translated_local(-STAFF_PIVOT)

func _preview_crate_action(motion: AnimationPlayer, skeleton: Skeleton3D, staff: Node3D) -> void:
	var avatar := staff.get_parent() as Node3D
	var name := motion.assigned_animation
	var clip := motion.get_animation(name)
	var phase := motion.current_animation_position / clip.length
	var travel := MotionControls.weight(clip, &"crate_travel", phase, phase)
	var pose := staff_poses.staff_pose(staff_poses.chest_motion(avatar, skeleton, chest_bone), true)
	if name == &"crate_throw":
		var direction := pose.basis.z.lerp(Vector3.BACK, MotionControls.weight(clip, &"aim_forward", phase, phase))
		var hand := pose.origin + pose.basis.z * staff_poses.grip
		pose.basis = Basis.looking_at(direction, Vector3.UP, true)
		pose.origin = hand - pose.basis.z * staff_poses.grip
	staff.transform = pose
	(staff.get_node("RightGrip/Wrist") as Marker3D).position.z = staff_poses.grip
	(avatar.get_node("RightElbowHint") as Marker3D).position = Vector3(-0.48, 0.87, -0.05)
	for modifier_name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
		(skeleton.get_node(modifier_name) as SkeletonModifier3D).influence = 1.0 if modifier_name.begins_with("Right") else 0.0
	if not is_instance_valid(_crate_preview):
		_crate_preview = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		_crate_preview.mesh = mesh
		avatar.add_child(_crate_preview)
	var ground := Vector3(0.0, 0.50, 0.82)
	var raised := Vector3(0.0, 2.02, 0.24)
	match name:
		&"crate_lift", &"crate_place":
			var up := travel if name == &"crate_lift" else 1.0 - travel
			_crate_preview.position = ground.lerp(raised, up) + Vector3.BACK * (0.4 * sin(PI * up))
		&"crate_throw":
			_crate_preview.position = raised + Vector3(0.0, 0.10, 0.30) * travel
		&"crate_push":
			_crate_preview.position = ground + Vector3.BACK * travel * 0.45
	_crate_preview.show()

func save_clips() -> bool:
	var motion := get_node_or_null(player_path) as AnimationPlayer
	var library := motion.get_animation_library("") if motion != null else null
	if library == null or library.resource_path != LIBRARY_PATH:
		push_warning("Ожидалась отдельная библиотека Миры.")
		return false
	if ResourceSaver.save(library, LIBRARY_PATH) != OK:
		push_warning("Не удалось сохранить библиотеку Миры.")
		return false
	print("Клипы Миры сохранены: ", LIBRARY_PATH)
	return true

func save_staff_poses() -> bool:
	if staff_poses == null or not staff_poses.is_valid():
		push_warning("Проверь координаты, хват и направления поз посоха.")
		return false
	if _staff_poses_hash != FileAccess.get_sha256(StaffPoses.PATH):
		push_warning("Позы изменились на диске. Сначала перечитай сохранённые позы.")
		return false
	if ResourceSaver.save(staff_poses, StaffPoses.PATH) != OK:
		push_warning("Не удалось сохранить позы посоха.")
		return false
	_staff_poses_hash = FileAccess.get_sha256(StaffPoses.PATH)
	print("Позы посоха Миры сохранены.")
	return true

func reload_staff_poses() -> bool:
	var saved := ResourceLoader.load(StaffPoses.PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as StaffPoses
	if saved == null or not saved.is_valid():
		return false
	staff_poses = saved.duplicate() as StaffPoses
	_staff_poses_hash = FileAccess.get_sha256(StaffPoses.PATH)
	return true

func save_socket() -> bool:
	var socket := get_node_or_null(socket_path) as Marker3D
	if socket == null or _socket_hash != FileAccess.get_sha256(SOCKET_PATH):
		push_warning("Крепление изменилось на диске. Сначала перечитай сохранённое крепление.")
		return false
	var authored := _read_socket()
	if authored == null: return false
	authored.transform = socket.transform.translated_local(-STAFF_PIVOT)
	var scene := PackedScene.new()
	var error := scene.pack(authored)
	authored.free()
	if error != OK or ResourceSaver.save(scene, SOCKET_PATH) != OK:
		push_warning("Не удалось сохранить крепление Миры.")
		return false
	_socket_hash = FileAccess.get_sha256(SOCKET_PATH)
	print("Крепление Миры сохранено: ", SOCKET_PATH)
	return true

func reload_socket() -> bool:
	var socket := get_node_or_null(socket_path) as Marker3D
	var authored := _read_socket()
	if socket == null or authored == null:
		if authored != null: authored.free()
		return false
	socket.transform = authored.transform.translated_local(STAFF_PIVOT)
	authored.free()
	_socket_hash = FileAccess.get_sha256(SOCKET_PATH)
	return true

func _read_socket() -> Marker3D:
	var scene := ResourceLoader.load(SOCKET_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return scene.instantiate() as Marker3D if scene != null else null
