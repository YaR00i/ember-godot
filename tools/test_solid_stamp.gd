extends SceneTree
const Stamp=preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions=preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Workspace=preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Registry=preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Edit=preload("res://addons/ember_import/ember_voxel_object_session.gd")
var errors:Array[String]=[]
var folder:="user://solid-stamp-%d"%Time.get_ticks_usec()
var scene:Node3D
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("SOLID_STAMP_FAIL ",label)
func data(source:EmberVoxelModelResource)->Dictionary:return source.to_definition(true).model
func cell(p:Vector3i,size:Vector3i)->int:return Model.index_of(p,size)
func fixture(id:String,artwork:String,notch:=false)->EmberVoxelModelResource:
	var source:=EmberVoxelModelResource.new();source.model_id=id;source.display_name=id;source.voxels_per_block=16;source.size_blocks=Vector3i(2,1,2);source.height_voxels=24
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("77838a"),Color("89654b"),Color("78974e")])
	source.merge_parts=PackedStringArray(["Основа"])
	source.voxels.resize(32*24*32);source.voxel_part_ids.resize(source.voxels.size())
	for y in 8:
		for z in 8:
			for x in 8:
				if notch and x>=2 and x<5 and y>=2 and y<6 and z<4:continue
				var index:=cell(Vector3i(x,y,z),source.grid_size());source.voxels[index]=1 if y<3 else 2 if y<6 else 3;source.voxel_part_ids[index]=1
	source.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,Vector3(1,2,0).normalized()])],"roles":PackedStringArray(["","stone","soil","grass"]),"material_ids":PackedStringArray(["",artwork,"soil_grain","cartoon_grass"]),"occupancy":Solid.occupancy_hash(source.voxels)}
	return source
func indices(source:EmberVoxelModelResource)->PackedInt32Array:
	var selected:=PackedInt32Array()
	for index in source.voxels.size():
		if source.voxels[index]>0:selected.append(index)
	return selected
func applied(source:EmberVoxelModelResource,plan:Dictionary)->EmberVoxelModelResource:
	var next:=source.duplicate_model()
	for key in plan.properties:next.set(key,EmberVoxelModelResource.copy_authoring_value(plan.properties[key]))
	return next
func run()->void:
	if "--native" in OS.get_cmdline_user_args():await native();return
	var source:=fixture("Кусок уступа","cartoon_sand",true);var source_before:=data(source)
	var captured:=Stamp.capture(source,indices(source),"Уступ · фрагмент")
	check(not captured.has("error"),captured.get("error","capture"))
	if captured.has("error"):quit(1);return
	var preset:Resource=captured.preset
	check(preset.geometry.validation_errors().is_empty() and Solid.active(data(preset.geometry)),"capture retains solid profile and parts")
	var saved:=Stamp.save_new(preset,folder.path_join("presets"),folder.path_join("models"))
	check(not saved.has("error"),saved.get("error","library save"))
	if saved.has("error"):quit(1);return
	var loaded:Resource=ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(Stamp.library(folder.path_join("presets")).size()==1 and data(loaded.geometry)==data(ResourceLoader.load(loaded.geometry.resource_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)),"library external Source roundtrip")
	var target:=fixture("Цель","cartoon_stone");var before:=data(target)
	var plan:=Stamp.plan(target,loaded,Vector3i(10,5,10),1,0,-1,0,false,0)
	check(not plan.has("error"),plan.get("error","placement"))
	if plan.has("error"):quit(1);return
	var result:=applied(target,plan)
	check(result.validation_errors().is_empty() and Solid.active(data(result)),"placement is a valid owned solid volume")
	check(result.palette.size()==target.palette.size()+1,"same RGB with different artwork remains a distinct material")
	var slot:int=result.voxels[cell(Vector3i(10,5,10),result.grid_size())]
	check(slot!=1 and result.palette[slot]==target.palette[1] and result.solid_surface.material_ids[slot]=="cartoon_sand" and result.solid_surface.material_ids[1]=="cartoon_stone","stamp and host artwork identities retained")
	check(result.merge_parts.size()==2 and result.voxel_part_ids[cell(Vector3i(10,5,10),result.grid_size())]==2,"unassigned placement creates an owned stamp part")
	check(result.voxels[cell(Vector3i(12,7,10),result.grid_size())]==0,"captured cavity survives placement")
	check(data(source)==source_before and data(target)==before,"planning and capture do not mutate author data")
	var history:=UndoRedo.new();var actions:=Actions.new();actions.configure(history);actions.active_part=int(plan.active_part)
	check(actions.apply_fragment(target,plan),"existing fragment commit")
	var committed:=data(target);history.undo();check(data(target)==before,"one Undo restores material table parts and geometry")
	history.redo();check(data(target)==committed,"Redo exact")
	var carve:=Model.oriented_stroke_changes(target,target.voxels,Vector3i(10,5,10),Vector3i.FORWARD,Model.TOOL_REMOVE,1,1,2)
	check(actions.apply_stroke(target,carve),"continue carving placed stamp")
	history.undo();check(data(target)==committed,"carve Undo restores stamp")
	var paint:=Model.oriented_stroke_changes(target,target.voxels,Vector3i(11,6,10),Vector3i.FORWARD,Model.TOOL_PAINT,3,1,1)
	check(actions.apply_stroke(target,paint),"continue painting placed stamp")
	history.undo();check(data(target)==committed,"paint Undo retains artwork table")
	for mesh in [Solid.build(data(target)),Solid.living_mesh(data(target),1.0,PackedFloat32Array()),Solid.build_voxel_look(data(target))]:
		check(mesh.get_surface_count()>0 and not mesh.get_faces().is_empty(),"all three solid looks build")
	var rotated:=Stamp.plan(fixture("Поворот","cartoon_stone"),loaded,Vector3i(10,5,10),2,1,0,0,false,0)
	check(not rotated.has("error"),rotated.get("error","rotation/mirror"))
	if not rotated.has("error"):
		var next:=applied(fixture("Поворот","cartoon_stone"),rotated);var found:=false
		for normal:Vector3 in next.solid_surface.parts[1]:
			if normal.is_equal_approx(Vector3(-2,-1,0).normalized()):found=true
		check(found and next.validation_errors().is_empty(),"guides follow rotated mirrored geometry")
	var explicit:=Stamp.plan(fixture("Явная часть","cartoon_stone"),loaded,Vector3i(10,5,10),1,0,-1,0,false,1)
	check(not explicit.has("error") and not explicit.properties.has("merge_parts"),"explicit existing part retained")
	var indent:=Stamp.plan_many(fixture("Вдавить","cartoon_stone"),loaded,[Vector3i(0,7,0)],1,0,-1,0,false,0,Rect2i(),-1,PackedInt32Array(),Vector3i.UP,false,2,true)
	check(not indent.has("error") and not indent.properties.has("palette") and not indent.properties.has("solid_surface"),"indent retains host material identity")
	var plain:=fixture("Обычный","cartoon_stone");plain.solid_surface={};plain.merge_parts=PackedStringArray();plain.voxel_part_ids=PackedInt32Array()
	check(Stamp.plan(plain,loaded,Vector3i(10,5,10),1,0,-1,0,false,0).has("error"),"mixed representation rejected without loss")
	var full:=fixture("Лимит частей","cartoon_stone")
	for i in 31:full.merge_parts.append("Часть%d"%i);full.solid_surface.parts.append(full.solid_surface.parts[0].duplicate())
	var full_before:=data(full).duplicate(true)
	check(Stamp.plan(full,loaded,Vector3i(10,5,10),1,0,-1,0,false,0).has("error") and data(full)==full_before,"part limit refuses without partial mutation")
	var full_palette:=fixture("Лимит палитры","cartoon_stone")
	while full_palette.palette.size()<256:
		full_palette.palette.append(Color.MAGENTA);full_palette.solid_surface.roles.append("stone");full_palette.solid_surface.material_ids.append("cartoon_stone")
	var palette_before:=data(full_palette).duplicate(true)
	check(Stamp.plan(full_palette,loaded,Vector3i(10,5,10),1,0,-1,0,false,0).has("error") and data(full_palette)==palette_before,"palette limit refuses without material loss")
	var path:=folder.path_join("placed.tres");check(ResourceSaver.save(target,path)==OK,"save placed volume")
	check(data(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP))==committed,"fresh reopen exact")
	history.clear_history();print("SOLID_STAMP ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"palette":target.palette.size(),"parts":target.merge_parts.size()}));quit(0 if errors.is_empty() else 1)

func frames(count:int)->void:
	for i in count:await process_frame
func save_scene()->int:
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed:=PackedScene.new();var result:=packed.pack(scene)
	if result==OK:result=ResourceSaver.save(packed,scene.scene_file_path)
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE);return result
func settle(interaction:Control)->void:
	for i in 180:
		if not interaction._pending:return
		await process_frame
	check(false,"stamp preview preparation finishes")
func native()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=60;root.size=Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("models")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("prefabs")))
	var source:=ResourceLoader.load("res://content/voxel_models/vox_earth_cliff_straight.tres","",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(source!=null,"existing main cliff Source available")
	if source==null:quit(1);return
	source=source.duplicate_model();source.model_id="solid_stamp_native_source"
	var size:=source.grid_size();var selected:=PackedInt32Array()
	for y in size.y:
		for z in range(maxi(0,int(size.z/2)-4),mini(size.z,int(size.z/2)+4)):
			for x in range(maxi(0,int(size.x/2)-16),mini(size.x,int(size.x/2)+16)):
				var at:=cell(Vector3i(x,y,z),size)
				if source.voxels[at]>0:selected.append(at)
	check(not selected.is_empty() and selected.size()<=32768,"bounded real cliff selection")
	var target:=fixture("solid_stamp_native_target","cartoon_stone")
	target.palette=source.palette.duplicate();target.material=source.material.duplicate(true)
	target.size_blocks=Vector3i(4,1,4);target.height_voxels=mini(128,size.y+16)
	target.voxels=PackedByteArray();target.voxels.resize(64*64*target.height_voxels)
	target.voxel_part_ids=PackedInt32Array();target.voxel_part_ids.resize(target.voxels.size())
	target.solid_surface.roles=source.solid_surface.roles.duplicate();target.solid_surface.material_ids=source.solid_surface.material_ids.duplicate()
	for y in 12:
		for z in 32:
			for x in 32:
				var at:=cell(Vector3i(x,y,z),target.grid_size());target.voxels[at]=1 if y<6 else 2 if y<10 else 3;target.voxel_part_ids[at]=1
	var models:=folder.path_join("models");var prefabs:=folder.path_join("prefabs")
	var source_asset:=Edit.Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),models.path_join(source.model_id+".tres"),prefabs.path_join(source.model_id+".tscn"))
	var target_asset:=Edit.Store.install_prepared_asset(target,EmberVoxelPrefab.prepare_resource(target),models.path_join(target.model_id+".tres"),prefabs.path_join(target.model_id+".tscn"))
	check(source_asset.ok and target_asset.ok,"native fixture publication")
	scene=Node3D.new();scene.name="SolidStampFixture";scene.scene_file_path=folder.path_join("scene.tscn");root.add_child(scene)
	var source_prop:=source_asset.packed.instantiate() as EmberVoxelProp;source_prop.authoring_source=source;scene.add_child(source_prop);source_prop.owner=scene;source_prop.position.x=-160
	var prop:=target_asset.packed.instantiate() as EmberVoxelProp;prop.authoring_source=target;scene.add_child(prop);prop.owner=scene
	var history:=UndoRedo.new();var registry:=Registry.new();registry.source_directory=models;registry.prefab_directory=prefabs;registry.recovery_directory=folder.path_join("recovery");registry.configure(history,save_scene)
	var view:=Workspace.new();view.setup(null,history);root.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source_entry:Dictionary=registry.open_object(source_prop,scene)
	view.open_world_draft(source_entry,registry,func():return registry.save_all(scene));view._enable_canvas_forms()
	var untouched:=data(view._resource).duplicate(true)
	view._selection_panel.set_selection(selected)
	for i in 600:
		if not view._selection_panel.busy():break
		await process_frame
	var panel:Control=view._stamp_panel;panel.directory=folder.path_join("presets");panel.sources=models;panel._title.text="Уступ · сохранённый фрагмент"
	panel._save();check(panel._entries.size()==1,"native Save puts cliff fragment into existing library: "+view._status.text)
	if panel._entries.size()!=1:view.free();history.clear_history();registry.release();scene.free();quit(1);return
	check(data(view._resource)==untouched,"library Save preserves original cliff draft")
	var entry:Dictionary=registry.open_object(prop,scene)
	view.open_world_draft(entry,registry,func():return registry.save_all(scene));view._enable_canvas_forms()
	view._actions.active_part=0;view._refresh_groups();view._show_stamp_library_mode()
	panel.refresh_library();panel._library.select(0);panel._place();await frames(2)
	var interaction:Control=view._selection_interaction
	interaction._stamp_anchor.select(0);interaction._set_stamp_position(Vector3i(20,8,12));await settle(interaction)
	check(not interaction._plan.has("error") and not interaction._apply.disabled,interaction._plan.get("error","native detached preview"))
	if not interaction._plan.has("properties"):view.free();history.clear_history();registry.release();scene.free();quit(1);return
	var before:=data(view._resource).duplicate(true);var plan:Dictionary=interaction._plan.duplicate(true)
	var expected:=data(applied(view._resource,plan)).duplicate(true)
	check(data(view._resource)==before and interaction._ghost.visible,"preview is detached")
	interaction.cancel_gesture();check(data(view._resource)==before,"cancel preserves target")
	panel._place();await frames(1);interaction._stamp_anchor.select(0);interaction._set_stamp_position(Vector3i(20,8,12));await settle(interaction)
	interaction.commit();check(data(view._resource)==expected,"native commit equals preview including materials")
	check(view._actions.active_part>0 and view._part_selector.item_count==view._resource.merge_parts.size()+1,"continue sculpting has a valid selected part")
	interaction.cancel_gesture();history.undo();check(data(view._resource)==before,"native one Undo removes only the stamp")
	check(view._part_selector.item_count==view._resource.merge_parts.size()+1,"part UI follows Undo")
	history.redo();check(data(view._resource)==expected,"native Redo exact")
	check(view._part_selector.item_count==view._resource.merge_parts.size()+1,"part UI follows Redo")
	var additions:=PackedInt32Array()
	for at in plan.selected:
		var p:=Stamp.Fragment.Selection.cell_of(at,view._resource.grid_size())+Vector3i.UP
		if Model.contains(p,view._resource.grid_size()) and view._resource.voxels[cell(p,view._resource.grid_size())]==0:
			additions.append(cell(p,view._resource.grid_size()));break
	check(not additions.is_empty(),"placed stamp has a free sculpt surface")
	if not additions.is_empty():
		var change:={additions[0]:{"before":0,"after":1}}
		check(view._actions.apply_stroke(view._resource,change),"sculpt after native placement")
		check(view._resource.voxel_part_ids[additions[0]]>0 and Solid.active(data(view._resource)),"sculpted addition retains three-look volume")
		history.undo();check(data(view._resource)==expected,"later sculpt Undo retains stamp")
	check(view.save_changes(),registry.error)
	var saved_data:=data(view._resource).duplicate(true)
	check(data(ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP))==saved_data,"native save/fresh Source reopen exact")
	view._resource.voxels[plan.selected[0]]=0;view.discard_changes();check(data(view._resource)==saved_data and not view.has_unsaved_changes(),"native discard restores saved stamp")
	var restored:Node=ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(restored.get_child_count()==2,"scene reopen retains original and edited objects");restored.free()
	for look in 3:
		prop.set_world_look(look)
		check(prop.get_node("Collision/Shape").shape.get_faces()==prop._hull_mesh.get_faces(),"native look%d retains canonical volume collision"%look)
	print("SOLID_STAMP_NATIVE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"selected":selected.size(),"parts":view._resource.merge_parts.size(),"source":entry.path}))
	view.free();history.clear_history();registry.release();scene.free();quit(0 if errors.is_empty() else 1)
