extends SceneTree
const Form = preload("res://addons/ember_import/ember_story_authoring_dialog.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Builder = preload("res://addons/ember_import/ember_story_authoring.gd")
const Store = preload("res://addons/ember_import/ember_action_script_store.gd")
const ChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(FileAccess.file_exists("res://.interaction-test-sandbox"))
	var stage: Node3D = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var original_camera := root.get_camera_3d()
	var original_item: Transform3D = stage.get_node("Item").transform
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var form := Form.new()
	root.add_child(form)
	form.setup(stage)
	var before := stage.get_child_count()
	var chain := ChainEditor.new()
	chain.presentation_scene_root = stage
	root.add_child(chain)
	chain.setup("harbor_cargo_story_trial", "")
	var result := {}
	form.create_requested.connect(func(data: Dictionary):
		result.clear()
		result.merge(actions.create_story_scene(stage, data)))
	form.confirmed.emit()
	assert(not result.ok and stage.get_child_count() == before)
	form.canceled.emit()
	assert(stage.get_child_count() == before)
	form.find_child("StoryTitle", true, false).text = "Своя передача посылки"
	for pair in [["primary", "ActorA"], ["secondary", "ActorB"], ["item", "Item"]]:
		var picker := form.find_child("StoryTarget_" + pair[0], true, false) as OptionButton
		_select(picker, pair[1])
	form.find_child("StoryFilter_primary", true, false).text = "ActorA"
	form.find_child("StoryFilter_primary", true, false).text_changed.emit("ActorA")
	assert(form.find_child("StoryTarget_primary", true, false).item_count == 2)
	var secondary := form.find_child("StoryTarget_secondary", true, false) as OptionButton
	assert(str(secondary.get_item_metadata(secondary.selected)) == "ActorB")
	form.find_child("StoryFilter_primary", true, false).text = ""
	form.find_child("StoryFilter_primary", true, false).text_changed.emit("")
	form.find_child("StoryMoveX", true, false).value = 1.1
	for index in 2:
		form.add_dialogue()
		var row: Node = form._talks.get_child(index)
		row.get_node("Time").value = 1.0 + index
		_select(row.get_node("Dialogue"), "camera_story_exchange")
	# World-space displacement must survive rotated/scaled object folders.
	var folder := Node3D.new()
	folder.name = "RotatedFolder"
	folder.rotation.y = 0.5
	folder.scale = Vector3.ONE * 2.0
	stage.add_child(folder)
	var prop := MeshInstance3D.new()
	prop.name = "NestedItem"
	prop.mesh = BoxMesh.new()
	folder.add_child(prop)
	var nested_values := form.values()
	nested_values.item = "RotatedFolder/NestedItem"
	var nested := Builder.build(stage, nested_values)
	assert(nested.ok)
	var endpoint: Vector3 = nested.node.get_node("AnimationPlayer").get_animation("story").position_track_interpolate(0, 4.0)
	assert(folder.to_global(endpoint).is_equal_approx(prop.global_position + Vector3(1.1, 0, 0)))
	nested.node.free()
	folder.free()
	var body := RigidBody3D.new()
	body.name = "PhysicalItem"
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = BoxMesh.new()
	body.add_child(visual)
	stage.add_child(body)
	nested_values.item = "PhysicalItem/Visual"
	assert(not Builder.build(stage, nested_values).ok, "Do not animate a visual child away from its physics owner")
	body.free()
	form.confirmed.emit()
	assert(result.ok and stage.get_child_count() == before + 1)
	var assembly: Node = result.node
	var name := str(assembly.name)
	var id: String = result.presenter.presentation_id
	var scene_picker := chain.find_child("StepField_presentationId", true, false) as OptionButton
	scene_picker.get_popup().about_to_popup.emit()
	assert(str(scene_picker.get_item_metadata(scene_picker.selected)) == "cargo_delivery")
	_select(scene_picker, id)
	assert(chain._document().steps[0].presentationId == id)
	chain.queue_free()
	assert(stage.get_node("Item").transform.is_equal_approx(original_item))
	assert(root.get_camera_3d() == original_camera, "Creating a scene stole the active camera")
	assert(assembly.get_node("DialogueLayer/InteractionUi/Panel").owner == null)
	assert(assembly.get_node("Presentation").dialogue_cues.size() == 2)
	history.undo()
	assert(not stage.has_node(name))
	history.redo()
	assert(stage.has_node(name))
	var packed := PackedScene.new()
	assert(packed.pack(stage) == OK)
	assert(ResourceSaver.save(packed, "user://story-authoring-full.tscn") == OK)
	var saved_hash := FileAccess.get_sha256("user://story-authoring-full.tscn")
	var saved_action := Store.document("harbor_cargo_story_trial")
	var action := saved_action.duplicate(true)
	action.steps[0].presentationId = id
	assert(Store.write_document(action) == OK)
	# Unsaved creation/discard does not change the saved scene or write any Action.
	var second := actions.create_story_scene(stage, form.values())
	assert(second.ok and str(second.node.name) != name)
	var second_name := str(second.node.name)
	assert(FileAccess.get_sha256("user://story-authoring-full.tscn") == saved_hash)
	history.clear_history()
	history.free()
	form.queue_free()
	stage.queue_free()
	await process_frame
	stage = ResourceLoader.load("user://story-authoring-full.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	assert(stage.has_node(name) and not stage.has_node(second_name))
	assembly = stage.get_node(name)
	var preview = assembly.get_node("Presentation")
	var inner: EmberInteractionUi = assembly.get_node("DialogueLayer/InteractionUi")
	var follow := EmberFollowCamera.new()
	follow.target = stage.get_node("ActorA")
	follow.follow_distance = 6.0
	follow.look_height = 1.2
	follow.cam_near = 0.03
	stage.add_child(follow)
	var camera := root.get_camera_3d()
	assert(preview.dialogue_cues.size() == 2)
	assert(stage.start_quest_trial().is_empty())
	assert(root.get_camera_3d() == assembly.get_node("ShotRig/Camera3D"))
	assert(not follow.is_processing_unhandled_input())
	var shot_rig = assembly.get_node("ShotRig")
	shot_rig.shot = 2
	shot_rig.snap()
	assert(shot_rig.camera.is_position_in_frustum(stage.get_node("ActorA/Head").global_position + Vector3.UP * 0.18), "Automatic close-up crops the character's head")
	shot_rig.shot = 0
	shot_rig.snap()
	assert(not stage.get_node("StoryPreview").start(), "A second preview stole the running camera")
	for index in 2:
		if index == 0:
			preview.skip()
		assert(inner.is_open() and preview.active)
		inner.advance()
		inner.choose(index)
		inner.advance()
		if index == 0:
			assert(stage._preview_state.inventory.get("coin", 0) == 0, "Reward before the second conversation")
	assert(stage._preview_state.inventory.get("coin", 0) == 3)
	assert(stage.get_node("Item").position.is_equal_approx(Vector3(1.1, 0.88, 0.9)))
	assert(root.get_camera_3d() == camera, "Presentation did not return the prior camera")
	assert(follow.is_processing_unhandled_input())
	await _capture("authored-completed.png")
	stage.reset_quest_trial()
	assert(stage.start_quest_trial().is_empty())
	preview.skip()
	inner.close()
	assert(not preview.active and stage._preview_state.inventory.get("coin", 0) == 0)
	assert(stage.get_node("Item").transform.is_equal_approx(original_item))
	assert(root.get_camera_3d() == camera)
	preview.dialogue_cues[1].time = 99.0
	assert(not stage.start_quest_trial().is_empty())
	assert(not preview.active and root.get_camera_3d() == camera)
	# The ordinary clock also visits BOTH cues; this is not only an End/seek path.
	preview.dialogue_cues[1].time = 2.0
	stage.reset_quest_trial()
	preview.player.speed_scale = 8.0
	assert(stage.start_quest_trial().is_empty())
	for index in 2:
		for frame in 60:
			if inner.is_open():
				break
			await process_frame
		assert(inner.is_open())
		inner.advance()
		inner.choose(index)
		inner.advance()
	await create_timer(0.7).timeout
	assert(not preview.active and stage._preview_state.inventory.get("coin", 0) == 3)
	assert(root.get_camera_3d() == camera)
	assert(Store.write_document(saved_action) == OK)
	stage.queue_free()
	await process_frame
	print("PASS story authoring: real form, validation/cancel/create/Undo/Redo/save/reopen/discard, authored-only nodes, portable bindings, two dialogue stops, quest/reward/camera rollback")
	quit()


func _select(picker: OptionButton, id: String) -> void:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			picker.select(index)
			return
	assert(false, "Missing picker option: " + id)


func _capture(name: String) -> void:
	var directory := OS.get_environment("EMBER_CAMERA_CAPTURE")
	if not directory.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(name))
