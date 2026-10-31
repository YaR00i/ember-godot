extends SceneTree
## Focused continuous Canvas scenario; all publication is under user://.
const Workspace=preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Registry=preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Edit=preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Shapes=preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Profiles=preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
var errors:Array[String]=[]
var scene:Node3D
var folder:="user://canvas-forms-%d"%Time.get_ticks_usec()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("CANVAS_FORMS_FAIL ",label)
func fields(source:Resource)->Dictionary:
	var result:Dictionary={}
	for key in Registry.FIELDS:
		if key!="model_id":result[key]=EmberVoxelModelResource.copy_authoring_value(source.get(key))
	return result
func frames(count:int)->void:
	for i in count:await process_frame
func save_scene()->int:
	for node in scene.get_children():
		if node is EmberVoxelProp:node._notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed:=PackedScene.new();var result:=packed.pack(scene)
	if result==OK:result=ResourceSaver.save(packed,scene.scene_file_path)
	for node in scene.get_children():
		if node is EmberVoxelProp:node._notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	return result
func run()->void:
	if "--forms-guard-math" in OS.get_cmdline_user_args():forms_guard_math();return
	if "--shared-mask-math" in OS.get_cmdline_user_args():shared_mask_math();return
	if DisplayServer.get_name()=="headless":printerr("Canvas forms requires Forward+");quit(2);return
	Engine.max_fps=60;root.size=Vector2i(1440,960)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var source:EmberVoxelModelResource=Shapes.build("block",Vector3i(16,16,16),16,Color("77838a"),"base","Основа").source
	source.palette.append(Color("886243"));source.palette.append(Color("638646"))
	source.merge_parts=PackedStringArray(["Основа"]);source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1)
	source.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","stone","soil","grass"]),"material_ids":PackedStringArray(["","cartoon_stone","soil_grain","cartoon_grass"]),"occupancy":Solid.occupancy_hash(source.voxels)}
	var packed:=EmberVoxelPrefab.prepare_resource(source)
	var installed:=Edit.Store.install_prepared_asset(source,packed,folder.path_join("base.tres"),folder.path_join("base.tscn"))
	check(installed.ok,"fixture publication")
	scene=Node3D.new();scene.name="CanvasFormsFixture";scene.scene_file_path=folder.path_join("scene.tscn");root.add_child(scene)
	var prop:=installed.packed.instantiate() as EmberVoxelProp;prop.authoring_source=source;scene.add_child(prop);prop.owner=scene
	var scene_commands:bool="--scene-commands" in OS.get_cmdline_user_args()
	if scene_commands:prop.rotation_degrees.y=90
	var history:=UndoRedo.new();var edit:=Edit.new();edit.source_directory=folder;edit.prefab_directory=folder
	check(edit.open(prop,scene,history),edit.error)
	var registry:=Registry.new();registry.source_directory=folder;registry.prefab_directory=folder;registry.recovery_directory=folder.path_join("recovery");registry.configure(history,save_scene)
	var view:=Workspace.new();view.setup(null,history);view.configure_forms(registry,func():return registry.save_all(scene))
	root.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);view.open_object(edit);await frames(3)
	view._depth.value=3;view._yaw=0.7;view._pitch=-0.6;view._update_camera()
	var yaw:=view._yaw;var pitch:=view._pitch;var radius:=view._radius.selected;var depth:=view._depth.value
	var original:=fields(view._resource)
	var paint:={Model.index_of(Vector3i(2,8,15),source.grid_size()):{"before":1,"after":2}}
	check(view._actions.apply_stroke(view._resource,paint),"dirty paint before enabling forms")
	view._enable_canvas_forms();var forms:RefCounted=view._canvas_forms
	check(forms!=null,"native forms controller connected")
	if "--lifecycle-only" in OS.get_cmdline_user_args():
		await lifecycle(view,registry,history)
		return
	if "--interaction-recovery" in OS.get_cmdline_user_args():
		await interaction_recovery(view,registry,history)
		return
	var painted:=fields(view._resource)
	var camera_world:Vector3=forms.frame(forms.active)*view._camera_target
	if scene_commands:
		var peer:=installed.packed.instantiate() as EmberVoxelProp;peer.authoring_source=source;scene.add_child(peer);peer.owner=scene;peer.global_position=Vector3(8.25,0,0)
		check(view.open_scene_forms([prop,peer]),"scene selection enters current Canvas")
		check(view.open_scene_forms([peer,prop]) and view._canvas_forms==forms and forms.bodies.size()==2,"repeat command reuses bodies and dirty draft")
		check(not view._forms_panel.bake_orientation.button_pressed,"orientation baking remains opt-in")
		var selection:Control=view._selection_panel
		selection.set_selection(PackedInt32Array([0]),Color.CYAN,Vector3i.UP)
		selection._mask.button_pressed=true
		view._activate_tool_id(Model.TOOL_PAINT)
		check(selection._mask_kind==Profiles.MASK_VOXELS and selection.allows_brush_index(0) and not selection.allows_brush_index(1),"paint mask is exact and labelled")
		view._activate_tool_id(Model.TOOL_ADD)
		check(selection._mask_kind==Profiles.MASK_COLUMNS and selection.allows_brush_index(Model.index_of(Vector3i.UP,view._resource.grid_size())),"add uses displayed face footprint")
		view._activate_tool_id(Model.TOOL_SMOOTH)
		check(selection._mask_kind==Profiles.MASK_VOXELS and view._tool.get_item_text(view._find_tool_item(Model.TOOL_SMOOTH)).contains("объём"),"volume Smooth context and mask agree")
		view._activate_tool_id(Model.TOOL_GRAB)
		check(selection.has_saved_mask() and not selection.mask_brushes_enabled() and selection._mask.text.contains("недоступна"),"Grab explicitly suspends saved mask")
		selection.clear_selection();view._activate_tool_id(Model.TOOL_ADD)
		check(not Profiles.world_modes(0,true).has("add") and Profiles.world_modes(0,false).has("add"),"heightfield and volume expose their actual capabilities")
	else:check(forms.add_shape("sphere"),forms.error)
	check(forms.bodies.size()==2 and registry.entries.size()==2,"two drafts in same registry")
	check(forms.bodies[0].entry.resource.voxels[Model.index_of(Vector3i(2,8,15),source.grid_size())]==2,"unsaved paint survives add")
	check(DirAccess.get_files_at(folder).size()==2,"new form has no asset files")
	check(camera_world.distance_to(forms.frame(forms.active)*view._camera_target)<0.001,"camera retained on form switch")
	if not scene_commands:
		history.undo();check(forms.bodies.size()==1 and fields(view._resource)==painted,"one Undo removes added form without losing paint")
		history.redo();check(forms.bodies.size()==2,"Redo restores added form")
	forms.set_position(Vector3(0.5,0.5,0.5))
	var position_state:Dictionary=forms.capture();var builds:int=forms.mesh_builds
	for i in 6:forms.set_position(Vector3(0.5+i/16.0,0.5,0.5))
	check(forms.mesh_builds==builds,"moving uses cached geometry")
	forms.apply_history_state(position_state)
	if "--capture" in OS.get_cmdline_user_args():
		await frames(8);await RenderingServer.frame_post_draw
		var image_path:=folder.path_join("canvas.png");root.get_texture().get_image().save_png(ProjectSettings.globalize_path(image_path));print("CANVAS_CAPTURE ",ProjectSettings.globalize_path(image_path))
	forms.select(0)
	if scene_commands:
		var panel:Control=view._forms_panel;panel.align_grid.button_pressed=true;panel.bake_orientation.button_pressed=true
		var prepare:Button
		for button in panel.find_children("*","Button",true,false):
			if button.text=="Предпросмотр":prepare=button;break
		var prior:Dictionary=forms.capture(forms.bodies)
		prepare.pressed.emit();check(not panel.candidate.is_empty() and forms.capture(forms.bodies)==prior and not view._surface_root.visible,"detached exact union preview does not mutate forms")
		panel.cancel.pressed.emit();check(panel.candidate.is_empty() and forms.capture(forms.bodies)==prior and view._surface_root.visible,"preview Cancel restores live forms")
		prepare.pressed.emit();var stale:Dictionary=panel.candidate
		var position:Vector3=forms.position_of(forms.active);forms.set_position(position+Vector3.RIGHT/16.0)
		check(panel.candidate.is_empty() and not forms.combine(true,true,stale),"pose change removes stale preview and rejects its commit")
		forms.set_position(position);prepare.pressed.emit()
		var expected:Dictionary=fields(panel.candidate.source)
		panel.join.pressed.emit();check(fields(view._resource)==expected,"UI commit exactly matches prepared union")
	else:check(forms.combine(),forms.error)
	check(forms.bodies.size()==1 and Solid.uses_volume(EmberVoxelPrefab.model_of(view._resource.to_definition())),"union stays in Canvas volume renderer")
	var united:=fields(view._resource)
	history.undo();check(forms.bodies.size()==2 and fields(view._resource)==painted,"one Undo restores two forms and dirty paint")
	history.redo();check(forms.bodies.size()==1 and fields(view._resource)==united,"Redo exact union")
	if scene_commands:
		check(forms.separate_parts() and forms.bodies.size()==2,"part separation uses same Canvas")
		history.undo();check(forms.bodies.size()==1 and fields(view._resource)==united,"part separation Undo restores union")
		history.redo();check(forms.bodies.size()==2,"part separation Redo restores pieces")
		history.undo()
	check(view._yaw==yaw and view._pitch==pitch and view._radius.selected==radius and view._depth.value==depth,"camera angles and brush unchanged")
	var center:=Vector3i(2,8,15)
	var changes:=Model.oriented_stroke_changes(view._resource,view._resource.voxels,center,Vector3i(0,0,1),Model.TOOL_REMOVE,1,2,4)
	check(view._actions.apply_stroke(view._resource,changes),"continue carving after union without Save")
	var carved:=fields(view._resource)
	var indices:=PackedInt32Array()
	for i in view._resource.voxels.size():
		if view._resource.voxels[i]>0 and Model.index_of(Vector3i(0,0,0),view._resource.grid_size())<=i:
			indices.append(i)
			if indices.size()==32:break
	check(forms.separate(indices),forms.error)
	check(forms.bodies.size()==2,"separated piece stays in same Canvas")
	var separated:=fields(view._resource)
	history.undo();check(forms.bodies.size()==1 and fields(view._resource)==carved,"one Undo restores detached cells")
	history.redo();check(forms.bodies.size()==2 and fields(view._resource)==separated,"Redo exact separation")
	check(view.save_changes(),registry.error)
	check(not view.has_unsaved_changes(),"whole composition clean after Save")
	for entry in registry.entries.values():
		check(not entry.path.is_empty() and not entry.get("created",false),"each saved form has a canonical asset")
		var reopened:=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
		check(fields(reopened)==fields(entry.resource),"reopen retains each form and paint")
	var saved_count:int=forms.bodies.size();var saved_data:=fields(view._resource)
	for look in 3:
		for body in forms.bodies:
			body.node.set_world_look(look)
			var visual:=body.node.get_node("Mesh") as MeshInstance3D
			check(body.node.get_node("Collision/Shape").shape.get_faces()==visual.mesh.get_faces(),"visible geometry equals physics look%d"%look)
	check(forms.add_shape("block"),forms.error)
	view.discard_changes()
	check(forms.bodies.size()==saved_count and fields(view._resource)==saved_data and not view.has_unsaved_changes(),"Discard restores whole saved composition")
	var restored:Node=ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate();root.add_child(restored)
	check(restored.get_child_count()==saved_count,"reopened scene retains all forms")
	print("CANVAS_FORMS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"saved_forms":saved_count,"mesh_builds":forms.mesh_builds}))
	view.free();history.clear_history();registry.release();restored.free();scene.free();quit(0 if errors.is_empty() else 1)

func pointer(view:Control,position:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=position;event.pressed=pressed
	view._on_viewport_input(event)
func lifecycle(view:Control,registry:RefCounted,history:UndoRedo)->void:
	var forms:RefCounted=view._canvas_forms
	check(forms.add_shape("sphere"),forms.error)
	var base=forms.bodies[0];var old_mesh:ArrayMesh=forms.mesh_for(base)
	base.entry.resource.voxels[0]=3;base.entry.resource.notify_geometry_changed(PackedInt32Array([0]))
	check(forms.mesh_for(base)!=old_mesh,"inactive mesh refreshes after geometry history change")
	view.open_world_draft(base.entry,registry,func():return registry.save_all(scene));view._enable_canvas_forms()
	check(view._canvas_forms==forms and forms.bodies.size()==2,"reopen reuses existing unsaved Canvas group")
	check(view.save_changes(),registry.error)
	for body in forms.bodies:
		check(not is_instance_valid(body.entry.preview),"saved presentation has no draft overlay")
		var faces:Array=[]
		for look in 3:
			body.node.set_world_look(look)
			var mesh:ArrayMesh=body.node.get_node("Mesh").mesh
			faces.append(mesh.get_faces())
			check(body.node.get_node("Collision/Shape").shape.get_faces()==mesh.get_faces(),"saved look/physics %d"%look)
		check(faces[2]!=faces[0],"voxel and detailed positions are distinct")
	var data:=fields(view._resource)
	forms.set_position(forms.position_of(forms.active)+Vector3.RIGHT*0.25)
	check(registry.dirty_count(scene)>0,"pose-only draft participates in native save status")
	check(view.save_changes() and not view.has_unsaved_changes(),"pose-only save establishes new baseline")
	check(fields(view._resource)==data,"pose-only save preserves Source")
	print("CANVAS_FORMS_LIFECYCLE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	view.free();history.clear_history();registry.release();scene.free();quit(0 if errors.is_empty() else 1)
func motion(view:Control,position:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.position=position
	view._on_viewport_input(event)
func screen_center(view:Control)->Vector2:
	return view._camera.unproject_position(Vector3.ONE*0.5)*view._viewport_container.size/Vector2(view._viewport.size)
func interaction_recovery(view:Control,registry:RefCounted,history:UndoRedo)->void:
	check(save_scene()==OK,"saved baseline scene")
	var forms:RefCounted=view._canvas_forms
	check(forms.add_shape("sphere"),forms.error)
	view._forms_panel.mode.button_pressed=true;view._fit_camera_to_surface();await frames(4)
	var start:Vector3=forms.position_of(forms.active);var screen:=screen_center(view)
	var builds:int=forms.mesh_builds;var version:=history.get_version()
	pointer(view,screen,true);check(forms.moving,"native input picks added form")
	check(not view.save_changes(),"save blocked during held move")
	motion(view,screen+Vector2(65,10));var moved:Vector3=forms.position_of(forms.active)
	check(moved!=start,"native input visibly moves form")
	check(history.get_version()==version,"held move is not committed")
	pointer(view,screen+Vector2(65,10),false)
	check(not forms.moving and forms.mesh_builds==builds,"release finishes without remesh")
	history.undo();check(forms.position_of(forms.active).is_equal_approx(start),"one Undo restores gesture pose")
	history.redo();check(forms.position_of(forms.active).is_equal_approx(moved),"Redo restores gesture pose")
	screen=screen_center(view);version=history.get_version()
	pointer(view,screen,true);motion(view,screen+Vector2(30,0))
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;view._on_viewport_input(escape)
	check(not forms.moving and forms.position_of(forms.active).is_equal_approx(moved) and history.get_version()==version,"Esc cancels held move without history")
	view._forms_panel.mode.button_pressed=false
	forms.set_position(Vector3(0.5,0.5,0.5))
	check(forms.combine(),forms.error) # active new shape absorbs the saved original
	var indices:=PackedInt32Array()
	for i in view._resource.voxels.size():
		if view._resource.voxels[i]>0:
			indices.append(i)
			if indices.size()==32:break
	check(forms.separate(indices),forms.error)
	var expected:Array=[]
	for body in forms.bodies:expected.append({"data":fields(body.entry.resource),"pose":body.node.transform})
	registry.write_recovery()
	var recovery:String=registry.recovery_directory
	view.free();history.clear_history();registry.release();forms=null;registry=null;scene.free()
	scene=ResourceLoader.load(folder.path_join("scene.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	for child in scene.get_children():
		if child is EmberVoxelProp:child.authoring_source=load(folder.path_join(child.model_id+".tres"))
	root.add_child(scene)
	registry=Registry.new();registry.source_directory=folder;registry.prefab_directory=folder;registry.recovery_directory=recovery;registry.configure(history,save_scene)
	check(registry.restore_recovery(scene)==2,"recovery restores created union and separated piece")
	check(scene.get_child_count()==2,"recovery removes absorbed original without duplication")
	for want in expected:
		var matched:=false
		for entry in registry.entries.values():
			if fields(entry.resource)==want.data and entry.target.get_ref().transform==want.pose:matched=true
		check(matched,"recovery retains geometry paint and pose")
	view=Workspace.new();view.setup(null,history);root.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.open_world_draft(registry.entries.values()[0],registry,func():return registry.save_all(scene));view._enable_canvas_forms()
	check(view._canvas_forms.bodies.size()==2,"recovery reopens whole Canvas group")
	view.discard_changes()
	check(scene.get_child_count()==1 and not view.has_unsaved_changes(),"discard after recovery restores saved original")
	print("CANVAS_FORMS_INPUT_RECOVERY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"remesh_during_move":forms.mesh_builds if forms!=null else 0}))
	view.free();history.clear_history();registry.release();scene.free();quit(0 if errors.is_empty() else 1)

func shared_mask_math()->void:
	const Selection=preload("res://addons/ember_import/ember_voxel_selection.gd")
	var size:=Vector3i(4,4,4);var cell:=Vector3i(1,1,1);var index:=Model.index_of(cell,size)
	for normal in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
		var state:Dictionary={"selection":{"grid_size":size,"mask_indices":PackedInt32Array([index]),"mask_enabled":true,"mask_normal":normal},"region":Rect2i(),"height":-1}
		for kind in ["voxels","columns"]:
			var guard:=Selection.compile_brush_guard(state,size,kind)
			for i in 64:
				var point:Vector3i=Selection.cell_of(i,size);var axis:int=Selection.mask_axis(normal)
				var expected:bool=i==index if kind=="voxels" else (point.y==1 and point.z==1 if axis==0 else point.x==1 and point.z==1 if axis==1 else point.x==1 and point.y==1)
				check(Selection.guard_allows(i,size,guard,1)==expected,"shared membership "+kind)
		state.region=Rect2i(0,0,2,2);state.height=2
		var guarded:=Selection.compile_brush_guard(state,size,"columns")
		for i in 64:
			var p:Vector3i=Selection.cell_of(i,size)
			if Selection.guard_allows(i,size,guarded,1):check(p.x<2 and p.z<2 and p.y<2,"scope and cut intersect mask")
		state.selection.grid_size=Vector3i.ONE
		check(Selection.compile_brush_guard(state,size,"voxels").invalid,"changed grid rejected")
	var malformed:=Selection.compile_brush_guard({"selection":{"grid_size":size,"mask_enabled":true,"mask_indices":PackedInt32Array()}},size,"voxels")
	check(malformed.invalid and not Selection.guard_allows(index,size,malformed,1),"empty enabled mask fails closed")
	check(Selection.guard_allows(index,size,{},1),"no guard preserves existing brush")
	print("SHARED_MASK_MATH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)

func forms_guard_math()->void:
	const Selection=preload("res://addons/ember_import/ember_voxel_selection.gd")
	var old:=Vector3i(32,32,32);var size:=Vector3i(64,48,32);var cell:=Vector3i(2,3,4);var offset:=Vector3i(16,2,0)
	var state:Dictionary={"selection":{"grid_size":old,"selected":PackedInt32Array([Model.index_of(cell,old)]),"mask_indices":PackedInt32Array([Model.index_of(cell,old)]),"mask_enabled":true,"mask_normal":Vector3i.LEFT},"region":Rect2i(0,0,1,1),"height":8}
	var before:=state.duplicate(true);var result:=Selection.translate_brush_guard(state,old,size,offset,16)
	check(not result.has("error"),"aligned guard translation succeeds")
	check(result.guard.selection.mask_indices==PackedInt32Array([Model.index_of(cell+offset,size)]) and result.guard.selection.grid_size==size,"mask follows new grid")
	check(result.guard.region==Rect2i(1,0,1,1) and result.guard.height==10,"scope and cut follow same origin")
	check(state==before,"guard planning immutable")
	check(Selection.translate_brush_guard(state,old,size,Vector3i(1,0,0),16).has("error"),"fractional block scope fails before mutation")
	state.selection.grid_size=Vector3i.ONE
	check(Selection.translate_brush_guard(state,old,size,offset,16).has("error"),"stale mask fails before mutation")
	check(Selection.translate_brush_guard({},old,size,offset,16)=={"guard":{}},"unrestricted new form stays unrestricted")
	state.selection.mask_enabled=false;state.region=Rect2i();state.height=-1
	check(Selection.translate_brush_guard(state,old,size,offset,16)=={"guard":{}},"stale inactive selection does not block unrestricted form")
	print("FORMS_GUARD_MATH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
