extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Look=preload("res://addons/ember_import/ember_world_look_panel.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var legacy=Materials.load_compact_terrain_variant("grass_surface")
	assert(not legacy.grass_light_enabled)
	var pattern=legacy.duplicate(true);pattern.grass_light_enabled=true
	assert(pattern.validation_errors().is_empty())
	for field in ["grass_light_low","grass_light_tint_strength","grass_light_shadow_fill"]:
		var bad=pattern.duplicate(true);bad.set(field,NAN);assert(not bad.validation_errors().is_empty())
	var bad=pattern.duplicate(true);bad.role_id="stone";assert(not bad.validation_errors().is_empty())
	bad=pattern.duplicate(true);bad.grass_light_warm=Color(2.1,1,1);assert(not bad.validation_errors().is_empty())
	var other=pattern.duplicate(true);other.grass_light_low=0.78;other.grass_light_warm=Color(0.9,1,1.1)
	var material=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(material,PackedStringArray(["","grass","grass","grass"]),PackedStringArray(["","first","second","legacy"]),PackedColorArray(),{"first":pattern,"second":other,"legacy":legacy})
	var lookup: Image=material.get_shader_parameter("grass_light_lookup").get_image()
	assert(is_equal_approx(lookup.get_pixel(1,0).r,0.64) and is_equal_approx(lookup.get_pixel(2,0).r,0.78) and lookup.get_pixel(3,0).a==0.0)
	var texture_id: int=material.get_shader_parameter("grass_light_lookup").get_instance_id()
	pattern.grass_light_low=0.7;Materials.update_grass_light_profile(material,1,pattern)
	assert(material.get_shader_parameter("grass_light_lookup").get_instance_id()==texture_id)
	lookup=material.get_meta("ember_grass_light_image") # Dummy renderer has no updated GPU readback; native covers it.
	assert(is_equal_approx(lookup.get_pixel(1,0).r,0.7) and is_equal_approx(lookup.get_pixel(2,0).r,0.78))
	var path:="user://ember-tests/grass-light-workflow.tres";DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(ResourceSaver.save(legacy.duplicate(true),path)==OK)
	var projection=TerrainProjection.new();projection.document=load("res://content/world_terrains/material_depth_study.res").working_copy()
	projection.document.palette_surface_roles=PackedStringArray(["","grass","grass","grass"])
	projection.document.palette_material_ids=PackedStringArray(["","first","second","legacy"])
	projection._ground_material=material
	Materials.update_grass_light_profile(material,1,legacy)
	var panel=Dialog.new();root.add_child(panel);root.add_child(panel.parameters_panel)
	panel.light_profile_previewed.connect(projection.preview_shared_material_light)
	panel.pattern_path_override=path;assert(panel.open_variant("first","grass"))
	var artwork=panel._draft.pixels.duplicate();var image_texture=panel._draft.albedo_texture
	panel._grass_light_switch.button_pressed=true;assert(panel._draft.grass_light_enabled)
	panel._finish_sliders.grass_light_low.value=0.72;assert(is_equal_approx(panel._draft.grass_light_low,0.72))
	assert(is_equal_approx(material.get_meta("ember_grass_light_image").get_pixel(1,0).r,0.72))
	panel.undo_edit();assert(is_equal_approx(panel._draft.grass_light_low,0.64));panel.redo_edit()
	panel._change_grass_light({"grass_light_warm":Color(0.9,1,1.1),"grass_light_cool":Color(1,0.95,1)})
	panel._change_tone(Color(0.3,0.55,0.22),0);assert(panel._draft.grass_light_warm==Color(0.9,1,1.1))
	var manual=panel._draft.grass_light_warm
	var actions: int=panel._history.get_history_count();panel._suggest_grass_light_tones()
	assert(panel._history.get_history_count()==actions+1);assert(panel._draft.grass_light_warm==Color(1.075,1,0.94))
	panel.undo_edit();assert(panel._draft.grass_light_warm==manual);panel.redo_edit()
	assert(panel._draft.pixels==artwork and panel._draft.albedo_texture==image_texture)
	assert(panel._save(true));assert(not panel.is_dirty())
	var saved=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	assert(saved.grass_light_enabled and is_equal_approx(saved.grass_light_low,0.72) and saved.grass_light_warm.is_equal_approx(Color(1.075,1,0.94)))
	var hash_before:=FileAccess.get_sha256(path);panel._finish_sliders.grass_light_shadow_fill.value=0.11
	assert(panel.is_dirty())
	panel.cancel_edit();assert(FileAccess.get_sha256(path)==hash_before);assert(panel.open_variant("first","grass"));assert(is_equal_approx(panel._draft.grass_light_shadow_fill,0.07))
	assert(is_equal_approx(material.get_meta("ember_grass_light_image").get_pixel(1,0).b,0.07))
	assert(is_equal_approx(material.get_meta("ember_grass_light_image").get_pixel(2,0).r,0.78))
	panel.free();projection.free()
	var scene:=Node3D.new();scene.name="MaterialLightScene";root.add_child(scene)
	var map:=EmberMapLoader.new();map.name="Map";scene.add_child(map);map.owner=scene
	var group:=Node3D.new();group.name="Look";map.add_child(group);group.owner=scene
	var sun:=DirectionalLight3D.new();sun.name="Sun";group.add_child(sun);sun.owner=scene;sun.rotation_degrees=Vector3(-27,23,0)
	var world:=WorldEnvironment.new();world.name="WorldEnvironment";world.environment=Environment.new();group.add_child(world);world.owner=scene
	world.environment.tonemap_exposure=1.17;world.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var world_panel=Look.new();root.add_child(world_panel);var history:=UndoRedo.new();world_panel.set_target(scene,map,history)
	for index in 3:
		var before_rotation:=sun.rotation_degrees;var before_energy:=sun.light_energy
		var before_source:=world.environment.ambient_light_source
		var count:=history.get_history_count();world_panel.apply_material_light_preset(index)
		assert(history.get_history_count()==count+1 and is_equal_approx(sun.rotation_degrees.y,23))
		assert(is_equal_approx(world.environment.tonemap_exposure,1.17) and world.environment.tonemap_mode==Environment.TONE_MAPPER_FILMIC)
		assert(sun.light_color==EmberLights.MATERIAL_LIGHT_PRESETS[index].sun_color)
		assert(world.environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR)
		history.undo();assert(sun.rotation_degrees.is_equal_approx(before_rotation) and is_equal_approx(sun.light_energy,before_energy))
		assert(world.environment.ambient_light_source==before_source)
		history.redo();assert(is_equal_approx(sun.light_energy,EmberLights.MATERIAL_LIGHT_PRESETS[index].sun_energy))
	var packed:=PackedScene.new();assert(packed.pack(scene)==OK);assert(ResourceSaver.save(packed,"user://ember-tests/material-light-scene.tscn")==OK)
	var reopened=ResourceLoader.load("user://ember-tests/material-light-scene.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	assert(is_equal_approx(reopened.get_node("Map/Look/Sun").light_energy,0.22))
	assert(reopened.get_node("Map/Look/WorldEnvironment").environment.ambient_light_color.is_equal_approx(Color(0.36,0.46,0.72)))
	reopened.free();world_panel.free();history.free();scene.queue_free()
	print("MATERIAL_LIGHT_WORKFLOW PASS data/legacy/two variants/binding/Undo-Redo/suggestion/paint/Save-Reopen/Discard/scene presets")
	quit()
