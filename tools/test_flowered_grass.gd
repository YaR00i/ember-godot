extends "res://tools/test_detail_brush.gd"
const Cover = preload("res://scripts/ember_flowered_grass.gd")

func run() -> void:
	output="user://ember-tests/flower-cover"
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

	var artwork:EmberCompactTerrainPattern=load(Cover.PATTERN_PATH).duplicate(true)
	var artwork_path:=output.path_join("cover.tres")
	check(ResourceSaver.save(artwork,artwork_path)==OK,"temporary artwork copy")
	brush.cover_pattern=ResourceLoader.load(artwork_path,"",ResourceLoader.CACHE_MODE_REPLACE)
	brush.controls.kind.select(2);await brush.select_kind(2)
	check(brush.detail_kind==3 and brush._cover_button.visible,"native selector enters textured flower cover")
	for i in brush.controls.kind.item_count:
		var path:Variant=brush.controls.kind.get_item_metadata(i)
		if path is String and path.get_file() in ["vox_detail_daisy.tres","vox_detail_wildflowers.tres"]:check(brush.controls.kind.is_item_disabled(i),"old voxel flower choice disabled")
	brush.controls.radius_m.value=.8;brush.controls.density_per_m2.value=14;brush.controls.size_value.value=.9;await frames(2)
	brush._append(Vector3(32,0,32));await settle();check(count(3)>0,"textured flower preview renders")
	for patch in patches():check(patch.owner==null and patch.density_cells.is_empty() and patch.detail_preset==null,"preview has no authored density or voxel source")
	brush.cancel_stroke();check(patches().is_empty(),"cancel removes flower preview")
	brush._append(Vector3(32,0,32));check(brush.commit_stroke()>0,"flower stroke commits")
	await settle();var saved_count:=count(3);var authored:=snapshot()
	history.undo();check(patches().is_empty(),"one Undo removes whole flower stroke")
	history.redo();await settle();check(snapshot()==authored and count(3)==saved_count,"Redo exact flower stroke")
	brush.controls.erase.button_pressed=true;brush._append(Vector3(32,0,32));brush.commit_stroke();await settle();check(count(3)==0,"flower eraser")
	history.undo();await settle();check(snapshot()==authored and count(3)==saved_count,"eraser Undo restores cover")
	brush.controls.erase.button_pressed=false
	var generations:={};var xz:={}
	for patch in patches():generations[patch.name]=patch.detail_generations
	for look in [0,1,2,0]:
		map.world_look=look;await settle()
		for patch in patches():
			check(patch._visual.visible and patch.detail_preset==null and patch.validation_errors().is_empty(),"painted flowers visible without voxel source in look "+str(look))
			check(patch.prepared_look_mesh(look)==Cover.mesh() and patch._visual.multimesh.mesh==Cover.mesh(),"same card geometry in every look")
			check(patch.detail_generations==generations[patch.name],"look reuses scatter")
			var points:=PackedVector2Array()
			for i in patch._visual.multimesh.instance_count:
				var p:Vector3=patch._visual.multimesh.get_instance_transform(i).origin;points.append(Vector2(p.x,p.z))
			if not xz.has(patch.name):xz[patch.name]=points
			else:check(xz[patch.name]==points,"look preserves XZ")
			check(patch._visual.material_override.get_shader_parameter("flower_atlas")==brush.cover_pattern.albedo_texture,"PNG bound to shared material")
	check(count(3)==saved_count,"all looks retain flower population")
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack flower cover")
	var saved:=output.path_join("roundtrip.tscn");check(ResourceSaver.save(packed,saved)==OK,"save temporary scene")
	var fresh:Node=(ResourceLoader.load(saved,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for patch in patches():
		var other:Node=fresh.get_node("Map/Props/"+str(patch.name))
		check(other.detail_kind==3 and other.detail_preset==null and other.cover_pattern.resource_path==artwork_path and other.density_cells==patch.density_cells and is_equal_approx(other.tuft_size,.9) and other.validation_errors().is_empty(),"fresh reopen mask/size/PNG material reference without voxels")
	fresh.free();brush._append(Vector3(42,0,50));brush.commit_stroke()
	fresh=(ResourceLoader.load(saved,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	for key in authored:check(fresh.get_node("Map/Props/"+key).density_cells==authored[key][0],"discard retains saved mask")
	fresh.free();history.undo();await settle()
	# Same material editor, reduced to the controls this cover consumes.
	brush._edit_cover();await frames(8)
	var editor=brush._cover_dialog
	check(editor._draft!=null and editor._cover_mode and editor._cover_texture_preview.texture!=null and not editor._channel_choice.visible,"native PNG editor opens without unused 16x16/relief controls")
	await RenderingServer.frame_post_draw
	brush._cover_window.get_texture().get_image().save_png(output.path_join("artwork-editor.png"))
	var original_texture:Texture2D=brush.cover_pattern.albedo_texture
	var other_texture:Texture2D=load("res://content/terrain_materials/textures/cartoon_grass.png")
	editor._change_texture(other_texture)
	for patch in patches():check(patch.cover_pattern.albedo_texture==original_texture and patch._visual.material_override.get_shader_parameter("flower_atlas")==other_texture,"texture draft is live but not authored")
	editor.undo_edit()
	for patch in patches():check(patch._visual.material_override.get_shader_parameter("flower_atlas")==original_texture,"texture Undo")
	editor.redo_edit();check(editor._draft.albedo_texture==other_texture,"texture Redo")
	check(editor._save(true),"save texture source through existing editor")
	var reopened:EmberCompactTerrainPattern=ResourceLoader.load(artwork_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.albedo_texture.resource_path==other_texture.resource_path,"artwork fresh reopen")
	editor._change_texture(original_texture);editor.cancel_edit()
	check(brush.cover_pattern.albedo_texture.resource_path==other_texture.resource_path and not brush._cover_window.visible,"artwork discard restores saved texture")
	brush._edit_cover();editor._change_texture(original_texture);check(editor._save(true),"restore fixture texture")
	editor._change_texture(null);check(not editor._save(true),"consumer validation blocks missing PNG")
	editor.undo_edit();editor._change_tone(Color(1,.8,.85),0)
	for patch in patches():check(patch.cover_pattern.base_color==Color.WHITE and patch._visual.material_override.get_shader_parameter("flower_tint").is_equal_approx(Color(1,.8,.85)),"tint draft is live without authored source mutation")
	editor.undo_edit();check(editor._draft.base_color==Color.WHITE,"tint Undo")
	editor.redo_edit();check(editor._save(true),"tint Save");editor.cancel_edit()
	check(brush.cover_pattern.base_color.is_equal_approx(Color(1,.8,.85)),"tint persisted")
	check(source==projection.document and revision==projection.column_revision() and terrain.same_terrain_data(original),"cover and artwork leave terrain unchanged")
	# Ordinary material editor keeps its normal controls.
	var normal=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd").new();root.add_child(normal)
	check(not normal._cover_mode and normal._channel_choice.visible,"ordinary material UI preserved");normal.free()
	print("FLOWER_COVER_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"instances":saved_count,"vertices":Cover.mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),"output":ProjectSettings.globalize_path(output)}))
	brush.deactivate();history.clear_history();history.free();quit(0 if errors.is_empty() else 1)
