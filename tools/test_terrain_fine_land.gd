extends "res://tools/test_terrain_generation_split.gd"
const Composition=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Editor=preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions=preload("res://addons/ember_import/ember_world_edit_sessions.gd")
func compose(source,plan,budget:=4000):
	var job:=Composition.new();check(job.begin(source,plan),job.error)
	while job.candidate!=null and not job.finished and job.error.is_empty():job.step(budget)
	check(job.error.is_empty(),job.error);return job
func run() -> void:
	var source:=Fixture.base();var original:=source.working_copy()
	var params:=Math.DEFAULTS.duplicate(true);params.terrain_operation="generate"
	var legacy=build(source,params)
	var explicit:=params.duplicate(true);explicit.terrain_sampling="legacy8"
	check(build(source,explicit).candidate.same_terrain_data(legacy.candidate),"legacy opt-in exact")
	params.terrain_sampling="fine16"
	var fine=build(source,params);var sampler:=Math.new();sampler.configure(Rect2(0,0,8,8),params)
	var detail_count:=0
	for z in 128:
		for x in 128:
			var expected:=clampi(roundi(sampler.height_m(Vector2(x+.5,z+.5)/16.0)*16),4,fine.candidate.height_limit)
			check(fine.candidate.column_value("heights",x+z*128)==expected,"cell-centre fine sample")
			if expected%4!=0:detail_count+=1
	check(detail_count>1000,"retains sub-quarter heights")
	for c in ["top_materials","base_materials"]:check(same_channel(source,fine.candidate,c),"fine preserves paint "+c)
	check(build(source,params,Rect2i(0,0,8,8),700).candidate.same_terrain_data(fine.candidate),"fine budget deterministic")
	var edge=build(source,params,Rect2i(1,1,6,6))
	for z in 128:
		for x in 128:
			if x<=16 or x>=111 or z<=16 or z>=111:check(edge.candidate.column_value("heights",x+z*128)==source.heights[x+z*128],"selection outside and boundary exact")
	var cancelled:=Generation.new();cancelled.begin(source,Rect2i(0,0,8,8),params);cancelled.step(500);cancelled.cancel()
	check(cancelled.candidate==null and source.same_terrain_data(original),"cancel/source immutable")
	var base:=source.working_copy();base.heights.fill(24);base.water_levels.fill(0);base.water_materials.fill(0)
	var plan:=Plan.new();plan.schema_version=11
	plan.regions=[{"id":"mountain","name":"Массив","kind":"mountain","enabled":true,"bounds":Rect2i(0,0,8,8),"parameters":{"height_m":4.0,"summit_m":1.0,"slope_m":3.5,"terrain_sampling":"fine16","mountain_shape":"massif","shape_seed":7}}]
	var first=compose(base,plan)
	check(first.candidate!=null,"massif generated")
	if first.candidate==null:quit(1);return
	var repeated=compose(first.candidate,first.output_plan,700)
	check(repeated.candidate.same_terrain_data(first.candidate),"massif recomposition no accumulation")
	var off=first.output_plan.working_copy();off.regions[0].enabled=false
	check(compose(first.candidate,off).candidate.same_terrain_geometry(base.sectioned_copy(),true),"off restores original")
	for c in ["top_materials","base_materials","water_levels","water_materials"]:check(same_channel(base,first.candidate,c),"massif preserves "+c)
	var shape: Dictionary=plan.regions[0].parameters
	check(absf(Plan.Influence.mountain_weight(Rect2i(0,0,8,8),Vector2(2,4),shape)-Plan.Influence.mountain_weight(Rect2i(0,0,8,8),Vector2(6,4),shape))>0.01,"asymmetric large slopes")
	for z in 128:
		check(first.candidate.column_value("heights",z*128)==24 and first.candidate.column_value("heights",127+z*128)==24,"compact foot exact boundary")
	var mixed:=plan.working_copy();mixed.regions.insert(0,{"id":"old","name":"Старое плато","kind":"plateau","enabled":true,"bounds":Rect2i(0,0,8,8),"parameters":{"height_m":2.0,"transition_m":1.0}})
	var old_only: Resource=mixed.working_copy();old_only.regions.pop_back()
	var old_result=compose(base,old_only)
	var combined=compose(base,mixed)
	for z in 128:
		for x in 128:
			var initial: int=old_result.candidate.column_value("heights",x+z*128)
			var weight:=Plan.Influence.mountain_weight(Rect2i(0,0,8,8),Vector2(x+.5,z+.5)/16.0,shape)
			check(combined.candidate.column_value("heights",x+z*128)==maxi(initial,roundi(lerpf(initial,64,weight))),"mixed old/new layers retain independent sampling")
	var restored=Plan.from_data(first.output_plan.data());check(restored!=null and Plan.same(restored,first.output_plan),"v11 roundtrip")
	var v10:=plan.working_copy();v10.schema_version=10;check(not v10.validation_errors().is_empty(),"v10 rejects new recipe")
	var panel:=Dialog.new();root.add_child(panel);await process_frame
	panel.open_for(Rect2i(0,0,8,8));check(panel.parameters().terrain_sampling=="fine16","new UI fine default")
	panel.open_plan(Rect2i(0,0,8,8),Math.DEFAULTS);check(not panel.parameters().has("terrain_sampling"),"old UI keeps legacy recipe")
	panel.open_influence(Rect2i(0,0,8,8),shape,"mountain");check(panel.parameters()==shape,"massif UI roundtrip")
	panel.set_ready("Ready");panel._shape_seed.value=8;check(panel.get_apply_button().disabled,"shape change invalidates preview")
	panel.queue_free()
	var path:="user://fine-land-test.res";check(ResourceSaver.save(first.candidate,path)==OK,"save fine source")
	check(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).same_terrain_data(first.candidate),"fresh source reopen")
	var folder:="user://fine-authoring-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path:=folder+"/terrain.res";var scene_path:=folder+"/map.tscn"
	check(ResourceSaver.save(base,terrain_path)==OK,"save authoring fixture")
	var scene:=Node3D.new();scene.scene_file_path=scene_path;root.add_child(scene)
	var map:=EmberMapLoader.new();map.name="Map";map.hydrate_legacy_regions=false;map.authored_size_blocks=Vector2i(8,8)
	map.compact_terrain=ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE);scene.add_child(map);map.owner=scene;map.set_meta(Plan.META,plan)
	var editor:=Editor.new();root.add_child(editor);editor.scene=scene;var history:=UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed:=PackedScene.new();var code:=packed.pack(scene);return ResourceSaver.save(packed,scene_path) if code==OK else code)
	editor.sessions.recovery_directory=folder+"/recovery"
	var draft:=editor.sessions.open_map(map,scene)
	var old_plan:=plan.working_copy();old_plan.schema_version=10
	for key in ["terrain_sampling","mountain_shape","shape_seed"]:old_plan.regions[0].parameters.erase(key)
	map.set_meta(Plan.META,old_plan)
	var preview_panel:=Dialog.new();root.add_child(preview_panel);await process_frame
	editor._generation_panel=preview_panel
	editor._generation_context={"target":weakref(map),"area":Rect2i(0,0,8,8),"plan_id":"mountain","plan_version":old_plan.data(),"composition":true}
	editor._prepare_terrain_generation(shape)
	check(editor._generation_job!=null,"old-plan direct fine preview upgrades private recipe")
	check(Plan.read(map).schema_version==10,"preview does not mutate old plan")
	editor.clear_terrain_generation_preview();editor._generation_panel=null;preview_panel.queue_free();map.set_meta(Plan.META,plan)
	var context:={"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"fine Apply")
	history.undo();check(draft.resource.same_terrain_data(base) and Plan.read(map).patches.is_empty(),"fine atomic Undo")
	history.redo();check(draft.resource==first.candidate and Plan.same(Plan.read(map),first.output_plan),"fine Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale fine Apply")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened=ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan) and reopened.get_node("Map").compact_terrain.same_terrain_data(first.candidate),"fine authoring Save/Reopen")
	reopened.free();history.clear_history();editor.sessions.release();editor.free();history.free();scene.free()
	print("FINE_LAND ","PASS" if errors.is_empty() else errors," fine_heights=",detail_count)
	quit(0 if errors.is_empty() else 1)
