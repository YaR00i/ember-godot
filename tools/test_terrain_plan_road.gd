extends "res://tools/test_terrain_plan_mountain.gd"
func road_plan() -> Resource:
	var plan := mountain_plan()
	var points := PackedVector2Array([Vector2(8,24),Vector2(18,24),Vector2(30,24),Vector2(40,24)])
	plan.regions.append({"id":"road","name":"Дорога","kind":"road","enabled":true,"points_m":points,"bounds":Plan.Influence.road_bounds(points,Plan.Influence.ROAD_DEFAULTS,Vector2i(48,48)),"parameters":Plan.Influence.ROAD_DEFAULTS.duplicate()})
	return plan
func _run() -> void:
	var source := fixture(); var plan := road_plan(); var first := compose(source,plan)
	var soil: int = source.palette_surface_roles.find("soil"); var grass: int = source.palette_surface_roles.find("grass")
	if first.candidate == null: quit(1); return
	var layer: Dictionary = first._layers[1]
	check(layer.start_height_m == 6.0 and layer.end_height_m == 6.0,"road endpoint heights")
	var center := Vector2i(384,384); var index: int = source.column_index(center.x,center.y)
	check(first.candidate.column_value("heights",index) == 96 and first.candidate.column_value("top_materials",index) == soil,"road core height/material")
	for x in range(8*16,40*16,8):
		var i: int = source.column_index(x,24*16)
		check(first.candidate.column_value("heights",i) == 96 and first.candidate.column_value("top_materials",i) == soil,"road centre gap")
	var mountain := compose(source,mountain_plan())
	check(first.candidate.column_value("heights",source.column_index(24*16,30*16)) == mountain.candidate.column_value("heights",source.column_index(24*16,30*16)),"outside corridor changed")
	check(first.candidate.column_value("heights",source.column_index(24*16,27*16)) > 96,"shoulder not blended")
	check(source.column_value("heights",index) == 96 and plan.patches.is_empty(),"road source mutated")
	for key in source.sections:
		for channel in ["water_levels","water_materials","water_flow"]: check(first.candidate.sections[key].get(channel) == source.sections[key].get(channel),"road changed water "+channel)
	var repeat := compose(first.candidate,first.output_plan,1300)
	check(repeat.candidate != null and repeat.candidate.same_terrain_data(first.candidate) and Plan.same(repeat.output_plan,first.output_plan),"road repeat accumulation")
	check(compose(source,plan,50000).candidate.same_terrain_data(first.candidate),"road work budget changed geometry")
	var reverse: Resource = plan.working_copy(); reverse.regions[1].points_m.reverse()
	check(compose(source,reverse).candidate.same_terrain_data(first.candidate),"road reverse changed geometry")
	var moved: Resource = first.output_plan.working_copy()
	var points := PackedVector2Array([Vector2(8,40),Vector2(20,40),Vector2(40,40)])
	moved.regions[1].points_m = points; moved.regions[1].bounds = Plan.Influence.road_bounds(points,moved.regions[1].parameters,Vector2i(48,48))
	var move := compose(first.candidate,moved)
	check(move.candidate != null and move.candidate.column_value("heights",index) == 192 and move.candidate.column_value("top_materials",index) == grass,"old road terrain/material not restored")
	var off: Resource = first.output_plan.working_copy(); off.regions[1].enabled = false
	check(compose(first.candidate,off).candidate.same_terrain_data(mountain.candidate),"road off did not restore previous mountain")
	var deleted: Resource = first.output_plan.working_copy(); deleted.regions.clear()
	check(compose(first.candidate,deleted).candidate.same_terrain_geometry(source,true),"road/layers delete did not restore source")
	for channel in ["heights","top_materials","water_levels","side","flow"]:
		var manual: Resource = first.candidate.working_copy(); var part: Resource = manual.sections[Vector2i(1,1)].working_copy()
		if channel == "side": part.column_material_overrides[0] = {0:1}
		elif channel == "flow": part.water_flow.resize(24*24); part.water_flow[0] = Vector2(0.1,0.2)
		else:
			var values: Variant = part.get(channel); values[0] = values[0]+4 if channel == "heights" else 4 if channel == "water_levels" else grass; part.set(channel,values)
		manual.sections[Vector2i(1,1)] = part
		var keep := compose(manual,moved)
		if keep.candidate == null: quit(1); return
		check(keep.protected_blocks.has(center/16),"road protection missing "+channel)
		check(keep.candidate.column_value("heights",index) == manual.column_value("heights",index) and keep.candidate.column_value("top_materials",index) == manual.column_value("top_materials",index) and keep.candidate.flow_at_cell(center.x,center.y) == manual.flow_at_cell(center.x,center.y),"road erased manual "+channel)
	var slope: Resource = plan.working_copy(); points = PackedVector2Array([Vector2(12,24),Vector2(24,24)])
	slope.regions[1].points_m = points; slope.regions[1].bounds = Plan.Influence.road_bounds(points,slope.regions[1].parameters,Vector2i(48,48))
	reject(source,slope,"excessive road grade accepted")
	slope.regions[1].parameters.grade_percent = 50.0
	var allowed := compose(source,slope)
	check(allowed.candidate != null and allowed._layers[1].end_height_m == 12.0,"allowed grade rejected")
	var invalid: Resource = plan.working_copy(); points = PackedVector2Array([Vector2(8,4),Vector2(32,4)])
	invalid.regions[1].points_m = points; invalid.regions[1].bounds = Plan.Influence.road_bounds(points,invalid.regions[1].parameters,Vector2i(48,48))
	reject(source,invalid,"wet road accepted")
	invalid = plan.working_copy(); invalid.regions[1].parameters.width_m = NAN
	check(not invalid.validation_errors().is_empty(),"road NaN accepted")
	invalid = plan.working_copy(); invalid.regions[1].points_m[1] = Vector2(INF,24)
	check(not invalid.validation_errors().is_empty(),"road invalid points accepted")
	var missing_soil: Resource = source.working_copy(); missing_soil.palette_surface_roles[soil] = ""; missing_soil.palette_material_ids[soil] = ""
	reject(missing_soil,plan,"road without soil role accepted")
	var legacy: Resource = mountain.output_plan.working_copy(); legacy.schema_version = 5
	var v5: Resource = Plan.from_data(legacy.data()); check(v5 != null,"v5 read")
	var upgraded: Resource = v5.working_copy(); upgraded.upgrade_local_layers()
	check(upgraded.patches == v5.patches and v5.schema_version == 5,"v5 upgrade mutated provenance")
	var shifted: Resource = first.output_plan.translated(Vector2i(24,24))
	check(shifted.validation_errors(Vector2i(96,96)).is_empty() and shifted.regions[1].points_m[0] == Vector2(32,48),"road translated points/patches")
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := LakePanel.new(); dock.add_child(panel); await process_frame
	panel.open_influence(plan.regions[1].bounds,plan.regions[1].parameters,"road")
	check(panel._road_grid.visible and not panel._river_grid.visible and panel.parameters() == plan.regions[1].parameters,"road dock fields")
	panel.set_ready("Ready"); panel._road_fields.edge_m.value = 3.0; check(panel.get_apply_button().disabled,"stale road Apply")
	for i in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302 and dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"road dock overflow"); dock.free()
	var folder := "user://ember-tests/road-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path := folder.path_join("terrain.res"); var scene_path := folder.path_join("map.tscn")
	check(ResourceSaver.save(source,terrain_path) == OK,"road fixture save")
	var scene := Node3D.new(); scene.scene_file_path = scene_path; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48,48)
	map.compact_terrain = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene; map.set_meta(Plan.META,plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene; var history := UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene); return ResourceSaver.save(packed,scene_path) if error == OK else error)
	editor.sessions.recovery_directory = folder.path_join("recovery")
	var draft := editor.sessions.open_map(map,scene)
	var context := {"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"road commit")
	history.undo(); check(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty(),"road atomic Undo")
	history.redo(); check(draft.resource == first.candidate and Plan.same(Plan.read(map),first.output_plan),"road Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale road commit")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened := (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan) and reopened.get_node("Map").compact_terrain.same_terrain_data(first.candidate),"road fresh Save/Reopen"); reopened.free()
	check(editor.commit_terrain_plan(map,moved).is_empty(),"move road recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":move.candidate,"output_plan":move.output_plan,"plan_version":moved.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"move road commit")
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	check(draft.resource.same_terrain_data(first.candidate),"road Discard")
	check(editor.sessions.restore_recovery(scene) == 1 and draft.resource.same_terrain_data(move.candidate) and Plan.same(Plan.read(map),move.output_plan),"road recovery")
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("ROAD_PLAN ","PASS" if errors.is_empty() else errors," cpu_ms=",first.elapsed_us/1000.0," repeat_ms=",repeat.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," tiles=",first.changed_tiles.size())
	quit(0 if errors.is_empty() else 1)
