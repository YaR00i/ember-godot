extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Editor=preload("res://addons/ember_import/ember_world_editor.gd")
const Composition=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("COAST_WORKFLOW_FAIL ",label)
func _initialize()->void:run.call_deferred()
func mouse(position:Vector2,pressed:bool)->InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.position=position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;return e
func run()->void:
	var dir:="user://ember-tests/coast-workflow-"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var source=Fixture.base();source.origin_y=-32
	var plan:=Plan.new();plan.upgrade_local_layers()
	var points:=PackedVector2Array([Vector2(5,1),Vector2(4.5,4),Vector2(5,7)])
	var params:Dictionary={"water_m":0.0,"depth_m":0.75,"shore_m":1.0,"terrain_sampling":"fine16"}
	plan.regions=[{"id":"sea","name":"Берег","kind":"coast","enabled":true,"bounds":Plan.Influence.coast_bounds(points,params,Vector2i(8,8)),"parameters":params,"points_m":points}]
	var job:=Composition.new();check(job.begin(source,plan),"initial sea: "+job.error)
	while not job.finished and job.error.is_empty():job.step(4000)
	if job.candidate==null:quit(1);return
	source=job.candidate;plan=job.output_plan
	var vp:=SubViewport.new();vp.size=Vector2i(600,600);root.add_child(vp)
	var frame:=Node3D.new();vp.add_child(frame);frame.scene_file_path=dir.path_join("map.tscn")
	var map:=EmberMapLoader.new();map.name="Map";frame.add_child(map);map.owner=frame
	ResourceSaver.save(source,dir.path_join("terrain.res"));map.compact_terrain=ResourceLoader.load(dir.path_join("terrain.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	map.authored_size_blocks=Vector2i(8,8);map.world_look=2;map.compact_ground_style=1;map.set_meta(Plan.META,plan)
	var camera:=Camera3D.new();frame.add_child(camera);camera.size=160;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.look_at_from_position(Vector3(64,180,170),Vector3(64,0,64));camera.make_current()
	var deadline:=Time.get_ticks_msec()+20000
	while (map._visual_surface_projection.pending_tile_count()>0 or not map._visual_surface_projection._look_pending.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	var history:=UndoRedo.new();var world:=Editor.new();root.add_child(world);world.scene=frame;world.map=map;world.camera=camera
	var fault:={"fail":false}
	world.sessions.configure(history,func()->int:
		if fault.fail:return ERR_CANT_CREATE
		var packed:=PackedScene.new();var code:=packed.pack(frame)
		return ResourceSaver.save(packed,frame.scene_file_path) if code==OK else code)
	world.sessions.recovery_directory=dir.path_join("recovery")
	world.entry=world.sessions.open_map(map,frame)
	world._plan_target=weakref(map);world._plan_selected_id="sea"
	world._terrain_workspace=VBoxContainer.new();root.add_child(world._terrain_workspace)
	world._plan_panel=load("res://addons/ember_import/ember_terrain_plan_dialog.gd").new();world._terrain_workspace.add_child(world._plan_panel);world._plan_panel.show_plan(plan,"sea")
	var baseline:Resource=world.entry.resource.working_copy()
	var revision:int=map._visual_surface_projection.column_revision()
	var start:Vector2=world._plan_point_pixel(points[1]);var end:=start+Vector2(15,5)
	var field:=LineEdit.new();root.add_child(field);field.grab_focus()
	check(root.gui_get_focus_owner()==field,"parameter field has keyboard focus")
	world.active=true
	world.forward_input(camera,mouse(start,true))
	check(not world._plan_drag.is_empty() and root.gui_get_focus_owner()!=field,"viewport click starts drag after editing a field")
	field.free()
	var count:=history.get_history_count()
	for i in 20:
		var e:=InputEventMouseMotion.new();e.position=start.lerp(end,float(i+1)/20);e.button_mask=MOUSE_BUTTON_MASK_LEFT;world.forward_input(camera,e)
	check(history.get_history_count()==count and Plan.same(Plan.read(map),plan),"drag does not write document before release")
	check(map._visual_surface_projection.column_revision()==revision,"drag never rebuilds terrain")
	world.forward_input(camera,mouse(end,false))
	var moved:Resource=Plan.read(map)
	check(history.get_history_count()==count+1 and moved.regions[0].points_m!=points,"release creates one Undo and moves a point")
	check(world.entry.resource.same_terrain_data(baseline),"point editing retains authored terrain")
	history.undo();check(Plan.same(Plan.read(map),plan),"point Undo exact")
	history.redo();check(Plan.same(Plan.read(map),moved),"point Redo exact")
	start=world._plan_point_pixel(moved.regions[0].points_m[1]);world.forward_input(camera,mouse(start,true))
	var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(9,1);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;world.forward_input(camera,motion)
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;world.forward_input(camera,escape)
	check(Plan.same(Plan.read(map),moved) and world._plan_drag.is_empty(),"Esc cancels uncommitted drag")
	var curve:=Plan.Influence.path_curve(moved.regions[0].points_m)
	var on_line:Vector2=curve.sample_baked(curve.get_baked_length()*0.25)
	world._plan_point_mode="insert";world.forward_input(camera,mouse(world._plan_point_pixel(on_line),true))
	check(Plan.read(map).regions[0].points_m.size()==4,"add a point on the line")
	var remove:=InputEventKey.new();remove.keycode=KEY_DELETE;remove.pressed=true;world.forward_input(camera,remove)
	check(Plan.read(map).regions[0].points_m.size()==3,"Delete removes the selected point")
	check(world._plan_region_at(world._plan_point_pixel(Vector2(7,4)))=="sea","click inside the sea selects its area")
	# Save migration and transaction rollback use the production save path.
	var pack:=PackedScene.new();pack.pack(frame);ResourceSaver.save(pack,frame.scene_file_path)
	var original_source_hash:=FileAccess.get_sha256(dir.path_join("terrain.res"))
	check(world.sessions.save_all(frame),"compressed plan save: "+world.sessions.error)
	var path:=Plan.storage_path(frame.scene_file_path,"Map")
	check(FileAccess.file_exists(path) and Plan.read(map).resource_path==path,"scene references its own binary Plan")
	var text:=FileAccess.get_file_as_string(frame.scene_file_path)
	check(text.length()<500*1024 and not "before_caps" in text,"heavy patch arrays no longer inflate the text scene")
	var saved_plan:Resource=Plan.read(map).working_copy()
	var reopened:Node=ResourceLoader.load(frame.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved_plan),"fresh scene reopen preserves every plan channel")
	reopened.free()
	var scene_hash:=FileAccess.get_sha256(frame.scene_file_path);var plan_hash:=FileAccess.get_sha256(path)
	var changed:PackedVector2Array=saved_plan.regions[0].points_m.duplicate();changed[1].x+=0.25
	check(world.commit_plan_points(map,"sea",changed).is_empty(),"change before failed save")
	var draft_plan:Resource=Plan.read(map).working_copy();fault.fail=true
	check(not world.sessions.save_all(frame),"scene save failure is reported")
	check(FileAccess.get_sha256(path)==plan_hash and FileAccess.get_sha256(frame.scene_file_path)==scene_hash,"failed save rolls back plan and scene together")
	check(Plan.same(Plan.read(map),draft_plan),"failed save preserves the author's draft")
	var after_failure:Node=ResourceLoader.load(frame.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(Plan.same(Plan.read(after_failure.get_node("Map")),saved_plan),"reopen after failed save sees the saved Plan")
	after_failure.free()
	# Native Ctrl+S publishes resources before Godot reports its scene result.
	fault.fail=false
	check(world.sessions.save_all(frame,true),"deferred save prepares")
	check(not world.sessions.finish_native_save(ERR_CANT_CREATE),"deferred failure reported")
	check(FileAccess.get_sha256(path)==plan_hash and Plan.same(Plan.read(map),draft_plan),"deferred failure restores file and keeps draft")
	var foreign:=FileAccess.get_file_as_bytes(path);var f:=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(foreign);f.store_8(0);f.close()
	check(not world.sessions.save_all(frame) and world.sessions.error.contains("вне редактора"),"external Plan changes block overwrite")
	f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(foreign);f.close()
	check(world.sessions.save_all(frame),"retry succeeds")
	var saved:Resource=Plan.read(map).working_copy()
	world.commit_plan_points(map,"sea",points);world.sessions.discard(frame)
	check(Plan.same(Plan.read(map),saved),"Discard restores the saved plan")
	check(world.sessions.dirty_count(frame)==0 and world.sessions.needs_plan_storage(frame),"clean Discard still routes inline baseline through native publication")
	check(world.sessions.save_all(frame,true),"native save after Discard prepares compressed Plan")
	var native_code:=ResourceSaver.save(world.sessions.pending_native_save.packed,frame.scene_file_path)
	check(world.sessions.finish_native_save(native_code) and Plan.read(map).resource_path==path,"native save after Discard retains external Plan")
	# Copy/Save As must never write the first scene's external Plan file.
	var first_hash:=FileAccess.get_sha256(path)
	var second:=Node3D.new();root.add_child(second);second.scene_file_path=dir.path_join("copy.tscn")
	var second_map:=EmberMapLoader.new();second_map.name="Map";second.add_child(second_map);second_map.owner=second;second_map.compact_terrain=map.compact_terrain;second_map.authored_size_blocks=Vector2i(8,8);second_map.set_meta(Plan.META,Plan.read(map))
	var session:RefCounted=world.sessions.get_script().new();var second_history:=UndoRedo.new()
	session.configure(second_history,func()->int:
		var packed:=PackedScene.new();var code:=packed.pack(second)
		return ResourceSaver.save(packed,second.scene_file_path) if code==OK else code)
	session.recovery_directory=dir.path_join("copy-recovery");var second_entry:Dictionary=session.open_map(second_map,second)
	var second_plan:Resource=Plan.read(second_map).working_copy();second_plan.regions[0].name="Другая копия";session.set_plan(second_entry,second_plan)
	check(session.save_all(second),"copy saves")
	check(Plan.read(second_map).resource_path!=path and FileAccess.get_sha256(path)==first_hash,"copy owns a different Plan and leaves original bytes unchanged")
	check(FileAccess.get_sha256(dir.path_join("terrain.res"))==original_source_hash,"plan-only workflow never rewrites terrain")
	print("COAST_PLANNER_WORKFLOW ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"scene_bytes":FileAccess.open(frame.scene_file_path,FileAccess.READ).get_length(),"plan_bytes":FileAccess.open(path,FileAccess.READ).get_length()}))
	history.clear_history();second_history.clear_history();world.sessions.entries.clear();world.sessions.save_scene=Callable();session.entries.clear();session.save_scene=Callable();world._terrain_workspace.free();world._plan_target=null;world.free();history.free();second_history.free();second.free();vp.free()
	await process_frame;quit(0 if failures.is_empty() else 1)
