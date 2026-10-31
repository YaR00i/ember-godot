extends SceneTree
const Smooth=preload("res://addons/ember_import/ember_voxel_volume_smooth.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Workspace=preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Registry=preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Edit=preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var errors:Array[String]=[]
var scene:Node3D
var folder:="user://volume-smooth-%d"%Time.get_ticks_usec()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("VOLUME_SMOOTH_FAIL ",label)
func index(p:Vector3i,size:Vector3i)->int:return p.x+size.x*(p.z+size.z*p.y)
func fixture()->EmberVoxelModelResource:
	var source:=EmberVoxelModelResource.new();source.model_id="smooth_fixture";source.display_name="Объёмное сглаживание"
	source.voxels_per_block=16;source.size_blocks=Vector3i(3,1,3);source.height_voxels=48
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("737e89"),Color("89654b"),Color("769550")])
	source.merge_parts=PackedStringArray(["Основа","Выступ"])
	var size:=source.grid_size();source.voxels.resize(size.x*size.y*size.z);source.voxel_part_ids.resize(source.voxels.size())
	for y in range(4,44):
		for z in range(4,28):
			for x in range(4,44):
				var first:=x<28 and y<28;var second:=x>=20 and y>=20
				if not first and not second:continue
				var at:=index(Vector3i(x,y,z),size);source.voxels[at]=1 if y<20 else 2 if y<36 else 3;source.voxel_part_ids[at]=1 if first else 2
	source.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]),PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","stone","soil","grass"]),"material_ids":PackedStringArray(["","cartoon_stone","soil_grain","cartoon_grass"]),"occupancy":Solid.occupancy_hash(source.voxels)}
	return source
func job(source:EmberVoxelModelResource,center:Vector3i,radius:=10,strength:=4)->RefCounted:
	var calculation:=Smooth.new();calculation.values=source.voxels;calculation.parts=source.voxel_part_ids;calculation.size=source.grid_size();calculation.radius=radius;calculation.kernel=strength
	calculation.segments=[{"from":center,"to":center}];calculation.run();return calculation
func _initialize()->void:run.call_deferred()
func run()->void:
	if "--plane" in OS.get_cmdline_user_args():plane_cases();return
	if "--native" in OS.get_cmdline_user_args():await native();return
	var source:=fixture();var before:=source.voxels.duplicate();var center:=Vector3i(20,28,16)
	var calculation:=job(source,center)
	check(not calculation.changes.is_empty(),"concave seam changes")
	var added:=0;var removed:=0
	for at in calculation.changes:
		var change:Dictionary=calculation.changes[at]
		if change.after>0:added+=1;check(change.after in [1,2,3] and calculation.owners[at] in [1,2],"new cells inherit material and owner")
		else:removed+=1
	check(added>0,"fills concave seam rather than only shrinking")
	check(source.voxels==before,"pure immutable input")
	var again:=job(source,center);check(again.changes==calculation.changes,"deterministic")
	var flat:=job(source,Vector3i(12,12,4),5,2);check(flat.changes.is_empty(),"flat side stays flat")
	var convex:=job(source,Vector3i(27,4,16),10,4);var eroded:=false
	for change in convex.changes.values():
		if change.after==0:eroded=true
	check(eroded,"smooth rounds a convex bulge too")
	# Permute Y/Z: exactly the same operation works on a sideways seam.
	var rotated:=source.duplicate_model();rotated.voxels.fill(0)
	var size:=source.grid_size()
	for y in size.y:
		for z in size.z:
			for x in size.x:rotated.voxels[index(Vector3i(x,z,y),size)]=source.voxels[index(Vector3i(x,y,z),size)]
	var sideways:=job(rotated,Vector3i(center.x,center.z,center.y))
	check(sideways.changes.size()==calculation.changes.size(),"axis-independent seam smoothing")
	var large:=job(source,center,20,8)
	print("VOLUME_SMOOTH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"added":added,"removed":removed,"local_usec":calculation.elapsed_usec,"large_usec":large.elapsed_usec,"sampled":calculation.sampled_cells}))
	quit(0 if errors.is_empty() else 1)

func frames(count:int)->void:
	for i in count:await process_frame
func save_scene()->int:
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed:=PackedScene.new();var result:=packed.pack(scene)
	if result==OK:result=ResourceSaver.save(packed,scene.scene_file_path)
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	return result
func finish_jobs(view:Control)->void:
	for i in 240:
		if view._volume_smooth_job==null and view._volume_smooth_segments.is_empty():return
		await process_frame
	check(false,"worker completes")
func finish_previews(view:Control)->void:
	for i in 360:
		if view._volume_preview_job==null and view._pending_preview_chunks.is_empty():return
		await process_frame
	check(false,"preview queue completes")
func check_preview(view:Control,indices:PackedInt32Array)->void:
	var width:int=view._preview_chunk_size();var size:Vector3i=view._resource.grid_size()
	for chunk:Vector2i in view._affected_preview_chunks(indices):
		var start:=Vector3i(chunk.x*width,0,chunk.y*width)
		var extent:=Vector3i(mini(width,size.x-start.x),size.y,mini(width,size.z-start.z))
		var reference:=EmberVoxelSurfaceMesher.build_region(view._resource,start,extent,1.0/view._resource.normalized_density(),false,true,-1)
		var actual:Mesh=view._chunk_meshes[chunk].mesh
		if reference.get_surface_count()==0:check(actual==null,"empty preview chunk");continue
		check(actual!=null and actual.get_faces()==reference.get_faces(),"async preview equals existing mesher")
		if actual!=null:check(actual.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==reference.surface_get_arrays(0)[Mesh.ARRAY_COLOR],"async preview retains vertex colours")
func native()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=60;root.size=Vector2i(1500,960)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var source:=fixture();var installed:=Edit.Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),folder.path_join(source.model_id+".tres"),folder.path_join(source.model_id+".tscn"))
	check(installed.ok,"fixture publication")
	scene=Node3D.new();scene.name="VolumeSmoothFixture";scene.scene_file_path=folder.path_join("scene.tscn");root.add_child(scene)
	var prop:=installed.packed.instantiate() as EmberVoxelProp;prop.authoring_source=source;scene.add_child(prop);prop.owner=scene
	var history:=UndoRedo.new();var registry:=Registry.new();registry.source_directory=folder;registry.prefab_directory=folder;registry.recovery_directory=folder.path_join("recovery");registry.configure(history,save_scene)
	var entry:Dictionary=registry.open_object(prop,scene);check(not entry.is_empty(),registry.error)
	var view:=Workspace.new();view.setup(null,history);root.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.open_world_draft(entry,registry,func():return registry.save_all(scene));view._enable_canvas_forms()
	for i in view._tool.item_count:
		if view._tool.get_item_metadata(i)==Model.TOOL_SMOOTH:view._tool.select(i);view._on_tool_selected(i);break
	view._select_option_metadata(view._radius,16);view._select_option_metadata(view._smooth_strength,4)
	await frames(3)
	check(not view._smooth_mode.visible and view._selection_panel._mask_kind=="voxels","volume controls and voxel mask")
	check(not view._coarse.visible and not view._palette.visible,"unrelated coarse and paint controls hidden")
	var before:PackedByteArray=view._resource.voxels.duplicate();var original_parts:PackedInt32Array=view._resource.voxel_part_ids.duplicate()
	var center:=Vector3i(20,28,16);var version:=history.get_version()
	view._prepare_stroke(Model.TOOL_SMOOTH);view._apply_smooth_segment(center,center)
	await finish_jobs(view)
	check(view._stroke_active and not view._stroke_changes.is_empty() and history.get_version()==version,"visible held preview without early history")
	for draft in view._pending_preview_chunks.values():check(not draft,"held preview uses full volume rather than heightfield")
	var expected:PackedByteArray=view._resource.voxels.duplicate();var inherited:Dictionary=view._volume_smooth_owners.duplicate()
	var changed_indices:=PackedInt32Array(view._stroke_changes.keys())
	var worker_usec:int=view._volume_smooth_last_usec;var release_start:=Time.get_ticks_usec();view._finish_stroke();var release_usec:=Time.get_ticks_usec()-release_start
	check(view._resource.voxels==expected and not view._stroke_active,"release equals held preview")
	for at in inherited:
		if before[at]==0 and expected[at]>0:check(view._resource.voxel_part_ids[at]==inherited[at],"new filled cells retain donor part")
	check(view._resource.validation_errors().is_empty(),"volume validates after smoothing")
	history.undo();check(view._resource.voxels==before and view._resource.voxel_part_ids==original_parts,"one Undo restores geometry and parts")
	history.redo();check(view._resource.voxels==expected,"Redo exact")
	await finish_previews(view);check_preview(view,changed_indices)
	view._prepare_stroke(Model.TOOL_SMOOTH);view._apply_smooth_segment(center+Vector3i(0,0,6),center);await finish_jobs(view)
	view._drain_preview_chunk();view._cancel_stroke();await finish_previews(view)
	check(view._resource.voxels==expected,"cancel rejects pending stale work")
	check_preview(view,changed_indices)
	check(view.save_changes(),registry.error)
	var reopened:Resource=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(Registry.same_data(reopened,view._resource),"save/reopen exact geometry paint and parts")
	for look in 3:
		prop.set_world_look(look)
		# Display cubes do not move the canonical carved boundary or its floor queries.
		check(prop.get_node("Collision/Shape").shape.get_faces()==prop._hull_mesh.get_faces(),"look%d retains canonical volume physics"%look)
		if look<2:check(prop.get_node("Collision/Shape").shape.get_faces()==prop.get_node("Mesh").mesh.get_faces(),"look%d physical surface equals visible boundary"%look)
	for i in view._tool.item_count:
		if view._tool.get_item_metadata(i)==Model.TOOL_ADD:view._tool.select(i);view._on_tool_selected(i);break
	check(view._volume_preview_enabled(),"follow-up sculpting retains background preparation")
	var carve:=Model.oriented_stroke_changes(view._resource,view._resource.voxels,Vector3i(12,12,4),Vector3i.FORWARD,Model.TOOL_REMOVE,1,2,3)
	check(view._actions.apply_stroke(view._resource,carve),"carving continues on smoothed volume")
	history.undo();check(view._resource.voxels==expected,"later carve undo retains smooth shape")
	view._prepare_stroke(Model.TOOL_SMOOTH);view._apply_smooth_segment(center+Vector3i(0,0,6),center);view._finish_stroke()
	view.discard_changes();check(view._resource.voxels==expected and not view.has_unsaved_changes(),"discard restores saved smoothed shape")
	print("VOLUME_SMOOTH_NATIVE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"worker_usec":worker_usec,"release_usec":release_usec,"changed":inherited.size()}))
	view.free();history.clear_history();registry.release();scene.free();quit(0 if errors.is_empty() else 1)

func plane_cases()->void:
	var size:=Vector3i(24,24,24);var values:=PackedByteArray();values.resize(24*24*24)
	var parts:=PackedInt32Array();parts.resize(values.size())
	for y in range(4,20):
		for z in range(4,20):
			for x in range(2,15):
				if x>=12 and y in range(7,11) and z in range(7,11):continue
				var at:=index(Vector3i(x,y,z),size);values[at]=2 if y<12 else 1;parts[at]=2 if y<12 else 1
	for y in range(11,15):
		for z in range(11,15):
			for x in range(15,18):values[index(Vector3i(x,y,z),size)]=1;parts[index(Vector3i(x,y,z),size)]=1
	for cut in [false,true]:
		var job:=Model.SurfacePlaneJob.new();job.values=values;job.parts=parts;job.size=size;job.radius=10;job.depth=4;job.plane_point=Vector3(14.5,12,12);job.plane_normal=Vector3.RIGHT;job.cut_only=cut;job.segments=[{"from":Vector3i(14,12,12),"to":Vector3i(14,12,12)}];job.run()
		var added:=0;var removed:=0
		for i in job.changes:
			var pair:Dictionary=job.changes[i];var x:int=int(i)%24
			check(pair.before==int(values[i]),"plane delta immutable before")
			if pair.after==0:removed+=1;check(x>=15,"plane removes only outward cells")
			else:added+=1;check(x<=14 and pair.after==2 and job.owners[i]==2,"plane fills with inward material and part")
		check(removed>0 and (added==0 if cut else added>0),"cut is subtractive, flatten fills nearby depression")
		check(values[index(Vector3i(17,12,12),size)]==1,"worker never mutates baseline")
		# Rotate the same volume/plane into all signed principal axes.
		for direction in [Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
			var basis:=Basis(Quaternion(Vector3.RIGHT,direction));var offset:=Vector3(11.5,11.5,11.5)
			var rotated:=PackedByteArray();rotated.resize(values.size());var owners:=PackedInt32Array();owners.resize(parts.size());var mapping:Dictionary={}
			for i in values.size():
				var p:=Vector3i(i%24,i/(24*24),(i/24)%24);var q:=Vector3i((basis*(Vector3(p)-offset)+offset).round());var at:=index(q,size);mapping[i]=at;rotated[at]=values[i];owners[at]=parts[i]
			var other:=Model.SurfacePlaneJob.new();other.values=rotated;other.parts=owners;other.size=size;other.radius=job.radius;other.depth=job.depth;other.cut_only=cut;other.plane_normal=direction;other.plane_point=basis*(job.plane_point-offset)+offset
			var center:=Vector3i((basis*(Vector3(14,12,12)-offset)+offset).round());other.segments=[{"from":center,"to":center}];other.run()
			check(other.changes.size()==job.changes.size(),"plane axis invariant count")
			for i in job.changes:check(other.changes.get(mapping[i],{})==job.changes[i],"plane axis invariant values")
	var cancelled:=Model.SurfacePlaneJob.new();cancelled.values=values;cancelled.parts=parts;cancelled.size=size;cancelled.segments=[{"from":Vector3i.ONE*12,"to":Vector3i.ONE*12}];cancelled.cancelled=true;cancelled.run();check(cancelled.changes.is_empty(),"cancelled plane produces no delta")
	var tilted:=Model.SurfacePlaneJob.new();tilted.values=values;tilted.parts=parts;tilted.size=size;tilted.radius=6;tilted.depth=4;tilted.plane_normal=Vector3(1,0.3,0.2).normalized();tilted.plane_point=Vector3(14,12,12);tilted.cut_only=true;tilted.segments=[{"from":Vector3i(14,12,12),"to":Vector3i(14,12,15)}];tilted.run()
	check(not tilted.changes.is_empty(),"inclined plane works")
	for i in tilted.changes:
		var p:=Vector3(i%24,i/(24*24),(i/24)%24)
		check((p-tilted.plane_point).dot(tilted.plane_normal)>=-0.0001 and tilted.changes[i].after==0,"inclined trim preserves inner half-space")
	var shifted:=Model.SurfacePlaneJob.new();shifted.values=values;shifted.parts=parts;shifted.size=size;shifted.radius=2;shifted.depth=2;shifted.plane_normal=Vector3.RIGHT;shifted.plane_point=Vector3(5.5,12,12);shifted.cut_only=true;shifted.segments=[{"from":Vector3i(14,12,12),"to":Vector3i(14,12,12)}];shifted.run()
	check(not shifted.changes.is_empty(),"offset plane bounds follow actual plane")
	print("SURFACE_PLANE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
