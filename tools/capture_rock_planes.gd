extends "res://tools/capture_rock_form_rules.gd"
const RockFixture=preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const RockPlanes=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")

func setup_capture_view(view: int) -> void:
	super.setup_capture_view(view)
	if view==0:
		# Same real follow camera/FOV/distance, aimed slightly higher so the
		# rock's peak is in frame. Identical pose in all A/B captures.
		scene.follow_camera.look_height=1.35
		scene.follow_camera.reset_follow_height()
		scene.follow_camera._process(0.0)

func build_variant(source,code: int) -> Dictionary:
	if code!=Rules.protect_code(0.75):return await super.build_variant(source,code)
	var carved:=RockFixture.chiselled_rock_source(source)
	var document=carved.source
	check(carved.changed_columns>0 and carved.peak_before_m==carved.peak_after_m,"chips change shape but retain peak")
	check(carved.max_cut_m<=0.375,"bounded cuts preserve overall masses")
	for i in source.width*source.depth:
		check(source.top_materials[i]==document.top_materials[i],"paint unchanged")
		if source.top_materials[i]!=1:check(source.heights[i]==document.heights[i],"non-rock heights unchanged")
	var built:=await super.build_variant(document,Rules.round_code(1.0,1))
	# Detailed ordinary rock can have hard geological planes. Reuse the
	# existing bounded plane fit, and advance the physical field with it.
	var largest:=0.0
	for key: Vector2i in built.tiles:
		var tile: Dictionary=built.tiles[key]
		var begin:=key*64
		var bounds:=Rect2i(begin,Vector2i(mini(64,source.width-begin.x),mini(64,source.depth-begin.y)))
		var original: ArrayMesh=tile.terrain
		var fitted:=RockPlanes.rock_faceted(original,original,tile.smooth_field,bounds)
		var field: Dictionary=tile.smooth_field.duplicate(true)
		var old_points: PackedVector3Array=original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var new_points: PackedVector3Array=fitted.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in old_points.size():
			var old:=old_points[i]
			if absf(old.y-Smooth.corner(tile.smooth_field,roundi(old.x),roundi(old.z)))>0.0001:continue
			var cell:=Vector2i(roundi(old.x),roundi(old.z))-Vector2i(field.start)
			field.heights[cell.x+cell.y*field.size.x]=new_points[i].y
		fitted.mesh.surface_set_material(0,original.surface_get_material(0))
		tile.terrain=RockPlanes.soften_within_stone_planes(fitted.mesh)
		check(tile.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==new_points,"crease normals preserve geometry")
		tile.smooth_field=field;tile.collision_faces=new_points
		largest=maxf(largest,fitted.max_error_m)
		await process_frame
	carved.plane_fit_error_m=largest
	check(ResourceSaver.save(built.document,output.path_join("chiselled-source.res"))==OK,"save private source")
	carved.erase("source")
	var file:=FileAccess.open(output.path_join("sculpt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(carved,"\t"));file.close()
	return built
