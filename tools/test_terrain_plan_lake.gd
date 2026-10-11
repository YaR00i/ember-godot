extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Job = preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const LakePanel = preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
var errors: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func compose(source: Resource,plan: Resource,budget := 4000) -> RefCounted:
	var job := Job.new()
	if not job.begin(source,plan): check(false,job.error); return job
	for i in 20000:
		job.step(budget)
		if not job.error.is_empty() or job.finished: break
	check(job.finished and job.candidate != null,job.error)
	if job.candidate != null:
		check(job.candidate.validation_errors().is_empty(),"candidate validation")
		check(job.output_plan.validation_errors().is_empty(),"provenance validation")
	return job
func fixture() -> Resource:
	var creation := Creation.new(); check(creation.prepare_sections("lake_fixture",2,2,96),creation.error)
	var source: Resource = creation.source.sectioned_copy()
	# Sea at 2 m, dry land at 6 m. Both are the same existing terrain source.
	for key in source.sections:
		if key.y != 0: continue
		var part: Resource = source.sections[key].working_copy()
		for z in 6*16:
			for x in part.width:
				var i: int = x+z*part.width
				part.heights[i] = 16; part.cap_depths[i] = 3
				part.water_levels[i] = 32; part.water_materials[i] = 5
		source.sections[key] = part
	return source
func lake_plan() -> Resource:
	var plan := Plan.new(); plan.schema_version = Plan.VERSION
	plan.regions = [{"id":"lake","name":"Верхнее озеро","kind":"lake","enabled":true,
		"bounds":Rect2i(12,12,24,24),"parameters":{"water_m":5.0,"depth_m":2.0,"shore_m":3.0}}]
	return plan
func _run() -> void:
	var source := fixture(); var plan := lake_plan(); var first := compose(source,plan)
	if first.candidate == null: quit(1); return
	var center: int = source.column_index(24*16,24*16)
	check(first.candidate.column_value("heights",center) == 48 and first.candidate.column_value("water_levels",center) == 80,"lake level/depth")
	check(source.column_value("heights",center) == 96 and plan.patches.is_empty(),"source mutation")
	check(first.candidate.column_value("water_levels",source.column_index(2*16,2*16)) == 32,"sea level changed")
	check(first.candidate.column_value("heights",source.column_index(40*16,40*16)) == 96,"outside land changed")
	var repeat := compose(first.candidate,first.output_plan,1300)
	check(repeat.candidate != null and repeat.candidate.same_terrain_data(first.candidate) and Plan.same(repeat.output_plan,first.output_plan),"repeat accumulation")
	var fast := compose(source,plan,50000)
	check(fast.candidate != null and fast.candidate.same_terrain_data(first.candidate),"work budget changed result")
	var moved: Resource = first.output_plan.working_copy(); moved.regions[0].bounds = Rect2i(30,30,12,12)
	var move := compose(first.candidate,moved)
	if move.candidate == null: quit(1); return
	check(move.candidate.column_value("heights",center) == 96 and move.candidate.column_value("water_levels",center) == 0,"old water/ground not restored")
	var off: Resource = move.output_plan.working_copy(); off.regions[0].enabled = false
	var disabled := compose(move.candidate,off)
	check(disabled.candidate != null and disabled.candidate.same_terrain_data(source),"disable did not restore all terrain channels")
	var changed: Resource = first.output_plan.working_copy(); changed.regions[0].parameters.water_m = 6.0
	var raised := compose(first.candidate,changed)
	check(raised.candidate != null and raised.candidate.column_value("water_levels",center) == 96,"lake level parameter")
	changed = plan.working_copy(); changed.regions[0].parameters.water_m = 8.0
	var above_land := compose(source,changed)
	if above_land.candidate == null: quit(1); return
	for x in range(12*16,36*16,8):
		var point := Vector2(float(x+4)/16.0,24.25)
		var distance: float = Plan.Influence.lake_distance(plan.regions[0].bounds,point)
		var index: int = source.column_index(x,24*16)
		if distance < 3.0: check(above_land.candidate.column_value("water_levels",index) <= above_land.candidate.column_value("heights",index),"outer bank flooded above original land")
		if absf(distance-3.0) < 0.5: check(above_land.candidate.column_value("heights",index) >= 8*16,"raised closed bank below lake")
	for channel in ["heights","water_levels","water_materials","top_materials","side","flow"]:
		var manual: Resource = first.candidate.working_copy(); var part: Resource = manual.sections[Vector2i(1,1)].working_copy()
		var index := 0 # Centre lies at the start of section (1,1).
		if channel == "side": part.column_material_overrides[index] = {0:1}
		elif channel == "flow":
			part.water_flow.resize((part.width/16)*(part.depth/16)); part.water_flow[0] = Vector2(0.5,0)
		else:
			var values: Variant = part.get(channel); values[index] = values[index]+4 if channel in ["heights","water_levels"] else 1; part.set(channel,values)
		manual.sections[Vector2i(1,1)] = part
		var protected_result := compose(manual,moved)
		if protected_result.candidate == null: quit(1); return
		check(protected_result.protected_blocks.has(Vector2i(24,24)),"manual protection missing "+channel)
		check(protected_result.candidate.column_value("heights",center) == manual.column_value("heights",center) and protected_result.candidate.column_value("water_levels",center) == manual.column_value("water_levels",center),"manual water/ground erased "+channel)
		check(protected_result.candidate.flow_at_cell(24*16,24*16) == manual.flow_at_cell(24*16,24*16),"manual flow erased")
	var invalid: Resource = plan.working_copy(); invalid.regions[0].parameters.depth_m = NAN
	check(not invalid.validation_errors().is_empty(),"NaN accepted")
	invalid = plan.working_copy(); invalid.regions[0].parameters.depth_m = 6.0
	check(not invalid.validation_errors().is_empty(),"bed below map accepted")
	invalid = plan.working_copy(); invalid.regions[0].bounds = Rect2i(0,0,4,4)
	check(not invalid.validation_errors().is_empty(),"tiny lake accepted")
	invalid = plan.working_copy(); invalid.regions[0].bounds = Rect2i(0,0,16,16)
	var rejected := Job.new(); check(rejected.begin(source,invalid),rejected.error)
	for i in 10000:
		rejected.step()
		if rejected.finished or not rejected.error.is_empty(): break
	check(not rejected.error.is_empty() and rejected.candidate == null,"existing water overwritten")
	var legacy := Plan.new(); legacy.schema_version = 2
	legacy.regions = [{"id":"p","name":"Старое плато","kind":"plateau","enabled":true,"bounds":Rect2i(10,10,8,8),"parameters":{"height_m":7.0,"transition_m":2.0}}]
	var plateau := compose(source,legacy)
	if plateau.candidate == null: quit(1); return
	var old_data: Dictionary = plateau.output_plan.data(); old_data.version = 2
	for patch in old_data.patches:
		for key in Plan.V3_CHANNELS: patch.erase(key)
		patch.erase("before_sides"); patch.erase("flows")
	var old_plan: Resource = Plan.from_data(old_data); check(old_plan != null,"v2 read")
	var upgraded: Resource = old_plan.working_copy(); upgraded.upgrade_local_layers()
	check(upgraded.validation_errors().is_empty() and old_plan.schema_version == 2,"v2 explicit upgrade")
	check(compose(plateau.candidate,old_plan).candidate.same_terrain_data(plateau.candidate),"v2 replay changed terrain")
	var translated: Resource = first.output_plan.translated(Vector2i(24,0))
	check(translated.validation_errors(Vector2i(96,48)).is_empty(),"translated lake provenance invalid")
	var corrupt: Resource = first.output_plan.working_copy()
	for patch in corrupt.patches:
		if patch.rect.has_point(Vector2i(384,384)): patch.before_waters[0] = -1
	var corrupt_job := Job.new(); check(corrupt_job.begin(first.candidate,corrupt),corrupt_job.error)
	for i in 10000:
		corrupt_job.step()
		if corrupt_job.finished or not corrupt_job.error.is_empty(): break
	check(not corrupt_job.error.is_empty() and corrupt_job.candidate == null,"corrupt water provenance accepted")
	corrupt = first.output_plan.working_copy(); corrupt.patches[0].before_sides[0] = "invalid"
	check(not corrupt.validation_errors().is_empty(),"corrupt side provenance accepted")
	# New parameters share the existing dock; actions stay pinned.
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := LakePanel.new(); dock.add_child(panel); await process_frame
	panel.open_influence(plan.regions[0].bounds,plan.regions[0].parameters,"lake")
	check(panel._lake_grid.visible and not panel._plateau_grid.visible and panel.parameters() == plan.regions[0].parameters,"lake fields/recipe")
	panel.set_ready("Ready"); panel._lake_fields.depth_m.value = 2.5
	check(panel.get_apply_button().disabled,"lake edit retained stale Apply")
	panel._scroll.scroll_vertical = 10000; for i in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302 and dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"lake dock overflow")
	dock.free()
	# Terrain + plan + local water provenance use one existing history and Save.
	var folder := "user://ember-tests/lake-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path := folder.path_join("terrain.res"); var scene_path := folder.path_join("map.tscn")
	check(ResourceSaver.save(source,terrain_path) == OK,"fixture save")
	var scene := Node3D.new(); scene.scene_file_path = scene_path; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48,48)
	map.compact_terrain = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene; map.set_meta(Plan.META,plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene; var history := UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene); return ResourceSaver.save(packed,scene_path) if error == OK else error)
	editor.sessions.recovery_directory = folder.path_join("recovery")
	var draft := editor.sessions.open_map(map,scene)
	var context := {"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"lake commit")
	history.undo(); check(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty(),"atomic lake Undo")
	history.redo(); check(draft.resource == first.candidate and Plan.same(Plan.read(map),first.output_plan),"atomic lake Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale lake Apply")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened := (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan),"lake plan Save/Reopen")
	check(compose(reopened.get_node("Map").compact_terrain,Plan.read(reopened.get_node("Map"))).candidate.same_terrain_data(first.candidate),"reopen lake replay")
	reopened.free(); check(editor.commit_terrain_plan(map,moved).is_empty(),"move recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":move.candidate,"output_plan":move.output_plan,"plan_version":moved.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"move commit")
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	check(draft.resource.same_terrain_data(first.candidate),"lake Discard")
	check(editor.sessions.restore_recovery(scene) == 1 and draft.resource.same_terrain_data(move.candidate),"lake recovery")
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("LAKE_METRICS calc_ms=",first.elapsed_us/1000.0," repeat_ms=",repeat.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," repeat_step_ms=",repeat.worst_step_us/1000.0," tiles=",first.changed_tiles.size())
	print("TERRAIN_PLAN_LAKE ","PASS" if errors.is_empty() else "FAIL"," level/depth/closed-bank/sea/immutable/repeat/move/off/manual/v2/UI/Undo/Save/Reopen/Discard/recovery errors=",errors)
	quit(0 if errors.is_empty() else 1)
