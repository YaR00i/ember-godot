@tool
extends EditorPlugin
## Focused real editor entry gate. Enable only in the existing disposable checkout.
const Shapes=preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Store=preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Profiles=preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
var errors:Array[String]=[]
func _enter_tree()->void:_run.call_deferred()
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("CANVAS_EDITOR_FAIL ",label)
func select_nodes(nodes:Array)->void:
	var selection:=EditorInterface.get_selection();selection.clear()
	for node in nodes:selection.add_node(node)
func _run()->void:
	if not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):return
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer available");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+120000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"preparation finishes")
	if "--terrain-wall-only" in OS.get_cmdline_user_args():
		await _terrain_wall(importer);return
	if "--forms-cycle-only" in OS.get_cmdline_user_args() or "--forms-panel-only" in OS.get_cmdline_user_args():
		await _forms_cycle(importer);return
	if "--shared-mask-only" in OS.get_cmdline_user_args() or "--shared-mask-direction-only" in OS.get_cmdline_user_args():
		await _shared_mask(importer);return
	if "--brush-settings-only" in OS.get_cmdline_user_args():
		await _brush_settings(importer);return
	if "--canvas-plane-only" in OS.get_cmdline_user_args() or "--canvas-plane-transfer-only" in OS.get_cmdline_user_args():
		await _canvas_plane(importer);return
	if "--world-plane-only" in OS.get_cmdline_user_args() or "--plane-capture-only" in OS.get_cmdline_user_args():
		await _world_smooth(importer,true);return
	if "--world-smooth-only" in OS.get_cmdline_user_args():
		await _world_smooth(importer);return
	if "--world-context-only" in OS.get_cmdline_user_args():
		await _world_context(importer);return
	var fixture:=Node3D.new();fixture.name="CanvasEntryFixture"
	var paths:Array[String]=[];var hashes:Array[String]=[]
	for i in 2:
		var source:EmberVoxelModelResource=Shapes.build("block",Vector3i(16,16,16),16,Color("77838a"),"qa_canvas_%d_%d"%[OS.get_process_id(),i],"Форма %d"%i).source
		source.palette.append(Color("886243"));source.merge_parts=PackedStringArray(["Основа"]);source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1)
		source.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","stone","soil"]),"material_ids":PackedStringArray(["","cartoon_stone","soil_grain"]),"occupancy":preload("res://scripts/ember_voxel_solid_surface.gd").occupancy_hash(source.voxels)}
		var path:="res://content/voxel_models/"+source.model_id+".tres"
		var saved:=Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),path,"user://canvas-editor-qa/"+source.model_id+".tscn")
		check(saved.ok,"fixture asset");paths.append(path);hashes.append(FileAccess.get_sha256(path))
		var prop:=saved.packed.instantiate() as EmberVoxelProp;fixture.add_child(prop);prop.owner=fixture;prop.position.x=i*8
	var scene_path:="res://tools/fixtures/qa_canvas_entry_%d.tscn"%OS.get_process_id()
	var packed:=PackedScene.new();check(packed.pack(fixture)==OK and ResourceSaver.save(packed,scene_path)==OK,"fixture scene save");fixture.free()
	EditorInterface.get_resource_filesystem().update_file(scene_path);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+30000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root();check(scene!=null and scene.scene_file_path==scene_path,"fixture opens")
	if scene==null:get_tree().quit(1);return
	var nodes:Array=scene.get_children();var world:Node=importer._world_editor
	world.active=false
	var entry_only:bool="--canvas-entry-only" in OS.get_cmdline_user_args()
	var open:Button=importer._voxel_object_toolbar.get_node("OpenSelectedCanvas")
	select_nodes([nodes[0]]);open.pressed.emit();await frames(3)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	check(view._world_sessions==world.sessions and view._world_entry.target.get_ref()==nodes[0],"ordinary object uses world draft while world tool inactive")
	check(view._actions.apply_stroke(view._resource,{0:{"before":1,"after":2}}),"paint before scene merge")
	select_nodes(nodes);open.pressed.emit();await frames(3)
	var forms:RefCounted=view._canvas_forms
	check(forms!=null and forms.bodies.size()==2 and view._resource.voxels[0]==2,"scene command keeps dirty paint and includes both forms")
	check(view._canvas_mode==view.CanvasMode.FORMS and view._tool.get_selected_items().is_empty() and not view._radius.visible,"forms mode owns input and hides brush settings")
	if forms==null:
		printerr("CANVAS_ENTRY_STATUS ",view._status.text);get_tree().quit(1);return
	open.pressed.emit();check(view._canvas_forms==forms and forms.bodies.size()==2,"repeat command reuses same context")
	if entry_only:
		select_nodes([]);open.pressed.emit()
		check(view._canvas_forms==forms and forms.bodies.size()==2,"empty selection never falls back to an unrelated last object")
		var panel:=EmberObjectInspectorPanel.new();panel.hide();add_child(panel);panel.setup(nodes[0],EmberObjectInspectorModel.snapshot(nodes[0]))
		var actions:VBoxContainer=panel.get_node("VoxelCanvasActions");var received:Array[String]=[]
		panel.canvas_action_requested.connect(func(prop,action):check(prop==nodes[0],"inspector target preserved");received.append(action))
		check(actions.get_child_count()==2,"one primary edit button and one secondary menu")
		actions.get_node("EditObjectInCanvas").pressed.emit()
		var popup:PopupMenu=actions.get_node("CanvasModelActions").get_popup()
		for i in popup.item_count:popup.id_pressed.emit(i)
		check(received==["selected","shared","linked","independent"],"all existing inspector actions retain their identity")
		panel.free();select_nodes([nodes[0]]);EditorInterface.inspect_object(nodes[0])
		EditorInterface.set_main_screen_editor("3D");await frames(6);await RenderingServer.frame_post_draw
		var image:="user://canvas-entry-%d.png"%OS.get_process_id()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
		print("CANVAS_ENTRY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}))
		get_tree().quit(0 if errors.is_empty() else 1);return
	await frames(4);await RenderingServer.frame_post_draw
	var capture:="user://canvas-editor-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(capture));print("CANVAS_EDITOR_CAPTURE ",ProjectSettings.globalize_path(capture))
	view._forms_panel.join.pressed.emit();check(forms.bodies.size()==1 and view._canvas_mode==view.CanvasMode.BRUSH,"join returns to sculpt without intermediate Save")
	if "--projection-frame-only" in OS.get_cmdline_user_args():
		var combined:Dictionary=forms.active.entry
		deadline=Time.get_ticks_msec()+30000
		while is_instance_valid(combined.preview) and not combined.preview.is_projection_complete() and Time.get_ticks_msec()<deadline:await frames(1)
		check(is_instance_valid(combined.preview) and combined.preview.global_transform.is_equal_approx(world.sessions.frame(combined)),"expanded union preview uses the publication Source frame")
		print("CANVAS_EDITOR_FRAME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
		get_tree().quit(0 if errors.is_empty() else 1);return
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();check(forms.bodies.size()==2 and view._resource.voxels[0]==2,"single scene Undo retains prior paint")
	history.redo();check(forms.bodies.size()==1,"scene Redo joins")
	var united:EmberVoxelProp=forms.active.node
	select_nodes([united]);importer._open_selected_canvas(true)
	check(view._canvas_forms==forms,"part command reuses Canvas")
	for button in view._forms_panel.find_children("*","Button",true,false):
		if button.text=="Разобрать части":button.pressed.emit();break
	check(forms.bodies.size()==2,"part command separates editable forms")
	history.undo();check(forms.bodies.size()==1,"part Undo restores union")
	EditorInterface.set_main_screen_editor("3D")
	for i in world.tools.item_count:
		if str(world.tools.get_item_metadata(i))=="smooth":world.tools.select(i);break
	world._tool_changed()
	check(world._mode()=="smooth" and not view.is_visible_in_tree(),"world Smooth remains in 3D")
	check(view.save_changes(),world.sessions.error)
	var entry:Dictionary=view._world_entry
	check(entry.resource.to_definition(true).model==ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).to_definition(true).model,"fresh Source reopen equals saved draft")
	var saved_data:Dictionary=entry.resource.to_definition(true).model.duplicate(true)
	entry.resource.voxels[0]=0;view.discard_changes();check(entry.resource.to_definition(true).model==saved_data and not view.has_unsaved_changes(),"discard restores saved data")
	for look in 3:
		united.set_world_look(look);check(united.get_node("Mesh").mesh.get_faces()==united.get_node("Collision/Shape").shape.get_faces(),"saved look%d matches collision"%look)
	for i in paths.size():check(FileAccess.get_sha256(paths[i])==hashes[i],"original Source remains unchanged")
	var reopened:Node=ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate();check(reopened.get_child_count()==1,"saved scene reopens as one object");reopened.free()
	print("CANVAS_EDITOR ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	get_tree().quit(0 if errors.is_empty() else 1)

func _world_context(importer:Node)->void:
	var path:="res://scenes/landscape_compact.tscn"
	EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor
	var map:Node=scene.get_node("Map")
	var a:Node3D=scene.get_node("Map/Props/EarthCliffCorner")
	var b:Node3D=scene.get_node("Map/Props/EarthCliffStraight")
	world.active=true;world.sidebar.show();EditorInterface.set_main_screen_editor("3D")
	check(world.activate_context(map),"ground context opens")
	var ground:Dictionary=world.entry
	check(world.activate_context(a),"first object opens")
	var first:Dictionary=world.entry
	world._changing_context=true;world._category_changed(1,true,"paint");world._changing_context=false
	world.radius.value=3.31
	var radius:float=world.radius.value
	var camera:Camera3D=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var camera_pose:=camera.global_transform
	await frames(5);await RenderingServer.frame_post_draw
	var image:="user://world-context-%d.png"%OS.get_process_id()
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("WORLD_CONTEXT_CAPTURE ",ProjectSettings.globalize_path(image))
	check(world.target_choice.get_item_text(1).contains(str(a.name)),"panel identifies selected object")
	check(world.actions.apply_stroke(first.resource,_context_paint(first.resource)),"first object paint")
	var first_data:Dictionary=first.resource.to_definition(true).model.duplicate(true)
	select_nodes([b]);await frames(3)
	check(world.entry.target.get_ref()==b,"ordinary native selection follows second object")
	var second:Dictionary=world.entry
	check(world.actions.apply_stroke(second.resource,_context_paint(second.resource)),"second object paint")
	check(world.activate_context(map) and world.entry.resource==ground.resource,"same ground draft reused")
	check(world._mode()=="paint" and is_equal_approx(world.radius.value,radius),"brush and physical radius survive ground switch")
	check(world.activate_context(a) and world.entry.resource==first.resource and first.resource.to_definition(true).model==first_data,"first dirty object retained")
	world.dragging=true
	check(not world.activate_context(b) and world.entry.target.get_ref()==a and world.dragging,"active gesture is never cancelled by context switch")
	world.dragging=false
	world._changing_context=true;world._category_changed(0,true,"add");world._changing_context=false
	check(world.activate_context(map) and world._mode()=="add" and not world._context_tool_available(),"unsupported ground brush remains explicit")
	world._set_busy(false)
	check(world._tool_buttons[world.tools.selected].disabled,"busy completion keeps unsupported brush disabled")
	check(world.activate_context(a) and world._mode()=="add" and world._context_tool_available(),"object restores supported brush")
	deadline=Time.get_ticks_msec()+120000
	while is_instance_valid(first.preview) and not first.preview.is_projection_complete() and Time.get_ticks_msec()<deadline:await frames(1)
	check(is_instance_valid(first.preview) and first.preview.is_projection_complete(),"dirty projection finishes")
	var derived:Node=first.preview._object_visual
	check(derived!=null and world._context_target(derived)==a,"derived preview resolves authored object")
	# Exercise the actual viewport handler with a ray through an upward triangle.
	var mesh:MeshInstance3D=derived.get_node("Mesh") if derived!=null else null
	if mesh!=null:
		var faces:PackedVector3Array=mesh.mesh.get_faces()
		for i in range(0,faces.size(),3):
			if (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized().y<0.6:continue
			var point:Vector3=mesh.global_transform*((faces[i]+faces[i+1]+faces[i+2])/3.0)
			camera.global_position=point+Vector3(0,10,1);camera.look_at(point)
			await get_tree().physics_frame;await frames(2)
			check(world.activate_context(b),"switch away before ray selection")
			var motion:=InputEventMouseMotion.new();motion.position=camera.unproject_position(point)
			importer._forward_3d_gui_input(camera,motion)
			var key:=InputEventKey.new();key.keycode=KEY_Q;key.alt_pressed=true;key.pressed=true
			var focus:Control=get_viewport().gui_get_focus_owner()
			if focus!=null:focus.release_focus()
			check(importer._forward_3d_gui_input(camera,key)==EditorPlugin.AFTER_GUI_INPUT_STOP and world.entry.target.get_ref()==a,"Alt Q selects real object through preview collider")
			var edit:=LineEdit.new();world.sidebar.add_child(edit);edit.grab_focus();await frames(1)
			check(importer._forward_3d_gui_input(camera,key)==EditorPlugin.AFTER_GUI_INPUT_PASS,"text input keeps Alt Q")
			edit.release_focus();edit.queue_free();break
	camera.global_transform=camera_pose
	world._changing_context=true;world._category_changed(1,true,"paint");world._changing_context=false
	check(world._open_canvas_entry(first),"Canvas opens current shared draft")
	await frames(3)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	check(view._resource==first.resource and view._world_entry==first,"Canvas shares exact dirty resource")
	check(view._selected_tool_id()==Model.TOOL_PAINT,"Canvas preserves brush")
	view._select_option_metadata(view._radius,24)
	view._on_brush_setting_changed()
	var physical_radius:float=float(view._radius.get_selected_metadata())/view._resource.normalized_density()
	select_nodes([b]);await frames(3)
	check(view._world_entry.target.get_ref()==b and view._resource==second.resource and view._selected_tool_id()==Model.TOOL_PAINT and is_equal_approx(float(view._radius.get_selected_metadata())/view._resource.normalized_density(),physical_radius),"native selection inside Canvas retains current brush and radius")
	select_nodes([a]);await frames(3)
	view._return_world_button.pressed.emit();await frames(3)
	check(world.entry.resource==first.resource and world._mode()=="paint" and is_equal_approx(world.radius.value,physical_radius),"return keeps shared draft and Canvas radius")
	check(camera.global_transform.is_equal_approx(camera_pose),"switching never reframes 3D camera")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	var second_data:Dictionary=second.resource.to_definition(true).model.duplicate(true)
	history.undo();check(second.resource.to_definition(true).model!=second_data and first.resource.to_definition(true).model==first_data,"common Undo addresses previous target")
	history.redo();check(second.resource.to_definition(true).model==second_data,"common Redo restores previous target")
	check(world.save_all(),"save all contexts: "+world.sessions.error)
	var saved_first:Dictionary=first.resource.to_definition(true).model.duplicate(true)
	for item in [first,second]:
		var loaded:Resource=ResourceLoader.load(item.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(loaded!=null and loaded.to_definition(true).model==item.resource.to_definition(true).model,"fresh Source reopen matches "+str(item.target.get_ref().name))
		check(item.resource.validation_errors().is_empty(),"saved Source validates")
	var packed:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var reopened:Node=packed.instantiate();check(reopened.get_node_or_null("Map/Props/EarthCliffCorner")!=null,"saved main copy reopens");reopened.free()
	check(world.actions.apply_stroke(first.resource,_context_paint(first.resource)),"post-save draft changes")
	world.sessions.discard(scene)
	check(not world.sessions.dirty(first) and not world.sessions.dirty(second) and first.resource.to_definition(true).model==saved_first,"discard returns both contexts to saved baseline")
	print("WORLD_CONTEXT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}))
	get_tree().quit(0 if errors.is_empty() else 1)

func _context_paint(resource:EmberVoxelModelResource)->Dictionary:
	for i in resource.voxels.size():
		if resource.voxels[i]>0:return {i:{"before":int(resource.voxels[i]),"after":2 if resource.voxels[i]!=2 else 1}}
	return {}

func _world_smooth(importer:Node,plane:=false)->void:
	const Smooth=preload("res://addons/ember_import/ember_voxel_volume_smooth.gd")
	const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
	var path:="res://scenes/landscape_compact.tscn"
	EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor;var map:Node=scene.get_node("Map")
	var actor:EmberVoxelProp=scene.get_node("Map/Props/EarthCliffCorner")
	world.active=true;world.sidebar.show();EditorInterface.set_main_screen_editor("3D")
	check(world.activate_context(actor),"object context opens")
	var mode:="level" if plane else "smooth"
	if plane:world.surface_plane_mode.select(2);world.surface_plane_offset.value=-2
	world._category_changed(0,true,mode);world._tool_changed()
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	check(not view.is_visible_in_tree() and world._mode()==mode,"selecting Smooth never opens Canvas")
	check(world._brush_parameter_controls.strength_detail.visible and not world._brush_parameter_controls.palette.visible,"volume controls omit height and paint")
	var entry:Dictionary=world.entry;var source:EmberVoxelModelResource=entry.resource
	var before:=source.voxels.duplicate();var before_parts:=source.voxel_part_ids.duplicate()
	var size:=source.grid_size();var center:=Vector3i.ZERO
	# A real occupied outer corner is a reproducible non-flat smoothing target.
	for i in before.size():
		if before[i]==0:continue
		var p:=Vector3i(i%size.x,i/(size.x*size.z),(i/size.x)%size.z);var exposed:=0
		for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
			var q:Vector3i=p+d
			if q.x<0 or q.y<0 or q.z<0 or q.x>=size.x or q.y>=size.y or q.z>=size.z or before[Model.index_of(q,size)]==0:exposed+=1
		if exposed>=3:center=p;break
	world.radius.value=8.0/source.normalized_density();world.depth.value=4
	var expected:RefCounted=Model.SurfacePlaneJob.new() if plane else Smooth.new()
	expected.values=before;expected.parts=before_parts;expected.size=size;expected.radius=8
	if plane:
		expected.depth=4;expected.cut_only=true
		var n:=Model.averaged_surface_normal(before,size,center,Vector3i.LEFT,Model.surface_normal_radius(8),Vector3i.LEFT)
		expected.plane_normal=n;expected.plane_point=Vector3(center)+Vector3.LEFT*0.5-n*2
	else:expected.kernel=4
	expected.segments.assign([{"from":center,"to":center}]);expected.run()
	check(not expected.changes.is_empty(),"real object has smoothing delta")
	var expected_values:=before.duplicate();var expected_parts:=before_parts.duplicate()
	for i in expected.changes:
		expected_values[i]=expected.changes[i].after
		if not expected_parts.is_empty():expected_parts[i]=0 if expected_values[i]==0 else expected.owners.get(i,expected_parts[i])
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene));var version:=history.get_version()
	world._begin_stroke({"hit":center,"normal":Vector3i.LEFT})
	deadline=Time.get_ticks_msec()+30000
	while world.job!=null or not world.queue.is_empty():
		if Time.get_ticks_msec()>deadline:check(false,"smooth worker deadline");break
		await frames(1)
	check(world.dragging and source.voxels==expected_values and source.voxel_part_ids==expected_parts,"held 3D preview equals existing Canvas calculation including donor parts")
	if plane and "--plane-capture-only" in OS.get_cmdline_user_args():
		world.inspector_panel.show();importer._set_world_editor_dock_active(true)
		deadline=Time.get_ticks_msec()+120000
		while is_instance_valid(entry.preview) and not entry.preview.is_projection_complete() and Time.get_ticks_msec()<deadline:await frames(1)
		var mesh:MeshInstance3D=actor.get_node("Mesh")
		var point:Vector3=mesh.global_transform*mesh.mesh.get_aabb().get_center()
		var camera:Camera3D=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		var distance:float=mesh.mesh.get_aabb().size.length()*mesh.global_transform.basis.get_scale().length()
		camera.global_position=point+Vector3(0.7,0.5,0.8).normalized()*maxf(8.0,distance);camera.look_at(point)
		await frames(5);await RenderingServer.frame_post_draw
		var image:="user://surface-plane-panel-%d.png"%OS.get_process_id()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
		world.cancel_stroke();print("SURFACE_PLANE_CAPTURE ",ProjectSettings.globalize_path(image));get_tree().quit(0 if errors.is_empty() else 1);return
	check(history.get_version()==version,"held gesture has no history commit")
	world.released=true;await frames(2)
	check(not world.dragging and source.validation_errors().is_empty(),"release commits valid volume")
	history.undo();check(source.voxels==before and source.voxel_part_ids==before_parts,"one Undo restores geometry and parts")
	history.redo();check(source.voxels==expected_values and source.voxel_part_ids==expected_parts,"Redo exact")
	world._begin_stroke({"hit":center,"normal":Vector3i.LEFT});await frames(1)
	check(world.job is Smooth or world.job is Model.SurfacePlaneJob,"local worker used asynchronously")
	world.cancel_stroke();await frames(5)
	check(source.voxels==expected_values and source.voxel_part_ids==expected_parts,"Cancel rejects pending worker result")
	check(world.activate_context(map) and world._mode()==mode and world._compact_active(),"same brush continues on ground")
	var ground:Dictionary=world.entry;var terrain:Resource=ground.resource
	check(world._compact_brush.begin(mode,0.5,4,1,0,16,0,1,0),"existing ground smooth starts")
	world._compact_brush.stamp(Vector2i(320,320),Rect2i());world._compact_brush.cancel()
	check(not world.sessions.dirty(ground),"ground cancellation preserves original terrain")
	check(world.activate_context(actor) and world._mode()==mode and not view.is_visible_in_tree(),"return to volume stays in 3D")
	deadline=Time.get_ticks_msec()+120000
	while is_instance_valid(entry.preview) and not entry.preview.is_projection_complete() and Time.get_ticks_msec()<deadline:await frames(1)
	check(is_instance_valid(entry.preview) and entry.preview.is_projection_complete(),"dirty object projection finishes")
	if is_instance_valid(entry.preview) and is_instance_valid(entry.preview._object_visual):
		for look in 3:
			actor.set_world_look(look);await frames(2)
			var visual:EmberVoxelProp=entry.preview._object_visual
			check(visual.get_node("Mesh").mesh.get_faces()==visual.get_node("Collision/Shape").shape.get_faces(),"look%d visual equals physics"%look)
	actor.set_world_look(1)
	check(world.save_all(),"save smooth: "+world.sessions.error)
	var loaded:Resource=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(loaded!=null and loaded.voxels==expected_values and loaded.voxel_part_ids==expected_parts and loaded.validation_errors().is_empty(),"fresh Source reopen exact")
	var packed:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP);var reopened:Node=packed.instantiate()
	check(reopened.get_node_or_null("Map/Props/EarthCliffCorner")!=null,"saved main copy reopens");reopened.free()
	world._begin_stroke({"hit":center,"normal":Vector3i.LEFT});world.released=true
	deadline=Time.get_ticks_msec()+30000
	while world.dragging and Time.get_ticks_msec()<deadline:await frames(1)
	world.sessions.discard(scene)
	check(source.voxels==expected_values and source.voxel_part_ids==expected_parts and not world.sessions.dirty(entry),"discard restores saved smoothing")
	await frames(2);await RenderingServer.frame_post_draw
	var image:="user://world-%s-%d.png"%["plane" if plane else "smooth",OS.get_process_id()];EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("WORLD_PLANE " if plane else "WORLD_SMOOTH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"changes":expected.changes.size(),"kernel_usec":0 if plane else expected.elapsed_usec,"capture":ProjectSettings.globalize_path(image)}))
	get_tree().quit(0 if errors.is_empty() else 1)

func _canvas_plane(importer:Node)->void:
	var path:="res://scenes/landscape_compact.tscn";EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor;var actor:Node3D=scene.get_node("Map/Props/EarthCliffCorner")
	world.active=true;world.sidebar.show();world.activate_context(actor)
	world.surface_plane_mode.select(2);world.surface_plane_offset.value=-2;world._category_changed(0,true,"level");world.radius.value=0.5;world.depth.value=4
	var entry:Dictionary=world.entry
	check(world._open_canvas_entry(entry),"Canvas opens common plane context");await frames(3)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	check(view.surface_plane_settings()=={"mode":2,"offset":-2.0,"depth":4.0} and view._resource==entry.resource,"3D to Canvas transfers same draft and plane settings")
	check(view._surface_plane_mode.visible and view._surface_plane_offset.visible and view._depth.visible and not view._coarse.visible and view._selection_panel._mask_kind=="voxels","surface plane UI and exact mask policy")
	if "--canvas-plane-transfer-only" in OS.get_cmdline_user_args():
		view.set_surface_plane_settings(0,0,4);view._activate_tool_id(Model.TOOL_PAINT);view._activate_tool_id(Model.TOOL_LEVEL)
		check(view._selection_panel._mask_kind=="columns" and view.surface_plane_settings().mode==0,"height profile restores column mask after another tool")
		view.set_surface_plane_settings(2,-3,12);world.depth.max_value=8
		view._return_world_button.pressed.emit();await frames(2)
		check(world.depth.value==12 and world.surface_plane_mode.selected==2 and world.surface_plane_offset.value==-3,"Canvas plane depth survives previous Smooth range")
		check(world._open_canvas_entry(entry),"plane returns to shared Canvas");await frames(3)
		check(view.surface_plane_settings()=={"mode":2,"offset":-3.0,"depth":12.0} and view._selection_panel._mask_kind=="voxels" and not view._palette.visible,"return restores exact plane settings and voxel policy")
		await RenderingServer.frame_post_draw
		var image:="user://canvas-plane-transfer-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
		print("CANVAS_PLANE_TRANSFER ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1);return
	var source:EmberVoxelModelResource=entry.resource;var before:=source.voxels.duplicate();var parts:=source.voxel_part_ids.duplicate();var size:=source.grid_size();var center:=Vector3i.ZERO
	for i in before.size():
		if before[i]==0:continue
		var p:=Vector3i(i%size.x,i/(size.x*size.z),(i/size.x)%size.z);var exposed:=0
		for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
			var q:Vector3i=p+d
			if not Model.contains(q,size) or before[Model.index_of(q,size)]==0:exposed+=1
		if exposed>=3:center=p;break
	var reference:=Model.SurfacePlaneJob.new();reference.values=before;reference.parts=parts;reference.size=size;reference.radius=8;reference.depth=4;reference.cut_only=true
	var n:=Model.averaged_surface_normal(before,size,center,Vector3i.LEFT,Model.surface_normal_radius(8),Vector3i.LEFT)
	reference.plane_normal=n;reference.plane_point=Vector3(center)+Vector3.LEFT*0.5-n*2;reference.segments=[{"from":center,"to":center}];reference.run()
	check(not reference.changes.is_empty(),"native real Source has plane changes")
	var expected:=before.duplicate();var expected_parts:=parts.duplicate()
	for i in reference.changes:
		expected[i]=reference.changes[i].after
		if not expected_parts.is_empty():expected_parts[i]=0 if expected[i]==0 else reference.owners.get(i,expected_parts[i])
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene));var version:=history.get_version()
	view._prepare_stroke(Model.TOOL_LEVEL);view._last_stroke_normal=Vector3i.LEFT;view._apply_level_segment(center,center)
	await _canvas_plane_wait(view)
	check(view._stroke_active and view._stroke_live_values==expected and history.get_version()==version,"held Canvas matches same 3D plane calculation without early history")
	view._finish_stroke();check(source.voxels==expected and source.voxel_part_ids==expected_parts and source.validation_errors().is_empty(),"commit preserves materials and parts")
	history.undo();check(source.voxels==before and source.voxel_part_ids==parts,"one Undo exact")
	history.redo();check(source.voxels==expected,"Redo exact")
	view._prepare_stroke(Model.TOOL_LEVEL);view._last_stroke_normal=Vector3i.LEFT;view._apply_level_segment(center,center);view._cancel_stroke();await frames(3)
	check(source.voxels==expected,"Cancel rejects pending plane work")
	history.undo()
	var mask:PackedInt32Array=PackedInt32Array(reference.changes.keys());var locked:int=mask[0]
	view._selection_panel.apply_history_state({"grid_size":size,"selected":mask,"mask_indices":mask,"mask_enabled":true,"mask_normal":Vector3i.LEFT})
	view._locked_indices={locked:true};view._slice_height=center.y+1
	check(view._slice_allows_tool(Model.TOOL_LEVEL),"surface plane is available in working slice")
	view._prepare_stroke(Model.TOOL_LEVEL);view._last_stroke_normal=Vector3i.LEFT;view._apply_level_segment(center,center);await _canvas_plane_wait(view)
	for i in view._stroke_changes:
		check(i in mask and i!=locked and int(i)/(size.x*size.z)<view._slice_height,"voxel mask locked group and hidden height respected")
	view._cancel_stroke();view._slice_height=-1;view._locked_indices={};view._selection_panel.apply_history_state({"grid_size":size})
	check(source.voxels==before,"filtered Cancel restores baseline")
	history.redo();check(source.voxels==expected,"prior full gesture remains redoable after cancelled mask")
	view._activate_tool_id(Model.TOOL_PAINT);view._activate_tool_id(Model.TOOL_LEVEL)
	check(view.surface_plane_settings()=={"mode":2,"offset":-2.0,"depth":4.0},"Level tool profile retains plane settings")
	view.set_surface_plane_settings(1,-1,3);view._return_world_button.pressed.emit();await frames(2)
	check(world.surface_plane_mode.selected==1 and world.surface_plane_offset.value==-1 and world.depth.value==3 and world._mode()=="level","Canvas to 3D retains operation offset and depth")
	check(world._open_canvas_entry(entry),"same Canvas reopens without replacing draft");await frames(3)
	check(view.surface_plane_settings()=={"mode":1,"offset":-1.0,"depth":3.0},"return trip retains settings")
	check(view.save_changes(),"shared Save: "+world.sessions.error)
	for look in 3:
		actor.set_world_look(look)
		check(actor.get_node("Mesh").mesh.get_faces()==actor.get_node("Collision/Shape").shape.get_faces(),"Canvas plane look%d equals physics"%look)
	var loaded:Resource=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(loaded!=null and loaded.voxels==expected and loaded.voxel_part_ids==expected_parts and loaded.validation_errors().is_empty(),"fresh Source reopen exact")
	var packed:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP);var reopened:Node=packed.instantiate();check(reopened.get_node_or_null("Map/Props/EarthCliffCorner")!=null,"saved scene reopens");reopened.free()
	view._prepare_stroke(Model.TOOL_LEVEL);view._last_stroke_normal=Vector3i.LEFT;view._apply_level_segment(center,center);await _canvas_plane_wait(view);view._finish_stroke();view.discard_changes()
	check(view._resource.voxels==expected and not view.has_unsaved_changes(),"discard returns saved state")
	view._activate_tool_id(Model.TOOL_LEVEL);view.set_surface_plane_settings(0,0,4)
	check(view._selection_panel._mask_kind=="columns" and not view._surface_plane_offset.visible,"legacy height Level keeps its old policy")
	view.set_surface_plane_settings(1,-1,3)
	await frames(5);await RenderingServer.frame_post_draw
	var image:="user://canvas-plane-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("CANVAS_PLANE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1)

func _canvas_plane_wait(view:Control)->void:
	var deadline:=Time.get_ticks_msec()+30000
	while view._volume_smooth_job!=null or not view._volume_smooth_segments.is_empty():
		if Time.get_ticks_msec()>deadline:check(false,"Canvas plane worker deadline");return
		view._drain_volume_smooth();await frames(1)

func _brush_settings(importer:Node)->void:
	var path:="res://scenes/landscape_compact.tscn";EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor;var actor:Node3D=scene.get_node("Map/Props/EarthCliffCorner")
	world.active=true;world.sidebar.show();world.activate_context(actor)
	var entry:Dictionary=world.entry;var original:Dictionary=entry.resource.to_definition(true).model.duplicate(true)
	world._category_changed(0,true,"smooth");world.radius.value=8;world.depth.value=5
	check(world._open_canvas_entry(entry),"open shared Smooth settings");await frames(2)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	check(view._smooth_strength.get_selected_metadata()==5 and view._radius.get_selected_metadata()==128,"3D strength5 and radius128 transfer exactly")
	view._activate_tool_id(Model.TOOL_PAINT);view._activate_tool_id(Model.TOOL_SMOOTH)
	check(view._radius.get_selected_metadata()==128 and view._smooth_strength.get_selected_metadata()==5,"Smooth profile retains nonpreset strength and large radius")
	view.set_world_brush_settings(7,75);view._return_world_button.pressed.emit();await frames(2)
	check(world._mode()=="smooth" and world.depth.value==7 and world.radius.value==8,"Canvas Smooth strength returns to 3D")
	world._category_changed(0,true,"add");world.depth.value=27
	check(world._open_canvas_entry(entry),"open Add settings");await frames(2)
	check(view._selected_tool_id()==Model.TOOL_ADD and view._depth.value==27,"Add depth exact after previous Smooth range")
	view._depth.value=19;view._return_world_button.pressed.emit();await frames(2)
	check(world.depth.value==19 and world._mode()=="add","Canvas Add depth returns")
	world._category_changed(0,true,"remove");world.depth.value=23;world._open_canvas_entry(entry);await frames(2)
	check(view._selected_tool_id()==Model.TOOL_REMOVE and view._depth.value==23,"Remove uses same depth contract")
	view._return_world_button.pressed.emit();await frames(2)
	world._category_changed(0,true,"grab");world.softness.value=31;world._open_canvas_entry(entry);await frames(2)
	check(view._grab_softness.value==31 and view._grab_softness.visible,"Grab softness transfers to Canvas")
	view._grab_softness.value=67;view._return_world_button.pressed.emit();await frames(2)
	check(world._mode()=="grab" and world.softness.value==67,"Grab softness returns to 3D")
	world._open_canvas_entry(entry);await frames(2)
	view._activate_tool_id(Model.TOOL_SMOOTH);view.set_world_brush_radius(8);view.set_world_brush_settings(5,67)
	view._remember_current_editor_view()
	var store:=preload("res://addons/ember_import/ember_surface_editor_view_store.gd").new()
	var config:=ConfigFile.new();config.set_value("ember","view",view._view_store.export_data())
	var config_path:="user://brush-settings-%d.cfg"%OS.get_process_id()
	check(config.save(config_path)==OK,"editor settings serialize")
	var fresh:=ConfigFile.new();check(fresh.load(config_path)==OK,"editor settings fresh reopen");store.import_data(fresh.get_value("ember","view",{}))
	var saved:Dictionary=Profiles.normalize_profiles(store.recall_brush_profiles())
	check(saved[Model.TOOL_SMOOTH].radius==128 and saved[Model.TOOL_SMOOTH].smooth_strength==5,"fresh profile retains radius and Smooth force")
	check(saved[Model.TOOL_ADD].depth==23 and saved[Model.TOOL_GRAB].grab_softness==67,"fresh profiles retain volume and Grab settings")
	var normalized:=Profiles.normalize_profile({"radius":99999,"smooth_strength":999,"depth":999,"grab_softness":-10})
	check(normalized.radius==Profiles.MAX_RADIUS_VOXELS and normalized.smooth_strength==8 and normalized.depth==32 and normalized.grab_softness==0,"invalid settings clamp to actual operation bounds")
	check(not world.sessions.dirty(entry) and entry.resource.to_definition(true).model==original,"settings never edit voxel geometry or materials")
	check(entry.resource.validation_errors().is_empty(),"unchanged Source validates")
	await frames(3);await RenderingServer.frame_post_draw
	var image:="user://brush-settings-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("BRUSH_SETTINGS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1)

func _shared_mask(importer:Node)->void:
	var path:="res://scenes/landscape_compact.tscn";EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor;var a:Node3D=scene.get_node("Map/Props/EarthCliffCorner");var b:Node3D=scene.get_node("Map/Props/EarthCliffStraight")
	world.active=true;world.sidebar.show();world.activate_context(a);world._category_changed(1,true,"paint");world.radius.value=0.5;world.depth.value=3
	var entry:Dictionary=world.entry;var source:EmberVoxelModelResource=entry.resource;var size:=source.grid_size();var at:=-1
	for i in range(source.voxels.size()-1):
		if i%size.x<size.x-1 and source.voxels[i]>0 and source.voxels[i+1]>0:at=i;break
	check(at>=0,"contiguous cells available")
	var cell:=Vector3i(at%size.x,at/(size.x*size.z),(at/size.x)%size.z);var locked:=at+1
	check(world._open_canvas_entry(entry),"shared Canvas opens");await frames(2)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	var created:Dictionary=view._actions.apply_groups(source,{"kind":"create","id":"qa_shared_guard","name":"QA protected","indices":PackedInt32Array([locked])})
	check(not created.has("error"),"fixture group created")
	check(not view._actions.apply_groups(source,{"kind":"lock","id":"qa_shared_guard","locked":true}).has("error"),"fixture group locked")
	var before:=source.voxels.duplicate();var document:Dictionary=source.to_definition(true).model.duplicate(true)
	var region:=Rect2i(Vector2i(cell.x/source.normalized_density(),cell.z/source.normalized_density()),Vector2i.ONE)
	view._edit_region_blocks=region;view._slice_height=cell.y+1;view._selection_panel.sync(source,region,view._slice_height,view._surface_root)
	view._selection_panel.apply_history_state({"grid_size":size,"selected":PackedInt32Array([at,locked]),"mask_indices":PackedInt32Array([at,locked]),"mask_enabled":true,"mask_normal":Vector3i.LEFT})
	view._return_world_button.pressed.emit();await frames(2)
	check(entry.canvas_guard.selection.mask_enabled and entry.canvas_guard.height==cell.y+1 and entry.canvas_guard.region==region,"Canvas publishes guard to same draft")
	check(source.to_definition(true).model==document,"guard metadata never changes Source")
	if "--shared-mask-direction-only" in OS.get_cmdline_user_args():
		world._begin_stroke({"hit":cell,"normal":Vector3i.UP})
		check(not world.queue.is_empty() and world.queue[0].normal==Vector3i.LEFT,"3D uses signed mask face rather than neighbouring hit face")
		world.cancel_stroke();world._category_changed(0,true,"add")
		var expected:Vector3i=cell+Vector3i.LEFT if Model.contains(cell+Vector3i.LEFT,size) else Model.INVALID_CELL
		check(world._center({"hit":cell,"adjacent":cell+Vector3i.UP,"normal":Vector3i.UP},"add")==expected,"Add adjacent cell follows same signed mask face")
		world._category_changed(1,true,"paint");world.inspector_panel.show();importer._set_world_editor_dock_active(true)
		var mesh:MeshInstance3D=a.get_node("Mesh");var point:Vector3=mesh.global_transform*mesh.mesh.get_aabb().get_center()
		var camera:Camera3D=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();var distance:float=mesh.mesh.get_aabb().size.length()*mesh.global_transform.basis.get_scale().length()
		camera.global_position=point+Vector3(0.7,0.5,0.8).normalized()*maxf(8.0,distance);camera.look_at(point)
		await frames(5);await RenderingServer.frame_post_draw
		var image:="user://shared-mask-direction-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
		print("SHARED_MASK_DIRECTION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1);return
	var after:=2 if before[at]!=2 else 1
	for i in world.palette.item_count:
		if world.palette.get_item_metadata(i)==after:world.palette.select(i);break
	world._begin_stroke({"hit":cell,"normal":Vector3i.LEFT});world.released=true;await _world_mask_wait(world)
	var expected:=before.duplicate();expected[at]=after
	check(source.voxels==expected and source.voxels[locked]==before[locked],"3D stroke respects exact mask locked group region and hidden height")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();check(source.voxels==before,"single Undo exact");history.redo();check(source.voxels==expected,"Redo exact")
	world.activate_context(b);check(not world.entry.has("canvas_guard"),"mask never leaks to second object")
	world.activate_context(a);check(world.entry==entry and world.sessions.brush_guard(entry,"voxels").enabled,"original object retains its guard")
	world._open_canvas_entry(entry);await frames(2)
	check(view._selection_panel.has_saved_mask() and view._selection_panel.allows_brush_index(at) and not view._selection_panel.allows_brush_index(at+size.x) and view._slice_height==cell.y+1 and view._edit_region_blocks==region,"Canvas restores exact mask scope and cut")
	view._activate_tool_id(Model.TOOL_GRAB)
	check(not view._grab_interaction.begin(Vector2.ZERO) and view._status.text.contains("маск"),"Canvas Grab cannot bypass saved mask")
	view._return_world_button.pressed.emit();await frames(2)
	check(not world._context_tool_available(),"3D labels unsupported masked Grab")
	world._begin_grab(Vector2.ZERO);check(world.grab.is_empty() and source.voxels==expected,"3D Grab cannot bypass saved mask")
	world._clear_shared_mask.pressed.emit()
	check(not entry.canvas_guard.selection.mask_enabled and world._context_tool_available(),"clear mask re-enables supported context")
	world._open_canvas_entry(entry);await frames(2)
	check(not view._selection_panel.has_saved_mask() and view._slice_height==cell.y+1 and view._edit_region_blocks==region,"clear in3D restores Canvas without erasing scope")
	view._return_world_button.pressed.emit();await frames(2)
	check(world.save_all(),"shared protected Save: "+world.sessions.error)
	var loaded:Resource=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(loaded!=null and loaded.voxels==expected and loaded.validation_errors().is_empty() and not loaded.to_definition(true).model.has("canvas_guard"),"fresh Source contains paint and groups but no session guard")
	var packed:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP);var reopened:Node=packed.instantiate();check(reopened.get_node_or_null("Map/Props/EarthCliffCorner")!=null,"saved scene reopens");reopened.free()
	world._category_changed(1,true,"paint")
	for i in world.palette.item_count:
		if world.palette.get_item_metadata(i)==before[at]:world.palette.select(i);break
	world._begin_stroke({"hit":cell,"normal":Vector3i.LEFT});world.released=true;await _world_mask_wait(world)
	world.sessions.discard(scene)
	check(source.voxels==expected and not world.sessions.dirty(entry) and entry.canvas_guard.height==cell.y+1,"discard restores saved document without erasing session protection")
	world._open_canvas_entry(entry);await frames(2)
	view._selection_panel.apply_history_state({"grid_size":size,"selected":PackedInt32Array([at]),"mask_indices":PackedInt32Array([at]),"mask_enabled":true,"mask_normal":Vector3i.LEFT});view._return_world_button.pressed.emit();await frames(2)
	importer._set_world_editor_dock_active(true)
	await frames(3);await RenderingServer.frame_post_draw
	var image:="user://shared-mask-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("SHARED_MASK ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1)

func _world_mask_wait(world:Node)->void:
	var deadline:=Time.get_ticks_msec()+30000
	while world.dragging and Time.get_ticks_msec()<deadline:await frames(1)
	check(not world.dragging,"protected stroke finishes")

func _forms_cycle(importer:Node)->void:
	const Selection=preload("res://addons/ember_import/ember_voxel_selection.gd")
	const Stamp=preload("res://addons/ember_import/ember_voxel_stamp.gd")
	var path:="res://scenes/landscape_compact.tscn";EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root()
	if scene==null or scene.scene_file_path!=path:check(false,"main copy opens");get_tree().quit(1);return
	var world:Node=importer._world_editor;var a:Node3D=scene.get_node("Map/Props/EarthCliffCorner");var b:Node3D=scene.get_node("Map/Props/EarthCliffUnion" if "--forms-panel-only" in OS.get_cmdline_user_args() and scene.has_node("Map/Props/EarthCliffUnion") else "Map/Props/EarthCliffStraight")
	world.active=true;world.activate_context(a);check(world._open_canvas_entry(world.entry),"common Canvas opens");await frames(2)
	var view:Control=EditorInterface.get_editor_main_screen().find_child(importer.SURFACE_WORKSPACE_NODE,true,false)
	view._enable_canvas_forms();var forms:RefCounted=view._canvas_forms
	check(forms.include_nodes([b]),"existing second form enters same context")
	if "--forms-panel-only" in OS.get_cmdline_user_args():
		var panel:Control=view._forms_panel
		for i in forms.bodies.size():
			forms.select(i);panel.refresh()
			var active_source:EmberVoxelModelResource=forms.active.entry.resource
			var count:int=active_source.voxels.size()-active_source.voxels.count(0)
			check(view._footer_stats.text.begins_with(str(count)+" "),"footer counts selected form")
			check(view._workshop_context_label.text.contains(active_source.display_name),"active form context")
		check(not panel.options_row.visible,"technical options initially collapsed")
		panel.advanced.button_pressed=true;check(panel.options_row.visible,"advanced options open")
		panel.advanced.button_pressed=false
		panel.mode.button_pressed=true;panel.refresh();check(view._canvas_mode==view.CanvasMode.FORMS and panel.position_row.visible,"move shows coordinates")
		panel.mode.button_pressed=false;panel.refresh();check(view._canvas_mode==view.CanvasMode.BRUSH and not panel.position_row.visible,"sculpt hides coordinates")
		check(not view.has_unsaved_changes(),"UI navigation does not dirty forms")
		await frames(5);await RenderingServer.frame_post_draw
		var image:="user://forms-panel-%d.png"%OS.get_process_id()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
		print("FORMS_PANEL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1);return
	var entry:Dictionary=forms.bodies[0].entry;var source:EmberVoxelModelResource=entry.resource;var old_size:=source.grid_size();var at:=source.voxels.find(1)
	if at<0:at=source.voxels.find(2)
	var first_mask:=PackedInt32Array([at])
	view._selection_panel.apply_history_state({"grid_size":old_size,"selected":first_mask,"mask_indices":first_mask,"mask_enabled":true,"mask_normal":Vector3i.LEFT})
	var original_b:PackedByteArray=forms.bodies[1].entry.resource.voxels.duplicate();var original_a:=source.voxels.duplicate()
	view._activate_tool_id(Model.TOOL_PAINT);view._prepare_stroke(Model.TOOL_PAINT)
	var dirty:Dictionary={};view._merge_live_changes({at:{"before":int(source.voxels[at]),"after":2 if source.voxels[at]!=2 else 1}},dirty);view._finish_live_changes(dirty,Model.TOOL_PAINT,-1)
	forms.select(1)
	check(not view._stroke_active and forms.bodies[1].entry.resource.voxels==original_b and source.voxels!=original_a,"switch finishes held stroke on original form only")
	check(not view._selection_panel.has_saved_mask(),"second form never inherits first mask")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene));history.undo();check(source.voxels==original_a,"one Undo restores held paint on previous form")
	var b_size:Vector3i=view._resource.grid_size();var b_at:int=view._resource.voxels.find(1)
	view._selection_panel.apply_history_state({"grid_size":b_size,"selected":PackedInt32Array([b_at]),"mask_indices":PackedInt32Array([b_at]),"mask_enabled":true,"mask_normal":Vector3i.UP})
	forms.select(0);check(view._selection_panel.history_state().mask_indices==first_mask and view._selection_panel.mask_normal()==Vector3i.LEFT,"first form restores its own signed mask")
	forms.select(1);check(view._selection_panel.history_state().mask_indices==PackedInt32Array([b_at]),"second form restores independent mask")
	var move_before:Dictionary=forms.capture();forms.set_position(Vector3(3,0,3));forms._record(move_before,"QA · place second form");forms.select(0)
	var old_frame:Transform3D=forms.frame(forms.active)
	var planned:Dictionary=forms.prepare_combine()
	check(not planned.has("error"),planned.get("error","union planning"))
	if planned.has("error"):print("FORMS_CYCLE_BLOCK ",planned.error);get_tree().quit(1);return
	var relative:Transform3D=planned.frame.affine_inverse()*old_frame
	var offset:=Vector3i((relative.origin*source.normalized_density()).round())
	var expected_mask:=PackedInt32Array([Model.index_of(Selection.cell_of(at,old_size)+offset,planned.source.grid_size())])
	var unchanged:Dictionary=source.to_definition(true).model.duplicate(true)
	view._forms_panel.candidate=planned;view._forms_panel.sync_preview();view._forms_panel.cancel_preview()
	check(source.to_definition(true).model==unchanged,"union preview Cancel preserves Source")
	check(forms.combine(false,false,planned),"combine prepared sources")
	check(forms.bodies.size()==1 and view._selection_panel.history_state().mask_indices==expected_mask,"union remaps active mask into new grid")
	history.undo();check(forms.bodies.size()==2 and view._selection_panel.history_state().mask_indices==first_mask and view._resource.grid_size()==old_size,"union Undo restores shape and original mask")
	history.redo();check(forms.bodies.size()==1 and view._selection_panel.history_state().mask_indices==expected_mask,"union Redo restores remapped mask")
	view._selection_panel.clear_selection();print("FORMS_CYCLE_STAGE union/history ready")
	# Choose a solid interior, carve a one-cell cavity, and crop a surrounding piece.
	var size:Vector3i=source.grid_size();var center:=Model.INVALID_CELL
	for i in source.voxels.size():
		if source.voxels[i]==0:continue
		var cell:Vector3i=Selection.cell_of(i,size)
		if cell.x<4 or cell.y<4 or cell.z<4 or cell.x>=size.x-4 or cell.y>=size.y-4 or cell.z>=size.z-4:continue
		var enclosed:=true
		for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
			if source.voxels[Model.index_of(cell+d,size)]==0:enclosed=false;break
		if enclosed:center=cell;break
	check(center!=Model.INVALID_CELL,"interior for cavity found")
	if center==Model.INVALID_CELL:get_tree().quit(1);return
	var carved:=Model.index_of(center,size);var color:int=source.voxels[carved]
	check(view._actions.apply_stroke(source,{carved:{"before":color,"after":0}}),"continue carving joined volume")
	var selected:=PackedInt32Array()
	for y in range(center.y-3,center.y+4):
		for z in range(center.z-3,center.z+4):
			for x in range(center.x-3,center.x+4):
				var i:=Model.index_of(Vector3i(x,y,z),size)
				if source.voxels[i]>0:selected.append(i)
	var painted:int=selected[0]
	check(view._actions.apply_stroke(source,{painted:{"before":int(source.voxels[painted]),"after":2 if source.voxels[painted]!=2 else 1}}),"paint joined volume before separating")
	var cropped:Dictionary=preload("res://addons/ember_import/ember_voxel_fragment_extract.gd").plan(source,selected,true)
	check(not cropped.has("error") and forms.separate(selected),"separate selected piece in same Canvas")
	check(forms.bodies.size()==2 and source.voxels[carved]==0,"remainder keeps cavity")
	forms.select(1);var piece:EmberVoxelModelResource=view._resource
	check(piece.validation_errors().is_empty(),"piece keeps valid materials and parts")
	var all:=PackedInt32Array()
	for i in piece.voxels.size():
		if piece.voxels[i]>0:all.append(i)
	view._selection_panel.set_selection(all)
	deadline=Time.get_ticks_msec()+30000
	while view._selection_panel.busy() and Time.get_ticks_msec()<deadline:await frames(1)
	var panel:Control=view._stamp_panel;var folder:="user://forms-cycle-%d"%OS.get_process_id();panel.directory=folder.path_join("presets");panel.sources=folder.path_join("models");panel._title.text="QA · carved piece"
	var piece_before:Dictionary=piece.to_definition(true).model.duplicate(true);panel._save()
	check(panel._entries.size()==1 and piece.to_definition(true).model==piece_before,"library Save preserves detached piece")
	if panel._entries.is_empty():get_tree().quit(1);return
	forms.select(0);view._actions.active_part=0;view._refresh_groups();view._show_stamp_library_mode();panel.refresh_library();panel._library.select(0);panel._place();await frames(2)
	var interaction:Control=view._selection_interaction;interaction._stamp_anchor.select(0);interaction._set_stamp_position(cropped.origin);await _forms_stamp_wait(interaction)
	check(not interaction._plan.has("error"),interaction._plan.get("error","stamp preview"))
	if interaction._plan.has("error"):get_tree().quit(1);return
	var plan:Dictionary=interaction._plan.duplicate(true);var stamp_before:=source.voxels.duplicate()
	interaction.cancel_gesture();check(source.voxels==stamp_before,"stamp Cancel leaves remainder unchanged")
	panel._place();await frames(1);interaction._stamp_anchor.select(0);interaction._set_stamp_position(cropped.origin);await _forms_stamp_wait(interaction)
	plan=interaction._plan.duplicate(true);interaction.commit()
	check(source.voxels==plan.properties.voxels and source.voxels[carved]==0,"stamp commit equals preview and preserves cavity")
	history.undo();check(source.voxels==stamp_before,"one Undo removes placed stamp");history.redo();check(source.voxels==plan.properties.voxels,"stamp Redo exact")
	interaction.cancel_gesture();check(view._actions.apply_stroke(source,{carved:{"before":0,"after":color}}),"continue sculpting after stamp")
	check(source.validation_errors().is_empty(),"final volume validates")
	var expected:=source.voxels.duplicate();check(view.save_changes(),"save entire forms cycle: "+world.sessions.error)
	var fresh:Resource=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(fresh!=null and fresh.voxels==expected and fresh.validation_errors().is_empty(),"fresh Source reopen exact")
	# Read scene topology without reloading every live @tool script and canceling
	# its suspended preparation. A cold play/reopen gate belongs in a new process.
	var packed:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE);var reopened:Node=packed.instantiate();check(reopened.get_node_or_null("Map/Props/EarthCliffCorner")!=null,"scene reopens with edited object");reopened.free()
	for look in 3:
		a.set_world_look(look);check(a.get_node("Mesh").mesh.get_faces()==a.get_node("Collision/Shape").shape.get_faces(),"cycle look%d equals physics"%look)
	view._actions.apply_stroke(source,{carved:{"before":color,"after":0}});view.discard_changes()
	check(view._resource.voxels==expected and not view.has_unsaved_changes(),"discard restores saved forms")
	view._forms_panel.show();view._return_to_last_brush();await frames(5);await RenderingServer.frame_post_draw
	var image:="user://forms-cycle-%d.png"%OS.get_process_id();EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(image))
	print("FORMS_CYCLE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"capture":ProjectSettings.globalize_path(image)}));get_tree().quit(0 if errors.is_empty() else 1)

func _forms_stamp_wait(interaction:Control)->void:
	var deadline:=Time.get_ticks_msec()+30000
	while interaction._pending and Time.get_ticks_msec()<deadline:await frames(1)
	check(not interaction._pending,"stamp preview finishes")

func _terrain_wall(importer:Node) -> void:
	const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
	var path:="res://scenes/landscape_compact.tscn";EditorInterface.open_scene_from_path(path)
	var deadline:=Time.get_ticks_msec()+120000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=path) and Time.get_ticks_msec()<deadline:await frames(1)
	var scene:=EditorInterface.get_edited_scene_root();var map:EmberMapLoader=scene.get_node("Map")
	var world:Node=importer._world_editor;world.active=true;check(world.activate_context(map),"terrain context opens")
	var entry:Dictionary=world.entry;var source:EmberTerrainPilotResource=entry.resource
	var center:=Vector2i(128,mini(640,source.depth-64));var index:=source.column_index(center.x,center.y)
	var base_height:=source.column_value("heights",index);var target:=mini(base_height+48,source.height_limit-8)
	var brush:=Brush.new();brush.configure(entry,get_undo_redo(),scene)
	check(brush.begin("level",1.5,1,1,0,16,0,7,0,source.origin_y+target,"detail","square"),"existing plateau starts")
	brush.stamp(center);brush.end()
	check(brush.begin("shape_protect",3.0,1,1,0,16,0,7,0,-99999,"detail","square",0,false,255),"existing edge protection starts")
	brush.stamp(center);brush.end()
	var projection:EmberTerrainPilotProjection=map._visual_surface_projection
	# Functional gate covers this patch, not cold preparation of the whole map.
	var local_pending:Array[Vector2i]=[]
	for key:Vector2i in projection._pending:
		if abs(key.x-center.x/64)<=1 and abs(key.y-center.y/64)<=1:local_pending.append(key)
	projection._pending.assign(local_pending);projection._reset_pending_flags()
	await _terrain_wall_wait(projection)
	var before:Resource=source.working_copy();var ray_y:=float(source.origin_y+base_height+20)
	var start:=projection.to_global(Vector3(center.x-64,ray_y,center.y+0.5));var end:=projection.to_global(Vector3(center.x,ray_y,center.y+0.5))
	var pick:Dictionary=projection.pick_ground_top(start,end,true)
	check(not pick.is_empty() and pick.normal.y<0.8,"native wall ray")
	if pick.is_empty():get_tree().quit(1);return
	var slot:=1
	for i in range(1,source.palette.size()):
		if source.surface_role_for_palette(i)=="stone":slot=i;break
	check(brush.begin("paint",0.6,1,slot,0,16,0,7,0),"side paint starts")
	brush.stamp_surface(pick);brush.end();await _terrain_wall_wait(projection)
	var edited:Resource=source.working_copy()
	check(not source.same_terrain_data(before) and source.same_terrain_data(projection.document) and source.validation_errors().is_empty(),"native side changes Source and preview")
	check(source.column_value("heights",index)==target and source.column_value("top_materials",index)==before.column_value("top_materials",index),"plateau and top remain")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await _terrain_wall_wait(projection);check(source.same_terrain_data(before) and source.same_terrain_data(projection.document),"native side Undo")
	history.redo();await _terrain_wall_wait(projection);check(source.same_terrain_data(edited) and source.same_terrain_data(projection.document),"native side Redo")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1000,700);viewport.world_3d=scene.get_world_3d();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var cam:=Camera3D.new();viewport.add_child(cam);cam.current=true
	cam.global_position=projection.to_global(pick.local+Vector3(-64,48,64));cam.far=4000;cam.look_at(pick.world)
	world._category_changed(1,true,"paint");world.camera=cam
	var routed:Dictionary=world._pick_compact(cam.unproject_position(pick.world))
	check(not routed.is_empty() and routed.get("normal",Vector3.UP).y<0.8,"world paint routes wall pick")
	world.hover=routed;world.radius.value=0.6;world._update_overlay()
	check(world._compact_grid_material.get_shader_parameter("side_paint")==true,"GPU wall brush overlay enabled")
	world._clear_compact_grid_overlay()
	var captures:Array=[]
	for look in 3:
		projection.set_world_look(look);projection._look_pending.clear()
		for z in range((center.y-32)/64,(center.y+32)/64+1):
			for x in range((center.x-32)/64,(center.x+32)/64+1):
				var key:=Vector2i(x,z)
				if projection._look_meshes.has(key):projection._apply_tile_look(key)
		await frames(5);await RenderingServer.frame_post_draw
		var image:="user://terrain-wall-%d-%d.png"%[OS.get_process_id(),look]
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(image));captures.append(ProjectSettings.globalize_path(image))
	projection.set_world_look(0);projection._look_pending.clear()
	check(world.save_all(),"native terrain save: "+str(world.sessions.error))
	var reopened=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened!=null and reopened.validation_errors().is_empty() and reopened.same_terrain_data(edited),"fresh terrain reopens")
	check(brush.begin("paint",0.6,1,1 if slot!=1 else 2,0,16,0,7,0),"unsaved side edit begins")
	brush.stamp_surface(pick);brush.end();world.sessions.discard(scene);await _terrain_wall_wait(projection)
	check(entry.resource.same_terrain_data(edited),"session Discard restores side paint")
	viewport.queue_free();history.clear_history()
	print("TERRAIN_WALL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"captures":captures,"slot":slot}));get_tree().quit(0 if errors.is_empty() else 1)

func _terrain_wall_wait(projection:EmberTerrainPilotProjection) -> void:
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		if projection.pending_tile_count()==0:return
	check(false,"local terrain preparation timeout")
