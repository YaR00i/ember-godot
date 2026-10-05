extends SceneTree

const PANEL := preload("res://addons/ember_import/ember_world_look_panel.gd")
const WATER := preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "WorldLookFixture"
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	scene.add_child(map)
	map.owner = scene
	var look := Node3D.new()
	look.name = "Look"
	map.add_child(look)
	look.owner = scene
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world.environment.ambient_light_sky_contribution = 1.0
	look.add_child(world)
	world.owner = scene
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	look.add_child(sun)
	sun.owner = scene
	var panel := PANEL.new()
	root.add_child(panel)
	var history := UndoRedo.new()
	panel.set_target(scene, map, history)
	assert(not panel._sliders["river_arc_opening"].editable, "ordinary maps must not gain an unsupported water owner")
	var water := WATER.new()
	water.name = "WaterSettings"
	scene.add_child(water)
	water.owner = scene
	panel.set_target(scene, map, history)
	assert(panel._tabs.get_tab_title(1) == "Вода")
	for key in WATER.WATER_VALUES:
		assert(panel._target(key) == water)
		if panel._choices.has(key): assert(not panel._choices[key].disabled)
		else: assert(panel._sliders[key].editable)
	panel._choices["obstacle_wave_mode"].item_selected.emit(2)
	assert(water.obstacle_wave_mode == 2)
	history.undo()
	assert(water.obstacle_wave_mode == 0)
	history.redo()
	assert(water.obstacle_wave_mode == 2)
	panel._drag_started("object_foam_width_voxels")
	panel._sliders["object_foam_width_voxels"].value = 1.0
	panel._sliders["object_foam_width_voxels"].value = 0.35
	panel._drag_ended(true, "object_foam_width_voxels")
	assert(is_equal_approx(water.object_foam_width_voxels, 0.35))
	history.undo()
	assert(is_equal_approx(water.object_foam_width_voxels, 0.55), "water drag must undo as one action")
	history.redo()
	panel._commit("river_arc_opening", water.river_arc_opening, 0.25, false)
	var distance_actions := history.get_history_count()
	panel._drag_started("water_detail_begin_m")
	panel._sliders["water_detail_begin_m"].value = 17.0
	panel._sliders["water_detail_begin_m"].value = 25.0
	panel._drag_ended(true, "water_detail_begin_m")
	assert(history.get_history_count() == distance_actions + 1)
	assert(water.water_detail_begin_m == 25.0)
	history.undo()
	assert(water.water_detail_begin_m == 40.0)
	history.redo()
	panel._commit("reaction_birth_seconds", water.reaction_birth_seconds, 0.50, false)
	panel._commit("river_foam_variation", water.river_foam_variation, 0.65, false)
	# A runtime snapshot is a single scene transaction, not one Undo per knob.
	scene.scene_file_path = "user://ember-tests/world-look-fixture.tscn"
	var runtime_values: Dictionary = water.water_settings_snapshot()
	runtime_values.obstacle_wave_mode = 1
	runtime_values.obstacle_wave_strength = 0.75
	runtime_values.wave_height_voxels = 2.4
	runtime_values.foam_trail_strength = 0.42
	runtime_values.water_glint_strength = 0.55
	runtime_values.water_detail_begin_m = 28.0
	runtime_values.water_detail_end_m = 88.0
	runtime_values.foam_trail_lifetime = 1.7
	runtime_values.foam_width_pulse = 0.67
	runtime_values.water_level_offset_voxels = -0.45
	runtime_values.sea_swash_height = 2.5
	runtime_values.sea_swash_period = 8.5
	runtime_values.sea_swash_reach = 9.5
	runtime_values.sea_approach_distance = 17.5
	runtime_values.sea_approach_strength = 0.55
	runtime_values.sea_foam_strength = 0.65
	runtime_values.sea_foam_trail_strength = 0.47
	runtime_values.sea_foam_trail_lifetime = 3.1
	runtime_values.sand_wet_strength = 0.65
	runtime_values.sand_drying_seconds = 10.0
	runtime_values.waterfall_strength = 0.85
	runtime_values.waterfall_speed = 0.75
	runtime_values.waterfall_irregularity = 0.9
	runtime_values.waterfall_foam_strength = 0.6
	var original_values: Dictionary = water.water_settings_snapshot()
	var original_sun := EmberLights.sun_look_snapshot(sun)
	var runtime_sun := original_sun.duplicate()
	runtime_sun.sun_azimuth = 72.0
	runtime_sun.sun_elevation = 38.0
	runtime_sun.shadow_softness = 0.6
	var bad_sun := runtime_sun.duplicate()
	bad_sun.sun_azimuth = NAN
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), runtime_values, bad_sun).ok)
	assert(EmberLights.sun_look_snapshot(sun) == original_sun)
	assert(water.water_settings_snapshot() == original_values)
	assert(panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), runtime_values, runtime_sun).ok)
	for key in runtime_sun: assert(is_equal_approx(EmberLights.sun_look_snapshot(sun)[key], runtime_sun[key]))
	history.undo()
	assert(EmberLights.sun_look_snapshot(sun) == original_sun)
	assert(water.water_settings_snapshot() == original_values)
	history.redo()
	for key in runtime_sun: assert(is_equal_approx(EmberLights.sun_look_snapshot(sun)[key], runtime_sun[key]))
	history.undo()
	assert(not panel.apply_runtime_water("res://another-scene.tscn", NodePath("WaterSettings"), runtime_values).ok)
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("Map"), runtime_values).ok)
	var invalid := runtime_values.duplicate()
	invalid.shore_foam_strength = NAN
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid).ok)
	invalid.shore_foam_strength = 5.0
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid).ok)
	invalid = runtime_values.duplicate()
	invalid["position"] = Vector3.ONE
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid).ok)
	assert(water.water_settings_snapshot() == original_values, "rejected snapshots must not partially change scene values")
	var invalid_mode: Dictionary = runtime_values.duplicate()
	invalid_mode.obstacle_wave_mode = 1.5
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid_mode).ok)
	var invalid_distance: Dictionary = runtime_values.duplicate()
	invalid_distance.water_detail_end_m = INF
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid_distance).ok)
	invalid_distance.water_detail_end_m = 0.0
	assert(not panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), invalid_distance).ok)
	assert(panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), runtime_values).ok)
	assert(is_equal_approx(panel._sliders["foam_trail_strength"].value, 0.42))
	history.undo()
	assert(water.water_settings_snapshot() == original_values, "all F6 values must undo together")
	history.redo()
	assert(water.water_settings_snapshot() == runtime_values)
	var action_count := history.get_history_count()
	panel._drag_started("sun_azimuth")
	panel._slider_changed(45.0, "sun_azimuth")
	panel._slider_changed(96.0, "sun_azimuth")
	panel._sliders.sun_azimuth.set_value_no_signal(96.0)
	panel._drag_ended(true, "sun_azimuth")
	assert(history.get_history_count() == action_count + 1)
	assert(is_equal_approx(sun.rotation_degrees.y, 96.0))
	history.undo()
	assert(is_equal_approx(sun.rotation_degrees.y, 0.0))
	history.redo()
	panel._commit("sun_elevation", 0.0, 42.0, false)
	assert(is_equal_approx(sun.rotation_degrees.x, -42.0))
	action_count = history.get_history_count()
	assert(panel.apply_runtime_water(scene.scene_file_path, NodePath("WaterSettings"), runtime_values).ok)
	assert(history.get_history_count() == action_count, "unchanged snapshot must not add an Undo action")
	panel._commit("contrast", 1.0, 1.2, false)
	if not world.environment.adjustment_enabled or not is_equal_approx(world.environment.adjustment_contrast, 1.2):
		_fail("contrast preview/commit")
		return
	history.undo()
	if world.environment.adjustment_enabled or not is_equal_approx(world.environment.adjustment_contrast, 1.0):
		_fail("contrast undo")
		return
	history.redo()
	var original_shadow_energy := world.environment.ambient_light_energy
	panel._commit("ambient_energy", original_shadow_energy, 0.35, true)
	if not is_equal_approx(world.environment.ambient_light_energy, 0.35) or not is_equal_approx(world.environment.ambient_light_sky_contribution, 0.25):
		_fail("shadow fill must reduce sky-only ambient so its strength is visible")
		return
	history.undo()
	if not is_equal_approx(world.environment.ambient_light_energy, original_shadow_energy) or not is_equal_approx(world.environment.ambient_light_sky_contribution, 1.0):
		_fail("shadow fill undo must restore original sky share")
		return
	var original_shadow_tone := world.environment.ambient_light_color
	var edited_shadow_tone := Color(0.12, 0.38, 0.72)
	panel._commit("ambient_color", original_shadow_tone, edited_shadow_tone, true)
	if world.environment.ambient_light_color != edited_shadow_tone or not is_equal_approx(world.environment.ambient_light_sky_contribution, 0.25):
		_fail("shadow tone must reduce sky-only ambient so the chosen color is visible")
		return
	history.undo()
	if world.environment.ambient_light_color != original_shadow_tone or not is_equal_approx(world.environment.ambient_light_sky_contribution, 1.0):
		_fail("shadow tone undo must restore original sky share")
		return
	history.redo()
	panel._commit("ambient_energy", original_shadow_energy, 0.35, true)
	if not is_equal_approx(world.environment.ambient_light_energy, 0.35):
		_fail("shadow fill strength")
		return
	panel._commit("sun_energy", sun.light_energy, 0.65, true)
	panel._commit("shadows", sun.shadow_enabled, false, true)
	panel._drag_started("exposure")
	(panel._sliders["exposure"] as HSlider).value = 1.2
	(panel._sliders["exposure"] as HSlider).value = 1.4
	panel._drag_ended(true, "exposure")
	history.undo()
	if not is_equal_approx(world.environment.tonemap_exposure, 1.0):
		_fail("slider drag must be one undo step")
		return
	history.redo()
	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		_fail("pack")
		return
	var path := "user://ember-tests/world-look-panel.tscn"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(packed, path) != OK:
		_fail("save")
		return
	var opened := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if opened == null:
		_fail("reopen")
		return
	var reopened := opened.instantiate()
	var reopened_sun := reopened.get_node("Map/Look/Sun") as DirectionalLight3D
	assert(is_equal_approx(reopened_sun.rotation_degrees.y, 96.0))
	assert(is_equal_approx(reopened_sun.rotation_degrees.x, -42.0))
	var reopened_env := (reopened.get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
	var reopened_water := reopened.get_node("WaterSettings")
	assert(is_equal_approx(reopened_water.object_foam_width_voxels, 0.35))
	assert(is_equal_approx(reopened_water.river_arc_opening, 0.25))
	assert(is_equal_approx(reopened_water.reaction_birth_seconds, 0.50))
	assert(is_equal_approx(reopened_water.river_foam_variation, 0.65))
	assert(is_equal_approx(reopened_water.foam_trail_strength, 0.42))
	assert(is_equal_approx(reopened_water.water_glint_strength, 0.55))
	assert(is_equal_approx(reopened_water.water_detail_begin_m, 28.0))
	assert(is_equal_approx(reopened_water.water_detail_end_m, 88.0))
	assert(is_equal_approx(reopened_water.foam_trail_lifetime, 1.7))
	assert(is_equal_approx(reopened_water.foam_width_pulse, 0.67))
	assert(is_equal_approx(reopened_water.water_level_offset_voxels, -0.45))
	assert(is_equal_approx(reopened_water.sea_swash_height, 2.5))
	assert(is_equal_approx(reopened_water.sea_swash_period, 8.5))
	assert(is_equal_approx(reopened_water.sea_swash_reach, 9.5))
	assert(is_equal_approx(reopened_water.sea_approach_distance, 17.5))
	assert(is_equal_approx(reopened_water.sea_approach_strength, 0.55))
	assert(is_equal_approx(reopened_water.sea_foam_strength, 0.65))
	assert(is_equal_approx(reopened_water.sea_foam_trail_strength, 0.47))
	assert(is_equal_approx(reopened_water.sea_foam_trail_lifetime, 3.1))
	assert(is_equal_approx(reopened_water.sand_wet_strength, 0.65))
	assert(is_equal_approx(reopened_water.sand_drying_seconds, 10.0))
	assert(reopened_water.obstacle_wave_mode == 1)
	assert(is_equal_approx(reopened_water.obstacle_wave_strength, 0.75))
	assert(reopened_water.get_child_count() == 0, "derived water cameras must not be saved")
	# Discard an unsaved edit by opening the saved scene, then route the panel
	# to the new owner. Subsequent edits must not touch the old scene.
	water.object_foam_width_voxels = 2.0
	water.sea_approach_distance = 6.0
	water.water_detail_begin_m = 5.0
	water.water_detail_end_m = 10.0
	panel.set_target(reopened, reopened.get_node("Map"), history)
	assert(panel._target("object_foam_width_voxels") == reopened_water)
	assert(is_equal_approx(panel._sliders["object_foam_width_voxels"].value, 0.35))
	assert(is_equal_approx(panel._sliders["sea_approach_distance"].value, 17.5))
	assert(is_equal_approx(panel._sliders["water_detail_begin_m"].value, 28.0))
	assert(is_equal_approx(panel._sliders["water_detail_end_m"].value, 88.0))
	if not is_equal_approx(reopened_sun.light_energy, 0.65) or reopened_sun.shadow_enabled or not is_equal_approx(reopened_env.adjustment_contrast, 1.2) or not reopened_env.adjustment_enabled or not is_equal_approx(reopened_env.tonemap_exposure, 1.4) or reopened_env.ambient_light_color != edited_shadow_tone or not is_equal_approx(reopened_env.ambient_light_sky_contribution, 0.25) or not is_equal_approx(reopened_env.ambient_light_energy, 0.35):
		_fail("saved look differs")
		return
	print("WORLD_LOOK_PANEL light_water_tabs=ok water_drag_undo=ok scene_save_reopen_discard=ok")
	reopened.free()
	panel.refresh()
	assert(not panel._sliders["river_arc_opening"].editable, "closing the scene must disable stale settings")
	panel.set_target(null, null, null)
	history.clear_history()
	history.free()
	panel.free()
	scene.free()
	reopened_env = null
	opened = null
	packed = null
	quit()


func _fail(reason: String) -> void:
	printerr("WORLD_LOOK_PANEL FAIL: ", reason)
	quit(1)
