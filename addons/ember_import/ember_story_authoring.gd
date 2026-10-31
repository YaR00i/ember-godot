@tool
extends RefCounted
## Builds a scene-owned native AnimationPlayer assembly. No document writes here.
const Presenter = preload("res://scripts/prototypes/ember_story_preview.gd")
const Rig = preload("res://scripts/prototypes/ember_camera_preset_rig.gd")
const Cue = preload("res://scripts/ember_story_dialogue_cue.gd")
const Binding = preload("res://scripts/ember_story_binding.gd")


static func candidates(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if root == null:
		return result
	for node in root.find_children("*", "Node3D", true, false):
		var parent := node.get_parent()
		var internal := false
		var ancestor: Node = node
		while ancestor != null and ancestor != root:
			if ancestor.has_meta("ember_story_scene"):
				internal = true
			ancestor = ancestor.get_parent()
		if internal or node is Camera3D or node is Light3D or node is Label3D:
			continue
		if node is MeshInstance3D:
			if parent != root and _direct_geometry(parent):
				continue
			result.append(node)
		elif _direct_geometry(node):
			result.append(node)
	return result


static func _direct_geometry(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D:
			return true
	return false


static func bounds(node: Node3D) -> Dictionary:
	var found := false
	var box := AABB()
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var next: AABB = mesh.global_transform * mesh.get_aabb()
		box = box.merge(next) if found else next
		found = true
	return {"center": box.get_center() if found else node.global_position + Vector3.UP * 1.38,
		"height": maxf(box.size.y, 0.1) if found else 1.8,
		"span": maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.1)) if found else 0.35}


static func build(root: Node3D, input: Dictionary) -> Dictionary:
	if root == null or not root.is_inside_tree():
		return {"ok": false, "error": "Открой3D-сцену с участниками и предметом"}
	var title := str(input.get("title", "")).strip_edges()
	if title.is_empty():
		return {"ok": false, "error": "Укажи название сценки"}
	var targets: Array[Node3D] = []
	for field in ["primary", "secondary", "item"]:
		var path := NodePath(str(input.get(field, "")))
		var node := root.get_node_or_null(path) as Node3D if not path.is_empty() else null
		if node == null or node == root or not root.is_ancestor_of(node):
			return {"ok": false, "error": "Выбери обоих участников и предмет на этой карте"}
		targets.append(node)
	if targets[0] == targets[1] or targets[2] in [targets[0], targets[1]]:
		return {"ok": false, "error": "Участники и перемещаемый предмет должны быть разными"}
	var item := targets[2]
	var physical_ancestor := false
	var ancestor: Node = item
	while ancestor != null and ancestor != root:
		if ancestor is CharacterBody3D or ancestor is RigidBody3D:
			physical_ancestor = true
		ancestor = ancestor.get_parent()
	if physical_ancestor or not item.find_children("*", "RigidBody3D", true, false).is_empty() or not item.find_children("*", "CharacterBody3D", true, false).is_empty():
		return {"ok": false, "error": "Для первой постановки выбери визуальный Node3D/меш без динамического физического тела"}
	var duration := float(input.get("duration", 4.0))
	var movement: Vector3 = input.get("movement", Vector3(0.8, 0, 0))
	if not is_finite(duration) or duration < 0.5 or duration > 120.0 or not movement.is_finite():
		return {"ok": false, "error": "Проверь длительность и смещение предмета"}
	var cues: Array[Cue] = []
	var times: Array[float] = []
	for entry in input.get("dialogues", []):
		var time := float(entry.get("time", -1.0))
		var id := str(entry.get("dialogueId", ""))
		if not is_finite(time) or time < 0.0 or time >= duration or time in times or EmberDialogueCatalog.document(id).is_empty():
			return {"ok": false, "error": "Выбери диалог и разные моменты его начала внутри сценки"}
		var cue := Cue.new()
		cue.time = time
		cue.dialogue = load(EmberDialogueCatalog.native_path(id)) as EmberDialogueResource
		cues.append(cue)
		times.append(time)
	var index := 1
	var ids: Array = Binding.entries(root).map(func(entry): return entry.id)
	while root.has_node("StoryScene%d" % index) or "story_%d" % index in ids:
		index += 1
	var assembly := Node3D.new()
	assembly.name = "StoryScene%d" % index
	assembly.set_meta("ember_story_scene", true)
	assembly.editor_description = title + " · анимация: AnimationPlayer; разговоры: Presentation"
	var rig := Node3D.new()
	rig.name = "ShotRig"
	rig.editor_description = "Привязки участников и предмета, крупность и плавность камеры"
	rig.set_script(Rig)
	assembly.add_child(rig)
	var measured: Array[Dictionary] = []
	for node in targets:
		measured.append(bounds(node))
	rig.primary_anchor = NodePath("../../" + str(root.get_path_to(targets[0])))
	rig.secondary_anchor = NodePath("../../" + str(root.get_path_to(targets[1])))
	rig.detail_anchor = NodePath("../../" + str(root.get_path_to(item)))
	# The character focus belongs near the upper torso; object detail uses its center.
	rig.primary_offset = targets[0].to_local(measured[0].center + Vector3.UP * measured[0].height * 0.25)
	rig.secondary_offset = targets[1].to_local(measured[1].center + Vector3.UP * measured[1].height * 0.25)
	rig.detail_offset = item.to_local(measured[2].center)
	rig.subject_scale = (measured[0].height + measured[1].height) / 3.6
	rig.detail_scale = measured[2].span / 0.35
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.03
	camera.far = 5000.0
	rig.add_child(camera) # current=false until this presentation actually runs.
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.editor_description = "Шкала story: движение предмета и переключение ракурсов"
	player.root_node = NodePath("../..")
	assembly.add_child(player)
	var clip := Animation.new()
	clip.length = duration
	var track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track, root.get_path_to(item))
	clip.position_track_insert_key(track, 0.0, item.position)
	var spatial_parent := item.get_parent_node_3d()
	var destination := spatial_parent.to_local(item.global_position + movement) if spatial_parent != null else item.global_position + movement
	clip.position_track_insert_key(track, duration, destination)
	var reset := Animation.new()
	reset.length = 0.001
	var reset_track := reset.add_track(Animation.TYPE_POSITION_3D)
	reset.track_set_path(reset_track, root.get_path_to(item))
	reset.position_track_insert_key(reset_track, 0.0, item.position)
	var shot_path := NodePath(str(assembly.name) + "/ShotRig:shot")
	track = clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, shot_path)
	clip.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	clip.track_insert_key(track, 0.0, int(input.get("shot", 0)))
	clip.track_insert_key(track, duration * 0.5, 5)
	reset_track = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_track, shot_path)
	reset.track_insert_key(reset_track, 0.0, 0)
	var library := AnimationLibrary.new()
	library.add_animation("story", clip)
	library.add_animation("RESET", reset)
	player.add_animation_library("", library)
	player.assigned_animation = &"story"
	var text_layer := CanvasLayer.new()
	text_layer.name = "StoryText"
	assembly.add_child(text_layer)
	var caption := Label.new()
	caption.name = "Caption"
	text_layer.add_child(caption)
	var layer := CanvasLayer.new()
	layer.name = "DialogueLayer"
	layer.layer = 30
	assembly.add_child(layer)
	var ui := EmberInteractionUi.new()
	ui.name = "InteractionUi"
	layer.add_child(ui)
	var presenter := Node.new()
	presenter.name = "Presentation"
	presenter.editor_description = "Название сценки и разговорные остановки: Разговоры по времени"
	presenter.set_script(Presenter)
	presenter.clip_name = &"story"
	presenter.presentation_id = "story_%d" % index
	presenter.presentation_name = title
	presenter.dialogue_cues = cues
	assembly.add_child(presenter)
	return {"ok": true, "node": assembly, "presenter": presenter}
