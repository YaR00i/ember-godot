extends "res://tools/test_terrain_plan_grove.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_catalog={"vox_fixture_tree_a":make_tree("vox_fixture_tree_a",Color.GREEN),"vox_fixture_tree_b":make_tree("vox_fixture_tree_b",Color.DARK_GREEN)}
	var source:=fixture()
	_scene=Node3D.new();root.add_child(_scene)
	_map=EmberMapLoader.new();_map.name="Map";_scene.add_child(_map);_map.owner=_scene
	var props:=Node3D.new();props.name="Props";_map.add_child(props);props.owner=_scene
	var input:=plan();_map.set_meta(Plan.META,input)
	var manual:=(_catalog.vox_fixture_tree_a as PackedScene).instantiate() as EmberVoxelProp
	manual.name="manual";manual.placement_id="manual";manual.position=Vector3(-100,0,-100)
	EmberSceneAuthoring.attach_model_instance(_scene,props,manual)
	var before:=Grove.pose_version(_map)
	test_editor_cancel(source,input)
	var job:=prepare(source,input)
	var synchronous:Dictionary=job.finalize(props)
	var expected:Dictionary=synchronous.plan.data()
	for prop in synchronous.added:prop.free()
	job=prepare(source,input)
	job.begin_publication(props);job.step_publication(4000)
	check(not job.publication_finished() and job.publication_progress().x<=4,"publication yields after a bounded batch")
	check(Grove.pose_version(_map)==before,"partial population excluded from authoring snapshot")
	var packed:=PackedScene.new();check(packed.pack(_scene)==OK,"pack partial scene")
	var partial:=packed.instantiate()
	check(partial.get_node("Map/Props").get_child_count()==1,"native packing excludes every partial instance")
	partial.free()
	check(not job.stale(),"own unowned preview does not invalidate input")
	manual.position.x+=1;check(job.stale(),"manual edit still invalidates input");manual.position.x-=1
	job.cancel()
	check(props.get_child_count()==1 and Grove.pose_version(_map)==before,"cancel removes all partial instances")
	job=prepare(source,input);job.begin_publication(props)
	var ticks:=0
	while not job.publication_finished() and job.error.is_empty() and ticks<1000:
		job.step_publication(4000);ticks+=1;await process_frame
	check(job.publication_finished() and job.error.is_empty(),"publication completes: "+job.error)
	check(not job.stale(),"completed staged population still validates")
	check(job.output_plan.data()==expected,"bounded publication matches synchronous provenance")
	var delta:Dictionary=job.take_publication()
	var history:=UndoRedo.new();history.create_action("Publish grove")
	history.add_do_method(Grove.apply_delta.bind(delta,true));history.add_undo_method(Grove.apply_delta.bind(delta,false))
	for prop in delta.added:history.add_do_reference(prop)
	for prop in delta.removed:history.add_undo_reference(prop)
	history.commit_action();_map.set_meta(Plan.META,delta.plan)
	var after:=Grove.pose_version(_map)
	check(after.size()==before.size()+job.placements.size(),"one action owns the complete population")
	history.undo();check(Grove.pose_version(_map)==before,"one Undo restores original manual population")
	history.redo();check(Grove.pose_version(_map)==after,"one Redo restores complete population")
	check(delta.plan.validation_errors(Vector2i(source.width/16,source.depth/16)).is_empty(),"output validates")
	check(packed.pack(_scene)==OK,"pack completed scene")
	var path:=ROOT.path_join("publication.tscn")
	check(ResourceSaver.save(packed,path)==OK,"save completed population")
	var reopened:Node=(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate();root.add_child(reopened)
	check(reopened.get_node("Map/Props").get_child_count()==props.get_child_count(),"reopen retains complete population")
	var snapshot:PackedScene=Grove.snapshot(_map)
	var pose:Transform3D=delta.added[0].transform;delta.added[0].position.x+=1
	check(Grove.restore_snapshot(_map,_scene,snapshot).is_empty() and delta.added[0].transform==pose,"Discard restores saved member")
	reopened.free();history.clear_history();history.free();_scene.free();await process_frame
	print("GROVE_PUBLICATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"ticks":ticks}))
	quit(0 if errors.is_empty() else 1)

func test_editor_cancel(source:Resource,input:Resource)->void:
	var editor:=Editor.new();root.add_child(editor);editor.scene=_scene
	var panel:=LakePanel.new();root.add_child(panel);editor._generation_panel=panel
	var history:=UndoRedo.new();editor.sessions.configure(history)
	var draft:Dictionary={"target":weakref(_map),"scene":weakref(_scene),"resource":source,"compact":true,"preview":null}
	editor.sessions.entries[_map.get_instance_id()]=draft
	var initial_version:=history.get_version()
	var count:=_map.get_node("Props").get_child_count()
	for mode in ["undo","clear","stale"]:
		var context:Dictionary={"target":weakref(_map),"grove":true,"grove_prepared":prepare(source,input),"draft":draft,"plan_version":input.data(),"version":source.working_copy(),"layout":Sessions.compact_layout(_map).positions}
		editor._generation_context=context
		editor._submit_grove();editor._process_terrain_generation()
		check(editor._generation_job!=null,"real editor starts bounded publication")
		if mode=="undo":
			var event:=InputEventKey.new();event.keycode=KEY_Z;event.ctrl_pressed=true;event.pressed=true
			editor._input(event)
		elif mode=="clear":editor.clear_terrain_generation_preview()
		else:
			var manual:=_map.get_node("Props/manual") as Node3D;manual.position.x+=1
			var ticks:=0
			while editor._generation_job!=null and ticks<1000:editor._process_terrain_generation();ticks+=1
			check(manual.position.x==-99,"stale cancellation preserves the intervening manual edit")
			manual.position.x-=1
		check(editor._generation_job==null and _map.get_node("Props").get_child_count()==count,"editor cancellation rolls back the whole partial batch: "+mode)
		check(history.get_version()==initial_version and Plan.same(Plan.read(_map),input),"cancel leaves history/plan unchanged: "+mode)
	editor.sessions.entries.clear();editor.free();panel.free();history.free()
