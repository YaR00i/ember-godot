extends "res://tools/test_detail_brush.gd"
const Cover = preload("res://scripts/ember_flowered_grass.gd")

func run() -> void:
	output="user://ember-tests/flower-sets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	# Controlled 8x8m fixture, with grass/sand and a wet edge; no authored map dependency.
	var terrain := EmberTerrainPilotResource.new(); terrain.width = 128; terrain.depth = 128
	terrain.palette = PackedColorArray([Color.TRANSPARENT,Color("6c963b"),Color("cdb482")])
	terrain.palette_surface_roles = PackedStringArray(["","grass","sand"])
	terrain.palette_material_ids = PackedStringArray(["","cartoon_grass","cartoon_sand"])
	var cells := terrain.width * terrain.depth
	terrain.heights.resize(cells); terrain.heights.fill(4)
	terrain.top_materials.resize(cells); terrain.base_materials.resize(cells); terrain.base_materials.fill(1)
	terrain.cap_depths.resize(cells); terrain.cap_depths.fill(1)
	terrain.water_levels.resize(cells); terrain.water_materials.resize(cells)
	for z in terrain.depth:
		for x in terrain.width:
			var i := x + z * terrain.width; terrain.top_materials[i] = 1 if x < 64 else 2
			if x >= 112: terrain.water_levels[i] = 6; terrain.water_materials[i] = 2
	check(terrain.validation_errors().is_empty(),"controlled fixture validates")
	var original := terrain.working_copy()
	scene = Node3D.new(); scene.name = "DetailFixture"
	map = EmberMapLoader.new(); map.name = "Map"; map.compact_terrain = terrain; map.compact_ground_style = 1; map.world_look = 0
	scene.add_child(map); map.owner = scene
	var props := Node3D.new(); props.name = "Props"; map.add_child(props); props.owner = scene
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-35,0); scene.add_child(sun)
	root.add_child(scene); current_scene = scene
	var deadline := Time.get_ticks_msec() + 30000
	while map._visual_surface_projection == null or map._visual_surface_projection.pending_tile_count() > 0:
		if Time.get_ticks_msec() > deadline: check(false,"fixture startup timeout"); break
		await process_frame
	var projection: Node = map._visual_surface_projection
	var revision: int = projection.column_revision()
	var source: Resource = projection.document
	brush = Brush.new(); root.add_child(brush); check(brush.activate_details(scene,map,history), "activate density brush")
	var panel: Control = brush.build_panel()
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	var backing := PanelContainer.new(); backing.position = Vector2(1030,16); backing.size = Vector2(390,860); canvas.add_child(backing)
	var background := StyleBoxFlat.new(); background.bg_color = Color(0.07,0.085,0.10,0.98); background.content_margin_left = 12; background.content_margin_right = 12; backing.add_theme_stylebox_override("panel",background)
	var scroll := ScrollContainer.new(); backing.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.add_child(panel)
	panel.theme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd").build(ThemeDB.get_default_theme())
	check(brush.controls.has("kind") and brush.controls.has("density_per_m2") and brush.controls.has("size_value"), "native panel exposes kind and brush controls")

	await frames(2)

	var expected:={};var counts:={};var set_paths:=[]
	brush.controls.kind.select(2);await brush.select_kind(2)
	brush.controls.radius_m.value=.8;brush.controls.density_per_m2.value=14
	for index in Cover.SETS.size():
		brush.controls.cover.select(index);brush.select_cover(index)
		check(brush.cover_pattern.flower_shape==index,"native set selector chooses saved shape")
		var path:=output.path_join("set%d.tres" % index)
		check(ResourceSaver.save(brush.cover_pattern.duplicate(true),path)==OK,"temporary source copy")
		brush.cover_pattern=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REPLACE);set_paths.append(path)
		brush._append(Vector3(32,0,32));await settle()
		check(patches().size()==index+1,"same tile has a separate mask for each source")
		brush.cancel_stroke();check(patches().size()==index,"cancel removes only selected source preview")
		brush._append(Vector3(32,0,32));brush.commit_stroke();await settle()
		var layer:Node=patches().back();expected[layer.name]=layer.density_cells.duplicate();counts[layer.name]=layer._visual.multimesh.instance_count
		check(layer.cover_pattern==brush.cover_pattern and layer.detail_preset==null,"source reference without voxels")
		check(layer._visual.multimesh.mesh==Cover.mesh(brush.cover_pattern),"saved set selects its own geometry")
	var authored:=snapshot();check(patches().size()==3,"three overlapping sources coexist")
	history.undo();check(patches().size()==2,"one Undo removes last set only")
	history.redo();await settle();check(snapshot()==authored,"Redo restores third set exactly")
	brush.controls.erase.button_pressed=true;brush._append(Vector3(32,0,32));brush.commit_stroke();await settle()
	for layer in patches():
		if layer.cover_pattern.resource_path==set_paths[2]:check(layer._visual.multimesh.instance_count==0,"selected set erased")
		else:check(layer.density_cells==expected[layer.name] and layer._visual.multimesh.instance_count==counts[layer.name],"erase leaves other flowers untouched")
	history.undo();await settle();brush.controls.erase.button_pressed=false
	for look in [0,1,2,0]:
		map.world_look=look;await settle()
		for layer in patches():check(layer._visual.visible and layer._visual.multimesh.mesh==Cover.mesh(layer.cover_pattern),"every set retains thin shape in every look")
	var scene_path:=output.path_join("sets.tscn");var packed:=PackedScene.new()
	check(packed.pack(scene)==OK and ResourceSaver.save(packed,scene_path)==OK,"save mixed sets")
	var reopened:Node=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for layer in patches():
		var other:Node=reopened.get_node("Map/Props/"+str(layer.name))
		check(other.density_cells==expected[layer.name] and other.cover_pattern.resource_path==layer.cover_pattern.resource_path and other.cover_pattern.flower_shape==layer.cover_pattern.flower_shape,"reopen source/shape/mask")
	reopened.free()
	brush._append(Vector3(44,0,32));brush.commit_stroke();await settle()
	reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for key in expected:check(reopened.get_node("Map/Props/"+key).density_cells==expected[key],"discard keeps saved set masks")
	reopened.free();history.undo();await settle()
	# Shape edits are private previews; they never mutate another family's source or placement.
	brush._edit_cover();await frames(6)
	var editor=brush._cover_dialog
	check(editor._cover_shape.selected==2,"material editor shows source shape")
	editor._change_cover_shape(1);await settle()
	for layer in patches():
		check(layer.density_cells==expected[layer.name],"shape change leaves masks")
		if layer.cover_pattern.resource_path==set_paths[2]:check(layer.cover_pattern.flower_shape==2 and layer._visual.multimesh.mesh==Cover.mesh(editor._draft),"shape preview without source mutation")
		else:check(layer._visual.multimesh.mesh==Cover.mesh(layer.cover_pattern),"other set geometry not changed")
	editor.undo_edit();await settle();check(editor._draft.flower_shape==2,"shape Undo")
	editor.redo_edit();await settle();check(editor._save(true),"shape Save");editor.cancel_edit();await settle()
	check(brush.cover_pattern.flower_shape==1,"shape stored in shared source")
	var saved:EmberCompactTerrainPattern=ResourceLoader.load(set_paths[2],"",ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.flower_shape==1,"shape fresh reopen")
	brush._edit_cover();editor._change_cover_shape(2);await settle();editor.cancel_edit();await settle()
	check(brush.cover_pattern.flower_shape==1,"shape discard restores saved source")
	var bad:EmberCompactTerrainPattern=brush.cover_pattern.duplicate(true);bad.flower_shape=99
	check(not bad.validation_errors().is_empty(),"unknown shape rejected")
	check(source==projection.document and revision==projection.column_revision() and terrain.same_terrain_data(original),"sets leave terrain untouched")
	# A changed Source shape must invalidate the existing sphere mesh, not just its material.
	var sphere:=preload("res://scripts/ember_world_anomaly_3d.gd").new();sphere.name="WorldAnomaly";map.add_child(sphere)
	deadline=Time.get_ticks_msec()+30000
	while not sphere._prepared and Time.get_ticks_msec()<deadline:await process_frame
	check(sphere._prepared,"sphere prepares mixed fixture")
	brush._edit_cover();editor._change_cover_shape(2);await settle()
	deadline=Time.get_ticks_msec()+30000
	var rebound:=false
	while not rebound and Time.get_ticks_msec()<deadline:
		await process_frame
		if not sphere._prepared:continue
		for binding:Dictionary in sphere._bindings:
			if binding.source.get_parent() in patches() and binding.source.get_parent().cover_pattern==brush.cover_pattern and binding.mesh==Cover.mesh(editor._draft):rebound=true
	check(rebound,"sphere uses fresh shape after artwork preview")
	var preparations:int=sphere.preparations;sphere.position.x+=16;await frames(8)
	check(sphere.preparations==preparations,"sphere motion reuses new geometry")
	editor.cancel_edit()
	print("FLOWER_SETS_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"sets":patches().size(),"masks_independent":true}))
	brush.deactivate();history.clear_history();history.free();quit(0 if errors.is_empty() else 1)
