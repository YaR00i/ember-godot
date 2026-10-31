extends SceneTree
## Native panel/serialization gate for the existing water owner's optical controls.
const PanelScript = preload("res://addons/ember_import/ember_world_look_panel.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("WATER_COLOR FAIL ", label)
func run() -> void:
	var authored: Node = load("res://scenes/landscape_compact.tscn").instantiate()
	var scene := Node3D.new(); scene.name = "WaterColorFixture"
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.imported_tile_size = 16.0
	scene.add_child(map); map.owner = scene
	var look := Node3D.new(); look.name = "Look"; map.add_child(look); look.owner = scene
	for name in ["Sun", "WorldEnvironment"]:
		var node: Node = authored.get_node("Map/Look/" + name).duplicate()
		look.add_child(node); node.owner = scene
	var water: Node = authored.get_node("PlanarReflection").duplicate()
	scene.add_child(water); water.owner = scene; water.study_controls = false
	authored.free(); root.add_child(scene); water.set_process(false)
	var material := ShaderMaterial.new(); material.shader = load("res://shaders/ember_compact_sky_reflection_study.gdshader")
	water._material = material; water.refresh_water_settings()
	var baseline: Dictionary = water.water_settings_snapshot()
	check(baseline.shallow_color == Color(0.12, 0.72, 0.78) and baseline.deep_color == Color(0.025, 0.34, 0.66), "preserve authored colors by default")
	check(baseline.water_density == 1.0 and baseline.water_transparency == 1.0 and baseline.water_color_softness == 1.0, "preserve original optics by default")
	var scroll := ScrollContainer.new(); root.add_child(scroll); scroll.position = Vector2(12, 12); scroll.size = Vector2(550, 760)
	var panel := PanelScript.new(); scroll.add_child(panel); panel.custom_minimum_size.x = 520
	var history := UndoRedo.new(); panel.set_target(scene, map, history)
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	var sun_color := sun.light_color
	for key in water.WATER_COLORS:
		history.clear_history()
		check(panel._pickers.has(key) and panel._water_rows.is_ancestor_of(panel._pickers[key]), "water color picker " + key)
		var actions := history.get_history_count()
		panel._color_started(key)
		for color in [Color(0.2, 0.45, 0.6), Color(0.18, 0.52, 0.36)]:
			panel._pickers[key].color = color; panel._color_changed(color, key)
		panel._color_closed(key)
		check(history.get_history_count() == actions + 1 and water.get(key) == Color(0.18, 0.52, 0.36), "one color edit produces one action")
		check(material.get_shader_parameter(key) == water.get(key), "color reaches real shader")
		history.undo(); check(water.water_settings_snapshot() == baseline, "color Undo restores all settings")
		history.redo(); check(water.get(key) == Color(0.18, 0.52, 0.36), "color Redo")
		history.undo()
	check(sun.light_color == sun_color, "water color does not edit sun color")
	for key in ["water_color_start_m", "water_color_end_m", "water_color_softness", "water_density", "water_transparency"]:
		history.clear_history()
		var actions := history.get_history_count()
		panel._drag_started(key)
		var value: float = {"water_color_start_m": 0.4, "water_color_end_m": 1.6, "water_color_softness": 0.3, "water_density": 2.5, "water_transparency": 0.4}[key]
		panel._sliders[key].value = value; panel._drag_ended(true, key)
		check(history.get_history_count() == actions + 1 and is_equal_approx(float(water.get(key)), value), "one numeric drag " + key)
		history.undo(); check(water.water_settings_snapshot() == baseline, "numeric Undo " + key)
		history.redo(); check(is_equal_approx(float(water.get(key)), value), "numeric Redo " + key)
		history.undo()
	panel._sliders.water_color_start_m.value = 30.0
	check(is_equal_approx(water.water_color_start_m, water.water_color_end_m - 0.01), "start cannot pass end")
	history.undo()
	panel._sliders.water_color_end_m.value = 0.01
	check(is_equal_approx(water.water_color_end_m, water.water_color_start_m + 0.01), "end cannot pass start")
	history.undo()
	for bad in [Color(NAN, 0, 0), Color(2, 0, 0), Color(0, 0, 0, 0.5), "red"]:
		var invalid := baseline.duplicate(); invalid.shallow_color = bad; invalid.water_density = 3.0
		check(not panel.apply_runtime_water(scene.scene_file_path, scene.get_path_to(water), invalid).ok and water.water_settings_snapshot() == baseline, "invalid color rejected atomically")
	var invalid := baseline.duplicate(); invalid.water_color_start_m = 3.0; invalid.water_color_end_m = 1.0
	check(not panel.apply_runtime_water(scene.scene_file_path, scene.get_path_to(water), invalid).ok and water.water_settings_snapshot() == baseline, "invalid transition rejected atomically")
	var valid := baseline.duplicate()
	valid.shallow_color = Color(0.2, 0.6, 0.48); valid.deep_color = Color(0.03, 0.18, 0.32)
	valid.water_color_start_m = 0.35; valid.water_color_end_m = 1.8; valid.water_color_softness = 0.7
	valid.water_density = 1.6; valid.water_transparency = 0.8
	check(panel.apply_runtime_water(scene.scene_file_path, scene.get_path_to(water), valid).ok and water.water_settings_snapshot() == valid, "F6 snapshot retains colors and numbers")
	history.undo(); check(water.water_settings_snapshot() == baseline, "F6 bulk Undo")
	history.redo(); check(water.water_settings_snapshot() == valid, "F6 bulk Redo")
	map.imported_tile_size = 32.0; water.refresh_water_settings()
	check(is_equal_approx(material.get_shader_parameter("deep_start_blocks"), 0.7) and is_equal_approx(material.get_shader_parameter("deep_end_blocks"), 3.6), "meter conversion follows actual map scale")
	map.imported_tile_size = 16.0; water.refresh_water_settings()
	var directory := "user://ember-tests/water-color-" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack settings copy")
	check(ResourceSaver.save(packed, directory + "/settings.tscn") == OK, "save settings copy")
	var reopened: Node = ResourceLoader.load(directory + "/settings.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(reopened); var saved: Node = reopened.get_node("PlanarReflection"); saved.set_process(false)
	check(saved.water_settings_snapshot() == valid, "fresh reopen keeps all optical and foam settings")
	panel._pickers.shallow_color.color = Color.RED; panel._color_changed(Color.RED, "shallow_color")
	panel._sliders.water_density.value = 5.0
	panel.set_target(reopened, reopened.get_node("Map"), history)
	check(panel._pickers.shallow_color.color == valid.shallow_color and panel._sliders.water_density.value == valid.water_density and saved.water_settings_snapshot() == valid, "discard restores saved colors and density")
	for tabs in panel.find_children("*", "TabContainer", true, false):
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i).contains("Вода"): tabs.current_tab = i
	for button in panel._water_rows.find_children("*", "Button", true, false):
		if button.toggle_mode: button.button_pressed = button.text.begins_with("Цвет и прозрачность")
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "/controls.png")
	print("WATER_COLOR_CONTROLS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size(), " ui=", ProjectSettings.globalize_path(directory + "/controls.png"))
	scroll.free(); history.free(); reopened.free(); scene.free()
	quit(0 if failures.is_empty() else 1)
