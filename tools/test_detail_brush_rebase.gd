extends "res://tools/test_detail_brush.gd"
## A west extension preserves old world positions but changes local patch addresses.
func run() -> void:
	var terrain:=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd").base()
	terrain.top_materials.fill(2);terrain.heights.fill(24);terrain.column_material_overrides.clear();terrain.surface_rules.clear()
	scene=Node3D.new();map=EmberMapLoader.new();map.name="Map"
	map.compact_terrain=terrain;map.compact_ground_style=1;map.world_look=0
	scene.add_child(map);map.owner=scene
	var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	root.add_child(scene);current_scene=scene
	while map._visual_surface_projection.pending_tile_count()>0 or map._visual_surface_projection.built_tile_count()<4:await process_frame
	await frames(5)
	brush=Brush.new();root.add_child(brush);check(brush.activate_details(scene,map,history),"activate")
	brush.radius_m=0.35;brush.density_per_m2=60.0
	brush._append(Vector3(16,0,32));check(brush.commit_stroke()>0,"initial grass")
	if props.get_node_or_null("DetailGrass_0_0")==null:quit(1);return
	var old:Node3D=props.get_node("DetailGrass_0_0");var cells:Dictionary=old.density_cells.duplicate()
	map.position.x-=64;props.position.x+=64;await frames(3)
	brush.density_per_m2=80.0
	brush._append(map.to_global(Vector3(16,0,32)))
	check(not brush._drafts.has(old),"west preview does not reuse retained patch by old name")
	check(brush._patch(Vector2i(1,0))==old,"old patch found at its new local address")
	brush.cancel_stroke();check(props.get_child_count()==1 and old.density_cells==cells,"cancel preserves retained grass")
	brush.erase=true;brush._append(Vector3(16,0,32))
	check(brush._drafts.has(old),"eraser finds retained patch at its world position")
	brush.commit_stroke();check(old.density_cells!=cells,"erase commits")
	history.undo();check(old.density_cells==cells,"erase Undo restores exact old mask")
	# The same spatial index must keep flower sources and library variants separate.
	var extra:Array[Node]=[]
	var frame:Transform3D=props.global_transform.affine_inverse()*map.global_transform
	brush.erase=false;brush.detail_kind=3
	for path:String in ["res://content/terrain_materials/meadow_daisy_cover.tres","res://content/terrain_materials/meadow_lilac_cover.tres"]:
		var flower:=Brush.Patch.new();flower.painted_only=true;flower.detail_kind=3;flower.cover_pattern=load(path)
		props.add_child(flower);flower.transform=frame;extra.append(flower)
		brush.cover_pattern=flower.cover_pattern;brush._index_patches()
		check(brush._patch(Vector2i.ZERO)==flower,"flower index keeps selected source")
	var preset:=preload("res://addons/ember_import/ember_voxel_stamp_preset.gd").new()
	preset.geometry=EmberVoxelModelResource.new();preset.geometry.model_id="fixture_detail_index"
	brush.detail_kind=2;brush.pattern_preset=preset;brush.pattern_variant=-1
	for variant in 2:
		var part:=Brush.Patch.new();part.painted_only=true;part.detail_kind=2;part.detail_preset=preset;part.detail_variant=variant
		props.add_child(part);part.transform=frame;extra.append(part);brush._index_patches()
		check(brush._patch(Vector2i.ZERO,variant)==part,"library index keeps variant")
	brush.pattern_variant=0;brush._index_patches();check(brush._patch_lookup.is_empty(),"single variant does not reuse mixed mask")
	for node in extra:node.free()
	brush.deactivate();brush.free();history.clear_history();history.free()
	scene.queue_free();await frames(3)
	print("DETAIL_REBASE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
