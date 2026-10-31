extends SceneTree
## Regression: map metres must reach ground, props and alternate sphere materials.
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("DEPTH_DISTANCE_FAIL ", label)
func distances(material: ShaderMaterial, near_m: float, far_m: float, unit: float) -> bool:
	return is_equal_approx(float(material.get_shader_parameter("material_depth_fade_near_m")), near_m*unit) and is_equal_approx(float(material.get_shader_parameter("material_depth_fade_far_m")), far_m*unit)
func run() -> void:
	var source := EmberVoxelModelResource.new()
	source.model_id="depth_distance_fixture";source.size_blocks=Vector3i.ONE;source.height_voxels=4
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("738f48")])
	source.voxels.resize(16*4*16);source.voxels.fill(1)
	source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1)
	source.merge_parts=PackedStringArray(["body"])
	source.solid_surface={"version":1,"parts":[PackedVector3Array([Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK])],"occupancy":Solid.occupancy_hash(source.voxels),"roles":PackedStringArray(["","grass"]),"material_ids":PackedStringArray(["","cartoon_grass"])}
	var stage := Node3D.new();root.add_child(stage)
	var map := EmberMapLoader.new();map.name="Map"
	map.compact_terrain=load("res://content/world_terrains/landscape_compact.res").dense_window(Rect2i(0,192,2,2))
	check(map.compact_terrain.validation_errors().is_empty(),"valid bounded main-map terrain")
	stage.add_child(map);map.owner=stage
	var prop: EmberVoxelProp = EmberVoxelPrefab.prepare_resource(source).instantiate()
	prop.authoring_source=source;prop.name="Prop";map.add_child(prop)
	await process_frame
	prop.set_world_look(0)
	var visual := prop.get_node("Mesh") as MeshInstance3D
	var mesh := visual.mesh
	var collision: Shape3D = prop.get_node("Collision/Shape").shape
	var material := visual.get_active_material(0) as ShaderMaterial
	check(distances(material,6,14,16),"prop uses map defaults instead of private 9/22")
	var projection = load("res://scripts/prototypes/ember_terrain_pilot_projection.gd").new()
	map.add_child(projection);projection.set_process(false);projection.world_look=0
	var ground := ShaderMaterial.new();ground.shader=Materials.compact_terrain_bank_depth_shader()
	ground.set_meta("ember_depth_keys",["fixture"])
	projection._bind_depth_material(ground)
	check(distances(ground,6,14,map.imported_tile_size),"ground uses same metres")
	var sphere = load("res://scripts/ember_world_anomaly_3d.gd").new()
	sphere.enabled=false;map.add_child(sphere);sphere.set_process(false)
	var copied := material.duplicate() as ShaderMaterial
	var original := material.duplicate() as ShaderMaterial
	var overlay := MeshInstance3D.new();overlay.visible=false;visual.add_child(overlay)
	sphere._bindings.append({"source":visual,"visual":overlay,"originals":[original],"materials":[copied],"alternate":true})
	var panel = load("res://addons/ember_import/ember_world_look_panel.gd").new()
	root.add_child(panel);panel.hide()
	var history := UndoRedo.new();panel.set_target(stage,map,history)
	panel._commit("compact_depth_fade_far_m",14.0,28.0,false)
	check(distances(material,6,28,16) and distances(copied,6,28,16),"panel updates prop and stale alternate copy")
	history.undo();check(distances(material,6,14,16) and distances(copied,6,14,16),"Undo propagates")
	history.redo();check(distances(material,6,28,16) and distances(copied,6,28,16),"Redo propagates")
	prop.material_pattern_scale=3.0
	check(distances(material,6,28,16),"texture size does not change fade metres")
	check(visual.mesh==mesh and prop.get_node("Collision/Shape").shape==collision and sphere.preparations==0,"uniform update preserves geometry and collision")
	for look in 3:
		prop.set_world_look(look)
		check(distances(visual.get_active_material(0),6,28,16),"look %d keeps map distances"%look)
	prop.set_world_look(0);prop.refresh_solid_material()
	check(distances(visual.get_active_material(0),6,28,16),"material recreation keeps distances")
	map.compact_depth_fade_near_m=32
	check(distances(visual.get_active_material(0),32,33,16) and distances(copied,32,33,16),"crossed sliders retain nonzero smooth fade")
	map.compact_depth_fade_near_m=6
	prop.block_world_size=32;prop._sync_solid_unit();sphere.refresh_material_bindings()
	check(distances(visual.get_active_material(0),6,28,32) and distances(copied,6,28,32),"alternate world units are independent of light-cell units")
	projection._bind_depth_material(ground)
	check(distances(ground,6,28,map.imported_tile_size),"ground refresh agrees after editor change")
	var packed := PackedScene.new();check(packed.pack(stage)==OK,"pack map parameters")
	var path := "user://depth-distance-check.tscn"
	check(ResourceSaver.save(packed,path)==OK,"save")
	var fresh: Node = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	var saved_map: EmberMapLoader = fresh.get_node("Map")
	check(saved_map.compact_depth_fade_near_m==6 and saved_map.compact_depth_fade_far_m==28,"fresh reopen")
	map.compact_depth_fade_far_m=40
	check(saved_map.compact_depth_fade_far_m==28,"discard unsaved change")
	sphere._bindings.clear();fresh.free();history.clear_history();history.free();panel.free()
	print("MATERIAL_DEPTH_DISTANCE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"manual":"visual distance acceptance open"}))
	stage.queue_free();await process_frame
	quit(0 if errors.is_empty() else 1)
