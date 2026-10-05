extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const PANEL = preload("res://addons/ember_import/ember_world_look_panel.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "MaterialLightFixture"
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.hydrate_legacy_regions = false
	var terrain := Terrain.new()
	terrain.width = 64
	terrain.depth = 64
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color("808080")])
	terrain.palette_surface_roles = PackedStringArray(["", "stone"])
	terrain.palette_material_ids = PackedStringArray(["", "stone_relief"])
	for field in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var channel: Variant = PackedInt32Array() if field in ["heights", "water_levels"] else PackedByteArray()
		channel.resize(64 * 64)
		channel.fill(8 if field == "heights" else 1 if field in ["top_materials", "base_materials", "cap_depths"] else 0)
		terrain.set(field, channel)
	assert(terrain.validation_errors().is_empty())
	map.compact_terrain = terrain
	scene.add_child(map)
	map.owner = scene
	var look := Node3D.new()
	look.name = "Look"
	map.add_child(look)
	look.owner = scene
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	look.add_child(world)
	world.owner = scene
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	look.add_child(sun)
	sun.owner = scene
	var projection = map.get("_visual_surface_projection")
	for frame in 90:
		await process_frame
		if projection.pending_tile_count() == 0: break
	assert(projection.pending_tile_count() == 0)
	var material: ShaderMaterial = projection.get("_ground_material")
	assert(material.get_shader_parameter("material_light_mode") == 0)
	var tile = projection.get("_tiles").values()[0]
	var original_geometry := terrain.working_copy()
	var panel := PANEL.new()
	root.add_child(panel)
	var history := UndoRedo.new()
	panel.set_target(scene, map, history)
	assert(panel._tabs.get_tab_title(2) == "Материалы")
	panel._choices.compact_material_light_mode.item_selected.emit(1)
	assert(material.get_shader_parameter("material_light_mode") == 1)
	history.undo()
	assert(material.get_shader_parameter("material_light_mode") == 0)
	history.redo()
	assert(material.get_shader_parameter("material_light_mode") == 1)
	panel._gray_switch.button_pressed = true
	assert(material.get_shader_parameter("material_gray_preview"))
	history.undo()
	assert(not material.get_shader_parameter("material_gray_preview"))
	history.redo()
	panel._contact_switch.button_pressed = true
	map.apply_authored_lighting()
	assert(world.environment.ssao_enabled, "map must preserve authored contact shading")
	history.undo()
	assert(not world.environment.ssao_enabled)
	history.redo()
	panel._choices.compact_material_light_mode.item_selected.emit(2)
	assert(material.get_shader_parameter("material_light_mode") == 2)
	assert(projection.get("_tiles").values()[0] == tile and projection.pending_tile_count() == 0,
		"changing light must not rebuild geometry/collision or water")
	assert(terrain.same_terrain_data(original_geometry))
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	var path := "user://ember-tests/material-light-fixture.tscn"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(ResourceSaver.save(packed, path) == OK)
	map.compact_material_light_mode = 0
	map.compact_material_gray_preview = false
	world.environment.ssao_enabled = false
	var saved := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := saved.instantiate()
	var reopened_map := reopened.get_node("Map") as EmberMapLoader
	root.add_child(reopened)
	assert(reopened_map.compact_material_light_mode == 2 and reopened_map.compact_material_gray_preview)
	var reopened_material: ShaderMaterial = reopened_map.get("_visual_surface_projection").get("_ground_material")
	assert(reopened_material.get_shader_parameter("material_light_mode") == 2)
	assert(reopened_material.get_shader_parameter("material_gray_preview"))
	assert(reopened_map.get_node("Look/WorldEnvironment").environment.ssao_enabled)
	panel.set_target(reopened, reopened_map, history)
	assert(panel._choices.compact_material_light_mode.selected == 2 and panel._gray_switch.button_pressed)
	print("PASS MATERIAL_LIGHT panel Undo/Redo, no remesh, scene Save/Reopen/Discard, runtime uniforms, authored SSAO")
	panel.set_target(null, null, null)
	history.clear_history()
	history.free()
	panel.free()
	scene.free()
	reopened.free()
	await process_frame
	quit()
