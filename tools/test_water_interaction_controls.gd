extends SceneTree
## Existing prop authoring fields and world-water history, on a disposable document.
const PanelScript = preload("res://addons/ember_import/ember_world_look_panel.gd")
const Water = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("INTERACTION_CONTROLS FAIL ", label)
func run() -> void:
	var scene := Node3D.new(); scene.name = "InteractionControlsFixture"; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false
	scene.add_child(map); map.owner = scene
	var look := Node3D.new(); look.name = "Look"; map.add_child(look); look.owner = scene
	var sun := DirectionalLight3D.new(); sun.name = "Sun"; look.add_child(sun); sun.owner = scene
	var environment := WorldEnvironment.new(); environment.name = "WorldEnvironment"; environment.environment = Environment.new()
	look.add_child(environment); environment.owner = scene
	var water := Water.new(); water.name = "PlanarReflection"; water.study_controls = false
	scene.add_child(water); water.owner = scene; water.set_process(false)
	var prop: Node3D = load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate()
	prop.name = "Rock"; map.add_child(prop); prop.owner = scene
	var scroll := ScrollContainer.new(); root.add_child(scroll); scroll.position = Vector2(12, 12); scroll.size = Vector2(550, 760)
	var panel := PanelScript.new(); scroll.add_child(panel); panel.custom_minimum_size.x = 520
	var history := UndoRedo.new(); panel.set_target(scene, map, history)
	check(not prop.has_node("WaterContact"), "disabled prop creates no implicit contact")
	history.create_action("Object water contact")
	history.add_do_property(prop, "water_contact_enabled", true); history.add_undo_property(prop, "water_contact_enabled", false)
	history.commit_action(); check(prop.has_node("WaterContact"), "existing authoring flag creates shared contact immediately")
	history.undo(); check(not prop.has_node("WaterContact"), "Undo removes derived contact")
	history.redo(); check(prop.get_node("WaterContact") is EmberWaterContact3D, "Redo restores same contact type as actors")
	prop.water_contact_radius_blocks = 1.1
	check(is_equal_approx(prop.get_node("WaterContact").radius_blocks, 1.1), "existing radius edits update live component")
	var position_before := prop.position
	history.create_action("Move water object")
	history.add_do_property(prop, "position", Vector3(24, -8, 16)); history.add_undo_property(prop, "position", position_before)
	history.commit_action(); history.undo(); check(prop.position == position_before, "object movement Undo")
	history.redo(); check(prop.position == Vector3(24, -8, 16), "object movement Redo")
	panel._choices.obstacle_wave_mode.select(2); panel._choices.obstacle_wave_mode.item_selected.emit(2)
	check(water.obstacle_wave_mode == 2, "existing world panel enables live interaction")
	check(not panel._sliders.reaction_opening.editable and panel._sliders.reaction_strength.editable, "live interaction exposes its strength without pretending to use analytic arc controls")
	history.undo(); check(water.obstacle_wave_mode == 0, "interaction mode Undo")
	check(panel._sliders.reaction_opening.editable, "legacy controls return when the analytic path is selected")
	history.redo(); check(water.obstacle_wave_mode == 2, "interaction mode Redo")
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack disposable settings document")
	var path := "user://ember-tests/water-interaction-" + str(OS.get_process_id()) + ".tscn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	check(ResourceSaver.save(packed, path) == OK, "save disposable document")
	check(not FileAccess.get_file_as_string(path).contains('[node name="WaterContact"'), "derived contact is not serialized as a second authored component")
	var reopened: Node = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(reopened); var saved: Node3D = reopened.get_node("Map/Rock")
	check(saved.water_contact_enabled and saved.get_node("WaterContact") is EmberWaterContact3D and is_equal_approx(saved.get_node("WaterContact").radius_blocks, 1.1), "fresh reopen restores authoring fields and derives one contact")
	check(saved.position == Vector3(24, -8, 16) and reopened.get_node("PlanarReflection").obstacle_wave_mode == 2, "fresh reopen retains transform and shared interaction mode")
	prop.water_contact_enabled = false; prop.position = Vector3.ZERO
	panel.set_target(reopened, reopened.get_node("Map"), history)
	check(saved.water_contact_enabled and saved.position == Vector3(24, -8, 16) and panel._choices.obstacle_wave_mode.selected == 2, "discard keeps saved object and mode")
	for tabs in panel.find_children("*", "TabContainer", true, false):
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i).contains("Вода"): tabs.current_tab = i
	for button in panel._water_rows.find_children("*", "Button", true, false):
		if button.toggle_mode: button.button_pressed = button.text.begins_with("Волны и препятствия") or button.text.begins_with("След от движения")
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var ui := "user://ember-tests/water-interaction-panel.png"
	root.get_texture().get_image().save_png(ui)
	print("INTERACTION_CONTROLS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size(), " ui=", ProjectSettings.globalize_path(ui))
	scroll.free(); history.free(); reopened.free(); scene.free()
	quit(0 if failures.is_empty() else 1)
