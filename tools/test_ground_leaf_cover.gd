extends "res://tools/test_detail_brush.gd"

const LeafCover := preload("res://scripts/ember_ground_leaf_cover.gd")


func run() -> void:
	output = "user://ember-tests/ground-leaf-cover"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var terrain := EmberTerrainPilotResource.new()
	terrain.width = 128
	terrain.depth = 128
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color("6c963b")])
	terrain.palette_surface_roles = PackedStringArray(["", "grass"])
	terrain.palette_material_ids = PackedStringArray(["", "cartoon_grass"])
	var size := terrain.width * terrain.depth
	terrain.heights.resize(size)
	terrain.top_materials.resize(size)
	terrain.top_materials.fill(1)
	terrain.base_materials = terrain.top_materials.duplicate()
	terrain.cap_depths.resize(size)
	terrain.cap_depths.fill(1)
	terrain.water_levels.resize(size)
	terrain.water_materials.resize(size)
	for z in terrain.depth:
		for x in terrain.width:
			terrain.heights[z * terrain.width + x] = 5 + maxi(x - 64, 0) / 4
	var original := terrain.working_copy()
	scene = Node3D.new()
	scene.name = "LeafCoverFixture"
	map = EmberMapLoader.new()
	map.name = "Map"
	map.compact_terrain = terrain
	map.compact_ground_style = 1
	map.world_look = 0
	scene.add_child(map)
	map.owner = scene
	var props := Node3D.new()
	props.name = "Props"
	map.add_child(props)
	props.owner = scene
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	scene.add_child(sun)
	var camera := Camera3D.new()
	scene.add_child(camera)
	root.add_child(scene)
	current_scene = scene
	camera.look_at_from_position(Vector3(64, 105, 117), Vector3(64, 6, 32))
	camera.make_current()
	var projection := map._visual_surface_projection
	var deadline := Time.get_ticks_msec() + 30000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	var revision: int = projection.column_revision()
	brush = Brush.new()
	root.add_child(brush)
	check(brush.activate_details(scene, map, history), "activate native details brush")
	var panel: Control = brush.build_panel()
	root.add_child(panel)
	panel.hide()
	brush.controls.kind.select(3)
	brush.controls.kind.item_selected.emit(3)
	brush.controls.radius_m.value = 1.6
	brush.controls.density_per_m2.value = 200
	var flat := Vector3(32, 5, 32)
	var slope := Vector3(96, 12, 32)
	brush._append(flat)
	await settle()
	check(_visible_decals() > 0, "preview visible on flat terrain")
	check(LeafCover.painted_density_at(map, map.imported_tile_size, flat) == 0.0, "runtime contact ignores unsaved draft")
	brush.cancel_stroke()
	check(patches().is_empty(), "discard removes preview")
	brush._append(flat)
	brush._append(slope)
	check(brush.commit_stroke() > 0, "commit covers flat and slope")
	await settle()
	var authored := snapshot()
	check(_visible_decals() == 2, "one decal per occupied tile")
	check(LeafCover.painted_density_at(map, map.imported_tile_size, flat) > 0.0, "runtime contact reads painted cells")
	for patch in patches():
		var decal: Decal = patch._leaf_decal
		check(decal != null and decal.cull_mask == LeafCover.GROUND_LAYER, "only terrain receives leaves")
		check(decal != null and decal.texture_albedo.get_width() == 256, "projection preserves close-up leaf contours")
		var folded := patch._folded_leaves as MeshInstance3D
		check(folded != null and folded.visible and folded.mesh != null and folded.mesh.get_aabb().size.y > 0.1,
			"mask generates genuinely raised leaf geometry")
		if folded != null and folded.mesh != null:
			check(folded.mesh.surface_get_array_len(0) <= LeafCover.MAX_FOLDED_LEAVES * 12, "folded geometry stays bounded per tile")
		if patch.position.x > 0 and decal != null:
			check(decal.size.y > map.imported_tile_size, "projection spans slope height")
	await capture("leaf-cover-flat-and-slope")
	var flat_patch: Node3D = patches()[0]
	var flat_layer: Texture2D = flat_patch._leaf_decal.texture_albedo
	var default_mesh: ArrayMesh = flat_patch._folded_leaves.mesh
	var default_count := default_mesh.surface_get_array_len(0)
	check(brush._cover_mesh_panel.visible and brush._cover_mesh_density.value == 100.0, "shared recipe starts at accepted density")
	brush._cover_mesh_density.value = 0.0
	brush._preview_cover_mesh_preset()
	await settle()
	check(flat_patch._folded_leaves.mesh == null and flat_patch._leaf_decal.texture_albedo == flat_layer, "zero raised leaves keeps the same ground texture")
	brush._cover_mesh_history.undo()
	await settle()
	check(flat_patch._folded_leaves.mesh != null and flat_patch._folded_leaves.mesh.surface_get_array_len(0) == default_count, "density preview Undo restores geometry")
	brush._cover_mesh_history.redo()
	await settle()
	check(flat_patch._folded_leaves.mesh == null, "density preview Redo hides geometry")
	brush._cover_mesh_density.value = 200.0
	brush._preview_cover_mesh_preset()
	await settle()
	check(flat_patch._folded_leaves.mesh != null and flat_patch._folded_leaves.mesh.surface_get_array_len(0) > default_count, "raised leaf density can increase")
	check(snapshot() == authored and flat_patch._leaf_decal.texture_albedo == flat_layer, "density changes only the derived mesh")
	await capture("leaf-cover-dense-details")
	brush.select_kind(4)
	await settle()
	check(flat_patch._folded_leaves.mesh.surface_get_array_len(0) == default_count and brush._cover_mesh_dimensions.visible, "switching to moss discards leaf preview")
	brush.select_kind(3)
	check(not brush._cover_mesh_dimensions.visible and brush._cover_mesh_density.value == 100.0, "return to unchanged leaf preset")
	brush._cover_mesh_density.value = 200.0
	var recipe_path := output.path_join("leaf-recipe.tres")
	brush._save_cover_mesh_preset(recipe_path)
	await settle()
	var recipe := ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberCompactTerrainPattern
	check(recipe != null and recipe.detail_density == 2.0 and flat_patch._folded_leaves.mesh.surface_get_array_len(0) > default_count, "saved recipe reloads and updates existing leaves")
	brush._cover_mesh_density.value = 100.0
	brush._save_cover_mesh_preset(recipe_path)
	await settle()
	history.undo()
	check(patches().is_empty(), "one Undo removes the whole stroke")
	check(LeafCover.painted_density_at(map, map.imported_tile_size, flat) == 0.0, "detached tile cannot receive contact")
	history.redo()
	await settle()
	check(snapshot() == authored and _visible_decals() == 2, "Redo restores exact painted mask")
	check(LeafCover.painted_density_at(map, map.imported_tile_size, flat) > 0.0, "redo registers reattached tile")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "pack authored mask")
	var path := output.path_join("leaf-cover-fixture.tscn")
	check(ResourceSaver.save(packed, path) == OK, "save isolated map")
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_patches := reopened.get_node("Map/Props").get_children()
	for patch in saved_patches:
		check(patch.detail_kind == LeafCover.KIND and patch.density_cells == authored[str(patch.name)][0], "reopen keeps authored leaf masks")
		check(patch.get_child_count(true) == 0, "derived decal is transient")
	root.add_child(reopened, true)
	deadline = Time.get_ticks_msec() + 15000
	var count_ready := 0
	while Time.get_ticks_msec() < deadline:
		count_ready = 0
		for patch in saved_patches:
			if is_instance_valid(patch._leaf_decal) and patch._leaf_decal.texture_albedo != null:
				count_ready += 1
		if count_ready == saved_patches.size():
			break
		await process_frame
	check(count_ready == 2, "reopened map rebuilds both projections")
	for patch in saved_patches:
		if not is_instance_valid(patch._leaf_decal) or patch._leaf_decal.texture_albedo == null:
			continue
		var previous := props.get_node(NodePath(patch.name))
		check(patch._leaf_decal.texture_albedo.get_image().get_data() == previous._leaf_decal.texture_albedo.get_image().get_data(),
			"reopened decal has the identical texture")
		check(patch._folded_leaves != null and previous._folded_leaves != null
			and patch._folded_leaves.mesh.surface_get_arrays(0) == previous._folded_leaves.mesh.surface_get_arrays(0),
			"reopened geometry matches the same mask and seed")
	reopened.free()
	brush.controls.erase.button_pressed = true
	brush._append(flat)
	brush.commit_stroke()
	await settle()
	check(_visible_decals() == 1, "eraser clears only the flat tile")
	check(LeafCover.painted_density_at(map, map.imported_tile_size, flat) == 0.0, "erased cells stop receiving contact")
	for patch in patches():
		if patch.position.x == 0:
			check(patch._folded_leaves == null or not patch._folded_leaves.visible, "eraser also clears raised leaves")
	check(terrain.same_terrain_data(original) and revision == projection.column_revision(), "painting leaves terrain data unchanged")
	print("LEAF_COVER ", JSON.stringify({"pass": errors.is_empty(), "errors": errors, "viewport": str(root.size)}))
	brush.deactivate()
	history.clear_history()
	history.free()
	quit(0 if errors.is_empty() else 1)


func _visible_decals() -> int:
	var total := 0
	for patch in patches():
		if is_instance_valid(patch._leaf_decal) and patch._leaf_decal.visible:
			total += 1
	return total
