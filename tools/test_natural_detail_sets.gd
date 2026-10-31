extends "res://tools/test_detail_brush.gd"
const Bake = preload("res://scripts/ember_detail_pattern_bake.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const IDS = ["wheat","shell"] # Voxel flower attempts were rejected; textured flowers have their own focused test.

func run() -> void:
	output = "user://ember-tests/natural-details"
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

	var populations := {}; var source_snapshots := {}
	for id: String in IDS:
		var path := "res://content/editor/voxel_stamps/vox_detail_"+id+".tres"
		var preset: Resource = load(path)
		source_snapshots[id] = var_to_bytes(preset.geometry.to_definition(true))
		check(Bake.validation_errors(preset).is_empty() and preset.geometry.merge_parts.size()>1, "valid editable multipart Source "+id)
		var selection := -1
		for i in brush.controls.kind.item_count:
			if brush.controls.kind.get_item_metadata(i)==path:selection=i
		check(selection>=2 and not brush.controls.kind.is_item_disabled(selection),"real library choice "+id)
		brush.controls.kind.select(selection);await brush.select_kind(selection)
		check(brush._pattern_ready and brush._pattern_count==1 and not brush._variant_group.visible,"single authored form is ready "+id)
		var prepared: Dictionary = Bake.cached(preset)
		check(prepared.variants[0].meshes.size()==3,"three prepared looks "+id)
		check(prepared.variants[0].meshes[1].surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()!=prepared.variants[0].meshes[2].surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),"low poly and voxel use distinct geometry "+id)
		brush.controls.radius_m.value=.75;brush.controls.density_per_m2.value=12;brush.controls.size_value.value=.8;await frames(2)
		var before:=snapshot()
		brush._append(Vector3(80,0,88));await settle();check(snapshot()!=before,"live preview created "+id)
		brush.cancel_stroke();check(snapshot()==before,"Cancel preserves other sets "+id)
		brush._append(Vector3(80,0,88));brush.commit_stroke();await settle();var committed:=snapshot()
		var total:=count(2);check(total>0,"visible source stroke "+id)
		history.undo();check(snapshot()==before,"one Undo affects selected set only "+id)
		history.redo();await settle();check(snapshot()==committed and count(2)==total,"Redo exact geometry population "+id)
		brush.controls.erase.button_pressed=true;brush._append(Vector3(80,0,88));brush.commit_stroke();await settle()
		check(snapshot()!=committed,"erase selected set "+id);history.undo();await settle();check(snapshot()==committed,"erase Undo "+id)
		brush.controls.erase.button_pressed=false
		populations[id]=total
	var authored:=snapshot();var generations:={};var positions:={};var total:=count(2);var builds:int=Bake.builds
	for patch in patches():
		generations[patch.name]=patch.detail_generations
		var points:=PackedVector2Array()
		for i in patch._visual.multimesh.instance_count:
			var pos:Vector3=patch._visual.multimesh.get_instance_transform(i).origin;points.append(Vector2(pos.x,pos.z))
		positions[patch.name]=points
		var palette:PackedColorArray=patch.detail_preset.geometry.palette
		var lookup:Image=patch._visual.material_override.get_shader_parameter("palette_color_lookup").get_image()
		for slot in palette.size():check(lookup.get_pixel(slot,0).is_equal_approx(palette[slot]),"source colours reach renderer")
	for look in [0,1,2,0]:
		map.world_look=look;await settle();check(count(2)==total and snapshot()==authored,"look preserves all sets")
		for patch in patches():
			check(patch.detail_generations==generations[patch.name],"look reuses placements")
			var points:=PackedVector2Array()
			for i in patch._visual.multimesh.instance_count:
				var pos:Vector3=patch._visual.multimesh.get_instance_transform(i).origin;points.append(Vector2(pos.x,pos.z))
			check(points==positions[patch.name],"look retains XZ")
	check(Bake.builds==builds,"switches reuse source geometry cache")
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack natural detail layers")
	var saved:=output.path_join("roundtrip.tscn");check(ResourceSaver.save(packed,saved)==OK,"save temporary copy")
	var fresh:Node=(ResourceLoader.load(saved,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for patch in patches():
		var other:Node=fresh.get_node("Map/Props/"+str(patch.name))
		check(other.density_cells==patch.density_cells and is_equal_approx(other.tuft_size,.8) and other.detail_preset.resource_path==patch.detail_preset.resource_path and other.validation_errors().is_empty(),"fresh reopen references masks size")
	fresh.free();brush._append(Vector3(90,0,100));brush.commit_stroke()
	fresh=(ResourceLoader.load(saved,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for key in authored:check(fresh.get_node("Map/Props/"+key).density_cells==authored[key][0],"discard restores saved layers")
	fresh.free();history.undo();brush.deactivate()
	# Existing Surface Canvas, isolated user:// sources: real palette/sculpt commands and save.
	var surface_undo:=UndoRedo.new();var workspace:=Workspace.new();root.add_child(workspace);workspace.setup(null,surface_undo);workspace.ensure_ui()
	for id: String in IDS:
		var preset: Resource=load("res://content/editor/voxel_stamps/vox_detail_"+id+".tres")
		var copy:EmberVoxelModelResource=preset.geometry.duplicate_model();var path:=output.path_join(id+".tres")
		check(ResourceSaver.save(copy,path)==OK,"temporary editable source")
		copy=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		workspace.open_surface(copy,path);await frames(2)
		check(workspace._resource==copy,"Surface Canvas opens actual source "+id)
		var before:PackedColorArray=copy.palette.duplicate()
		workspace._apply_palette_operation(copy,{"kind":"set","index":1,"color":Color("608a62")})
		check(copy.palette!=before,"Surface Canvas palette editable "+id)
		surface_undo.undo();check(copy.palette==before,"source palette Undo "+id);surface_undo.redo()
		check(workspace.save_changes(),"Surface Canvas saves source "+id)
		var reopened:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(reopened.palette==copy.palette and reopened.voxel_part_ids==copy.voxel_part_ids and reopened.solid_surface==copy.solid_surface,"source reopen preserves parts/profile "+id)
		workspace._apply_palette_operation(copy,{"kind":"set","index":1,"color":Color.RED});workspace.discard_changes();check(copy.palette==reopened.palette,"source discard "+id)
		var draft:Resource=preset.duplicate(true);draft.geometry=copy
		var changed_key:=Bake.key(draft);check(changed_key!=Bake.key(preset),"palette edits invalidate cache "+id)
		var occupied:int=copy.voxels.find(1);check(workspace._actions.apply_stroke(copy,{occupied:{"before":int(copy.voxels[occupied]),"after":0}}),"Surface Canvas erases occupied source cell "+id)
		check(copy.voxels[occupied]==0 and copy.voxel_part_ids[occupied]==0,"source sculpt preserves ownership invariant")
		var edited:Dictionary=await Bake.prepare(draft,map);check(edited.has("variants"),"sculpted Source still prepares three looks "+id)
		surface_undo.undo();workspace.discard_changes();surface_undo.clear_history()
		if id=="wheat":
			check(workspace._actions.apply_stroke(copy,{0:{"before":0,"after":1}}),"new unowned sculpt cell can be added")
			var fallback:Dictionary=await Bake.prepare(draft,map)
			check(fallback.variants[0].meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==fallback.variants[0].meshes[2].surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"unowned additions retain exact visible voxel geometry")
			surface_undo.undo();workspace.discard_changes();surface_undo.clear_history()
			# Simulate a separately opened source being saved; explicit library refresh replaces stale cached data.
			var preset_dir:=output.path_join("presets");DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(preset_dir))
			var preset_path:=preset_dir.path_join("copy.tres")
			check(ResourceSaver.save(draft,preset_path)==OK,"temporary canonical preset link")
			var linked:Resource=load(preset_path);var linked_geometry:Resource=linked.geometry
			var saved_source:Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			saved_source.palette[1]=Color("4477aa");check(ResourceSaver.save(saved_source,path)==OK,"separate editor saves source")
			var rows:=Bake.choices(true,preset_dir)
			check(rows.size()==1 and linked==load(preset_path) and linked.geometry==linked_geometry and linked.geometry.palette[1].is_equal_approx(Color("4477aa")),"explicit refresh updates shared saved source without replacing its identity")
		check(var_to_bytes(preset.geometry.to_definition(true))==source_snapshots[id],"canonical Source untouched by temporary authoring "+id)
	workspace.free();surface_undo.clear_history();surface_undo.free()
	check(source==projection.document and revision==projection.column_revision() and terrain.same_terrain_data(original),"detail painting never changes terrain")
	print("NATURE_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"sets":IDS.size(),"instances":total,"populations":populations}))
	history.clear_history();history.free();quit(0 if errors.is_empty() else 1)
