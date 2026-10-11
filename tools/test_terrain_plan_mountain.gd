extends "res://tools/test_terrain_plan_river.gd"
func mountain_plan() -> Resource:
	var plan := Plan.new(); plan.schema_version = Plan.VERSION
	plan.regions = [{"id":"mountain","name":"Гора","kind":"mountain","enabled":true,"bounds":Rect2i(12,12,24,24),"parameters":{"height_m":12.0,"summit_m":4.0,"slope_m":10.0}}]
	return plan
func _run() -> void:
	var source := fixture(); var plan := mountain_plan(); var first := compose(source,plan)
	if first.candidate == null: quit(1); return
	var center := Vector2i(384,384); var index: int = source.column_index(center.x,center.y)
	check(first.candidate.column_value("heights",index) == 192,"mountain peak")
	for point in [Vector2i(360,384),Vector2i(400,384),Vector2i(384,360),Vector2i(384,400)]:
		check(first.candidate.column_value("heights",source.column_index(point.x,point.y)) == 192,"summit not flat")
	check(first.candidate.column_value("heights",source.column_index(18*16,24*16)) > 96 and first.candidate.column_value("heights",source.column_index(18*16,24*16)) < 192,"slope not gradual")
	check(first.candidate.column_value("heights",source.column_index(12*16,24*16)) == 96,"foot seam")
	check(first.candidate.column_value("heights",source.column_index(44*16,24*16)) == 96 and source.column_value("heights",index) == 96 and plan.patches.is_empty(),"outside/source mutation")
	for key in source.sections:
		for field in ["top_materials","base_materials","cap_depths","water_levels","water_materials","water_flow","column_material_overrides"]:
			check(first.candidate.sections[key].get(field) == source.sections[key].get(field),"mountain changed "+field)
	var repeat := compose(first.candidate,first.output_plan,1300)
	check(repeat.candidate != null and repeat.candidate.same_terrain_data(first.candidate) and Plan.same(repeat.output_plan,first.output_plan),"mountain repeat accumulation")
	check(compose(source,plan,50000).candidate.same_terrain_data(first.candidate),"mountain work budget changes shape")
	var moved: Resource = first.output_plan.working_copy(); moved.regions[0].bounds = Rect2i(28,28,16,16); moved.regions[0].parameters.slope_m = 6.0
	var move := compose(first.candidate,moved)
	check(move.candidate != null and move.candidate.column_value("heights",index) == 96,"old mountain footprint not restored")
	var off: Resource = move.output_plan.working_copy(); off.regions[0].enabled = false
	check(compose(move.candidate,off).candidate.same_terrain_geometry(source,true),"mountain off did not restore original geometry")
	var deleted: Resource = first.output_plan.working_copy(); deleted.regions.clear()
	check(compose(first.candidate,deleted).candidate.same_terrain_geometry(source,true),"mountain delete did not restore original geometry")
	for channel in ["heights","top_materials","water_levels","side","flow"]:
		var manual: Resource = first.candidate.working_copy(); var part: Resource = manual.sections[Vector2i(1,1)].working_copy()
		if channel == "side": part.column_material_overrides[0] = {0:1}
		elif channel == "flow": part.water_flow.resize(24*24); part.water_flow[0] = Vector2(0.1,0.2)
		else:
			var values: Variant = part.get(channel); values[0] = values[0]-4 if channel == "heights" else 4 if channel == "water_levels" else 1; part.set(channel,values)
		manual.sections[Vector2i(1,1)] = part
		var keep := compose(manual,moved)
		if keep.candidate == null: quit(1); return
		check(keep.protected_blocks.has(center/16),"mountain protection missing "+channel)
		check(keep.candidate.column_value("heights",index) == manual.column_value("heights",index) and keep.candidate.flow_at_cell(center.x,center.y) == manual.flow_at_cell(center.x,center.y),"manual state erased "+channel)
	var lower: Resource = plan.working_copy(); lower.regions[0].parameters.height_m = 4.0
	check(compose(source,lower).candidate.same_terrain_data(source),"lower peak cut original land")
	var ellipse := Rect2i(8,8,16,32); var values := Plan.Influence.mountain_defaults(ellipse)
	check(is_equal_approx(Plan.Influence.mountain_weight(ellipse,Vector2(20,24),values),Plan.Influence.mountain_weight(ellipse,Vector2(16,32),values)),"elongated mountain axes")
	values = Plan.Influence.mountain_defaults(Rect2i(0,0,9,9))
	check(Plan.Influence.mountain_bounds_error(Rect2i(0,0,9,9),values).is_empty() and fmod(values.slope_m,0.25) == 0,"selection defaults do not fit spin grid")
	var invalid: Resource = plan.working_copy(); invalid.regions[0].parameters.height_m = NAN
	check(not invalid.validation_errors().is_empty(),"NaN peak accepted")
	invalid = plan.working_copy(); invalid.regions[0].parameters.slope_m = 16.0
	check(not invalid.validation_errors().is_empty(),"oversize slopes accepted")
	invalid = plan.working_copy(); invalid.regions[0].bounds = Rect2i(0,0,4,4)
	check(not invalid.validation_errors().is_empty(),"tiny mountain accepted")
	invalid = plan.working_copy(); invalid.regions[0].bounds = Rect2i(8,0,24,24)
	reject(source,invalid,"wet mountain accepted")
	var overlapped: Resource = plan.working_copy()
	overlapped.regions.insert(0,{"id":"plateau","name":"Плато","kind":"plateau","enabled":true,"bounds":Rect2i(12,12,24,24),"parameters":{"height_m":8.0,"transition_m":4.0}})
	check(compose(source,overlapped).candidate.column_value("heights",index) == 192,"mountain/plateau order")
	# A v4 river contains original flow different from expected flow. Adding a
	# v5 mountain must retain that original state; copying expected would leak it.
	var river := compose(source,river_plan())
	var v4: Resource = river.output_plan.working_copy(); v4.schema_version = 4
	var read_v4: Resource = Plan.from_data(v4.data()); check(read_v4 != null,"v4 read")
	var upgraded: Resource = read_v4.working_copy(); upgraded.upgrade_local_layers()
	check(upgraded.patches == read_v4.patches and read_v4.schema_version == 4,"v4 upgrade changed original flow provenance")
	upgraded.regions.append({"id":"hill","name":"Возвышенность","kind":"mountain","enabled":true,"bounds":Rect2i(36,28,8,8),"parameters":Plan.Influence.mountain_defaults(Rect2i(36,28,8,8))})
	var joint := compose(river.candidate,upgraded)
	check(joint.candidate != null and joint.candidate.flow_at_cell(400,208) == river.candidate.flow_at_cell(400,208),"new mountain changed existing river")
	var restored: Resource = joint.output_plan.working_copy(); restored.regions.clear()
	check(compose(joint.candidate,restored).candidate.same_terrain_geometry(source,true),"v4 original flow lost after adding mountain")
	var shifted: Resource = first.output_plan.translated(Vector2i(24,24)); check(shifted.validation_errors(Vector2i(96,96)).is_empty(),"mountain translation")
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := LakePanel.new(); dock.add_child(panel); await process_frame
	panel.open_influence(plan.regions[0].bounds,plan.regions[0].parameters,"mountain")
	check(panel._mountain_grid.visible and not panel._river_grid.visible and panel.parameters() == plan.regions[0].parameters,"mountain dock fields")
	panel.set_ready("Ready"); panel._mountain_fields.height_m.value = 12.25; check(panel.get_apply_button().disabled,"stale mountain Apply")
	for i in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302 and dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"mountain dock overflow"); dock.free()
	var folder := "user://ember-tests/mountain-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path := folder.path_join("terrain.res"); var scene_path := folder.path_join("map.tscn")
	check(ResourceSaver.save(source,terrain_path) == OK,"mountain fixture save")
	var scene := Node3D.new(); scene.scene_file_path = scene_path; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48,48)
	map.compact_terrain = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene; map.set_meta(Plan.META,plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene; var history := UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene); return ResourceSaver.save(packed,scene_path) if error == OK else error)
	editor.sessions.recovery_directory = folder.path_join("recovery")
	var draft := editor.sessions.open_map(map,scene)
	var context := {"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"mountain commit")
	history.undo(); check(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty(),"mountain atomic Undo")
	history.redo(); check(draft.resource == first.candidate and Plan.same(Plan.read(map),first.output_plan),"mountain Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale mountain Apply")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened := (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan) and reopened.get_node("Map").compact_terrain.same_terrain_data(first.candidate),"mountain fresh Save/Reopen"); reopened.free()
	check(editor.commit_terrain_plan(map,moved).is_empty(),"move recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":move.candidate,"output_plan":move.output_plan,"plan_version":moved.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"move mountain commit")
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	check(draft.resource.same_terrain_data(first.candidate),"mountain Discard")
	check(editor.sessions.restore_recovery(scene) == 1 and draft.resource.same_terrain_data(move.candidate) and Plan.same(Plan.read(map),move.output_plan),"mountain recovery")
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("MOUNTAIN_PLAN ","PASS" if errors.is_empty() else errors," cpu_ms=",first.elapsed_us/1000.0," repeat_ms=",repeat.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," tiles=",first.changed_tiles.size())
	quit(0 if errors.is_empty() else 1)
