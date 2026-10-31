extends "res://tools/test_detail_brush.gd"
## Visual-only contract: small stones use one faceted shape and disappear in voxel regions.
func run() -> void:
	output="user://ember-tests/detail-stone-looks"
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

	brush.controls.kind.select(1);await brush.select_kind(1)
	brush.controls.radius_m.value=.65;brush.controls.density_per_m2.value=16;await frames(2)
	brush._append(Vector3(80,0,88));brush.commit_stroke();await settle()
	for spec in [["vox_stamp_104392975",Vector3(80,0,88)]]:
		var path:String="res://content/editor/voxel_stamps/"+spec[0]+".tres";var selected:=-1
		for i in brush.controls.kind.item_count:
			if brush.controls.kind.get_item_metadata(i)==path:selected=i
		brush.controls.kind.select(selected);await brush.select_kind(selected)
		brush.controls.density_per_m2.value=12;await frames(2)
		brush._append(spec[1]);brush.commit_stroke();await settle()
	brush.controls.kind.select(2);await brush.select_kind(2)
	brush.controls.density_per_m2.value=12;await frames(2)
	brush._append(Vector3(24,0,40));brush.commit_stroke();await settle()
	var authored:=snapshot();var generations:={};var stone_count:=0;var flower_count:=0
	for patch in patches():
		generations[patch.name]=patch.detail_generations
		if patch.is_detail_stone():stone_count+=patch._visual.multimesh.instance_count
		else:flower_count+=patch._visual.multimesh.instance_count
	check(stone_count>0 and flower_count>0,"fixture contains both stone sources and flowers")
	for look in [0,1,2,0]:
		map.world_look=look;await settle()
		for patch in patches():
			check(patch.detail_generations==generations[patch.name],"look reuses scatter")
			if patch.is_detail_stone():
				check(patch._visual.visible==(look!=2),"small stone visibility follows look "+str(look))
				check(patch.prepared_look_mesh(0)==patch.prepared_look_mesh(1),"detailed and low poly use same faceted stone")
				check(patch._visual.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==patch.prepared_look_mesh(1).surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"rendered stone uses faceted geometry")
			else:check(patch._visual.visible and patch.detail_preset==null,"textured flowers remain visible without voxel source")
	check(snapshot()==authored and source==projection.document and revision==projection.column_revision(),"visual rule leaves authored masks and terrain unchanged")
	var sphere:=preload("res://scripts/ember_world_anomaly_3d.gd").new();sphere.name="WorldAnomaly";sphere.inner_look=2;map.add_child(sphere)
	var timeout:=Time.get_ticks_msec()+30000
	while not sphere._prepared and Time.get_ticks_msec()<timeout:await process_frame
	check(sphere._prepared,"sphere prepares fixture")
	for patch in patches():
		if not patch.is_detail_stone():continue
		var bindings:=0
		for binding:Dictionary in sphere._bindings:
			if binding.source==patch._visual:
				bindings+=1
				check(not binding.voxel_only and int(binding.materials[0].get_shader_parameter("ember_anomaly_grass_form"))==1,"stone only shrinks inside voxel sphere; no voxel duplicate")
		check(bindings==1,"one sphere binding per small-stone source")
	var preparations:int=sphere.preparations;sphere.position.x+=16;await frames(8)
	check(sphere.preparations==preparations,"sphere motion reuses prepared stone transition")
	print("DETAIL_STONE_LOOKS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"stones":stone_count,"flowers":flower_count}))
	brush.deactivate();history.clear_history();history.free();quit(0 if errors.is_empty() else 1)
