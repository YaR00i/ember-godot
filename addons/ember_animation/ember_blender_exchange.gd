@tool
extends RefCounted

const WORK_DIR := "user://mira-blender"
const HELPER := "res://addons/ember_animation/blender_exchange.py"
const EDITOR_SETTING := "ember/animation/blender_executable"
const BONE_TRACKS := [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]


static func bone_track(animation: Animation, track: int, skeleton: Skeleton3D, root: Node) -> bool:
	var path := animation.track_get_path(track)
	return (
		animation.track_get_type(track) in BONE_TRACKS and path.get_subname_count() == 1
		and root.get_node_or_null(NodePath(path.get_concatenated_names())) == skeleton
		and skeleton.find_bone(path.get_subname(0)) >= 0
	)


static func export_clip(workshop: Node, source: Animation, clip_id: StringName, path: String) -> Error:
	var motion := workshop.get_node(workshop.get("player_path")) as AnimationPlayer
	var skeleton := workshop.get_node(workshop.get("skeleton_path")) as Skeleton3D
	var avatar := motion.get_node(motion.root_node)
	var copy := avatar.duplicate(0)
	for child in copy.get_children():
		if child is AnimationPlayer or child.name == "MiraStaff":
			copy.remove_child(child)
			child.free()
	var clip := source.duplicate() as Animation
	for track in range(clip.get_track_count() - 1, -1, -1):
		if not bone_track(clip, track, skeleton, avatar):
			clip.remove_track(track)
	if clip.get_track_count() == 0:
		copy.free()
		return ERR_INVALID_DATA
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = ^".."
	copy.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(clip_id, clip)
	player.add_animation_library(&"", library)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(copy, state)
	if error == OK:
		error = document.write_to_filesystem(state, path)
	copy.free()
	return error


static func import_clip(workshop: Node, original: Animation, clip_id: StringName, path: String) -> Animation:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	var imported := document.generate_scene(state, 60.0)
	if imported == null:
		return null
	var result := _merge_bones(workshop, imported, original, clip_id)
	imported.free()
	return result


static func import_new_clip(workshop: Node, path: String) -> Animation:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	var imported := document.generate_scene(state, 60.0)
	if imported == null:
		return null
	var players := imported.find_children("*", "AnimationPlayer", true, false)
	var result: Animation
	if players.size() == 1:
		var player := players[0] as AnimationPlayer
		var names := player.get_animation_list()
		if names.size() == 1:
			var original := Animation.new()
			original.length = player.get_animation(names[0]).length
			result = _merge_bones(workshop, imported, original, names[0])
	imported.free()
	return result


static func _merge_bones(workshop: Node, imported: Node, original: Animation, clip_id: StringName) -> Animation:
	var players := imported.find_children("*", "AnimationPlayer", true, false)
	var skeletons := imported.find_children("*", "Skeleton3D", true, false)
	if players.size() != 1 or skeletons.size() != 1:
		return null
	var player := players[0] as AnimationPlayer
	var source_skeleton := skeletons[0] as Skeleton3D
	var source_root := player.get_node(player.root_node)
	var names := player.get_animation_list()
	if not player.has_animation(clip_id) and names.size() != 1:
		return null
	var clip := player.get_animation(clip_id if player.has_animation(clip_id) else StringName(names[0]))
	if clip.length <= 0.001:
		return null
	var target := workshop.get_node(workshop.get("skeleton_path")) as Skeleton3D
	var motion := workshop.get_node(workshop.get("player_path")) as AnimationPlayer
	var target_path := motion.get_node(motion.root_node).get_path_to(target)
	var result := original.duplicate() as Animation
	var transferred := 0
	for track in clip.get_track_count():
		if not bone_track(clip, track, source_skeleton, source_root):
			continue
		var bone := clip.track_get_path(track).get_subname(0)
		var from := source_skeleton.find_bone(bone)
		var to := target.find_bone(bone)
		if to < 0 or not _compatible_bone(source_skeleton, from, target, to):
			return null
		var path := NodePath("%s:%s" % [target_path, bone])
		var type := clip.track_get_type(track)
		var old := result.find_track(path, type)
		if old >= 0:
			result.remove_track(old)
		var dst := result.add_track(type)
		result.track_set_path(dst, path)
		result.track_set_interpolation_type(dst, clip.track_get_interpolation_type(track))
		for key in clip.track_get_key_count(track):
			var time := clip.track_get_key_time(track, key) * result.length / clip.length
			result.track_insert_key(dst, time, clip.track_get_key_value(track, key))
		transferred += 1
	return result if transferred > 0 else null


static func _compatible_bone(source: Skeleton3D, from: int, target: Skeleton3D, to: int) -> bool:
	var source_parent := source.get_bone_parent(from)
	var target_parent := target.get_bone_parent(to)
	if (source_parent < 0) != (target_parent < 0):
		return false
	if source_parent >= 0 and source.get_bone_name(source_parent) != target.get_bone_name(target_parent):
		return false
	var a := source.get_bone_rest(from)
	var b := target.get_bone_rest(to)
	return a.origin.distance_to(b.origin) < 0.005 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.015
