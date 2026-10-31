extends SceneTree
## Regression: actual main assets, no-edit Canvas return and empty scene Save must retain neighbours and all looks. All writes stay in user://.
const Registry=preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Workspace=preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
class MapContext extends EmberMapLoader:
	func _ready()->void:pass # Keep the real map-light owner without generating terrain.
var problems:Array[String]=[]
var stage:Node3D
var folder:="user://canvas-appearance-%d"%Time.get_ticks_usec()

func _initialize()->void:run.call_deferred()
func frames(n:int)->void:
	for i in n:await process_frame
func semantic(value:Variant)->Variant:
	if value is Texture2D:
		var img:Image=value.get_image()
		return [value.get_class(),img.get_size(),hash(img.get_data())] if img!=null else [value.get_class(),"pending"]
	if value is TextureLayered:
		var layers:Array=[]
		for layer in value.get_layers():
			var img:Image=value.get_layer_data(layer);layers.append(hash(img.get_data()) if img!=null else 0)
		return [value.get_class(),layers]
	if value is Resource:return [value.get_class(),value.resource_path]
	return value
func state(prop:Node3D)->Dictionary:
	var visual:=prop.get_node("Mesh") as MeshInstance3D
	var mats:Array=[]
	for i in visual.mesh.get_surface_count():
		var mat:=visual.get_active_material(i)
		var uniforms:Dictionary={}
		if mat is ShaderMaterial:
			for uniform in mat.shader.get_shader_uniform_list():
				var value:Variant=mat.get_shader_parameter(uniform.name)
				if value==null:value=RenderingServer.call("shader_get_parameter_default",mat.shader.get_rid(),uniform.name)
				uniforms[uniform.name]=semantic(value)
		mats.append({"shader":mat.shader.code.hash() if mat is ShaderMaterial else str(mat),"uniforms":uniforms})
	return {"look":prop.solid_look(),"mats":mats}
func compare(props:Array[Node3D],before:Array,label:String)->void:
	for i in props.size():
		var after:=state(props[i]);var changes:Array=[]
		for slot in mini(before[i].mats.size(),after.mats.size()):
			for key in after.mats[slot].uniforms:
				if before[i].mats[slot].uniforms.get(key)!=after.mats[slot].uniforms[key]:changes.append([key,before[i].mats[slot].uniforms.get(key),after.mats[slot].uniforms[key]])
		if not changes.is_empty():print("APPEARANCE_DELTA ",label," ",props[i].name," ",changes)
		check(after==before[i],label+": "+props[i].name)
func check(ok:bool,label:String)->void:
	if not ok:problems.append(label);printerr("APPEARANCE_FAIL ",label)
func capture(label:String)->float:
	await frames(8);await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image();img.convert(Image.FORMAT_RGBA8);img.save_png(ProjectSettings.globalize_path(folder.path_join(label+".png")))
	var bytes:=img.get_data();var white:=0
	for i in range(0,bytes.size(),4):
		if bytes[i]>240 and bytes[i+1]>240 and bytes[i+2]>240:white+=1
	var ratio:=float(white)/(img.get_width()*img.get_height());print("APPEARANCE_WHITE ",label," ",ratio);return ratio
func save_scene()->int:
	stage.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed:=PackedScene.new();var err:=packed.pack(stage)
	if err==OK:err=ResourceSaver.save(packed,stage.scene_file_path)
	stage.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE);return err
func wait_projection(entry:Dictionary)->void:
	var deadline:=Time.get_ticks_msec()+30000
	while is_instance_valid(entry.preview) and not entry.preview.is_projection_complete() and Time.get_ticks_msec()<deadline:await frames(1)
	check(is_instance_valid(entry.preview) and entry.preview.is_projection_complete(),"draft projection settles")
func draft_preview(view:Control,sessions:RefCounted,entry:Dictionary,selected:EmberVoxelProp,history:UndoRedo,camera:Camera3D,source_path:String)->void:
	var source_hash:=FileAccess.get_sha256(source_path)
	await wait_projection(entry)
	check(entry.preview.has_method("object_presentation_pending"),"dirty solid must use the published object presentation")
	if entry.preview.has_method("object_presentation_pending"):
		check(entry.resource.validation_errors().is_empty(),"draft Source validates before publication parity")
		var packed:=EmberVoxelPrefab.prepare_resource(entry.resource)
		check(packed!=null,"publication fixture prepares")
		if packed==null:return
		var expected:=packed.instantiate() as EmberVoxelProp
		expected.authoring_source=entry.resource.duplicate_model();expected.hide();stage.add_child(expected)
		expected.global_transform=sessions.frame(entry)*expected.get_node("Mesh").transform.affine_inverse()
		for look in [0,1,2]:
			selected.set_world_look(look);expected.set_world_look(look);await frames(3)
			var live:EmberVoxelProp=entry.preview._object_visual
			check(is_instance_valid(live),"ready typed prop")
			if not is_instance_valid(live):break
			var actual:MeshInstance3D=live.get_node("Mesh");var reference:MeshInstance3D=expected.get_node("Mesh")
			check(actual.mesh.get_faces()==reference.mesh.get_faces(),"look%d draft triangles equal publication"%look)
			check(actual.global_transform.is_equal_approx(reference.global_transform),"look%d source frame equals publication"%look)
			compare([live],[state(expected)],"look%d draft materials and light equal publication"%look)
			check(live.get_node("Collision/Shape").shape.get_faces()==expected.get_node("Collision/Shape").shape.get_faces(),"look%d physical boundary equals publication"%look)
			var bounds:AABB=actual.global_transform*actual.get_aabb();var point:=bounds.get_center()
			var sample:=point;var triangles:=reference.mesh.get_faces()
			for i in range(0,triangles.size(),3):
				if (triangles[i+2]-triangles[i]).cross(triangles[i+1]-triangles[i]).normalized().y>0.5:
					sample=reference.global_transform*((triangles[i]+triangles[i+1]+triangles[i+2])/3.0);break
			var floor_actual:=selected.surface_floor_sample(sample);var floor_expected:=expected.surface_floor_sample(sample)
			check(floor_actual.get("solid",false) and floor_expected.get("solid",false) and floor_actual.position.distance_to(floor_expected.position)<0.0001 and floor_actual.normal.distance_to(floor_expected.normal)<0.0001 and floor_actual.get("object")==live,"look%d authoring floor follows draft geometry and owner"%look)
			camera.size=bounds.size.length()*1.4;camera.position=point+Vector3(1,0.8,1.3)*camera.size;camera.look_at(point)
			await capture("draft-look%d"%look)
		expected.free()
		if "--looks-only" in OS.get_cmdline_user_args():
			view.discard_changes()
			check(not is_instance_valid(entry.preview) and selected.authoring_preview==null and not sessions.dirty(entry),"Discard restores the original presentation and data")
			check(entry.resource.validation_errors().is_empty(),"discarded Source validates")
			check(PhysicsServer3D.body_get_collision_layer(selected.get_node("Collision").get_rid())==selected.get_node("Collision").collision_layer,"Discard restores original physics")
			print("DRAFT_APPEARANCE ",JSON.stringify({"pass":problems.is_empty(),"errors":problems}));return
		var cell:int=entry.resource.voxels.find(1)
		view._actions.apply_stroke(entry.resource,{cell:{"before":1,"after":2}});await frames(1)
		view._actions.apply_stroke(entry.resource,{cell:{"before":2,"after":1}})
		await wait_projection(entry)
		check(entry.preview._object_visual.authoring_source.voxels==entry.resource.voxels,"stale worker cannot replace the latest draft")
		history.undo();history.undo();history.undo()
		check(not is_instance_valid(entry.preview) and selected.authoring_preview==null,"Undo to clean restores original display and floor owner")
		var body:StaticBody3D=selected.get_node("Collision")
		check(PhysicsServer3D.body_get_collision_layer(body.get_rid())==body.collision_layer,"Undo restores original physical layer")
		history.redo();await wait_projection(entry)
		check(view.save_changes(),sessions.error)
		var reopened:=ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
		check(reopened!=null and reopened.to_definition(true).model==entry.resource.to_definition(true).model,"saved Source reopens exactly")
		check(not is_instance_valid(entry.preview) and selected.authoring_preview==null,"Save publishes the real prop and removes its temporary view")
	check(FileAccess.get_sha256(source_path)==source_hash,"author Source remains unchanged")
	print("DRAFT_APPEARANCE ",JSON.stringify({"pass":problems.is_empty(),"errors":problems}))
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=60;root.size=Vector2i(1200,720)
	var original:Node=load("res://scenes/landscape_compact.tscn").instantiate()
	stage=Node3D.new() if "--standalone" in OS.get_cmdline_user_args() else MapContext.new()
	if stage is EmberMapLoader:stage.compact_material_light_mode=1;stage.compact_material_gray_preview=false
	stage.name="AppearanceFixture";stage.scene_file_path=folder.path_join("scene.tscn")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("models")))
	var props:Array[Node3D]=[]
	var names:Array=["EarthCliffCorner","CoastalHouse"] if "--minimal" in OS.get_cmdline_user_args() else ["EarthCliffCorner","EarthCliffStraight","PaintedRockGroup","CoastalHouse"]
	for name in names:
		var prop:Node3D=original.get_node("Map/Props/"+name);prop.get_parent().remove_child(prop);prop.owner=null;stage.add_child(prop);prop.owner=stage
		props.append(prop)
	original.free();root.add_child(stage)
	for prop in props:prop.set_world_look(0)
	var env:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("283849");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.5;env.environment=settings;stage.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.2;stage.add_child(sun)
	var house:Node3D=props.back();var mesh:MeshInstance3D=house.get_node("Mesh");var bounds:AABB=mesh.global_transform*mesh.get_aabb()
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=bounds.size.length()*1.35;camera.far=5000;stage.add_child(camera);camera.position=bounds.get_center()+Vector3(1,0.8,1.3)*camera.size;camera.look_at(bounds.get_center());camera.current=true
	await frames(6)
	var white_before:float=await capture("before")
	var before:Array=[]
	for prop in props:before.append(state(prop))
	var selected:=props[0] as EmberVoxelProp
	var source:=load("res://content/voxel_models/"+selected.model_id+".tres") as EmberVoxelModelResource
	ResourceSaver.save(source.duplicate_model(),folder.path_join("models/"+selected.model_id+".tres"))
	if "--add-preview" in OS.get_cmdline_user_args():
		var restored:=EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
		restored.name=selected.name;restored.transform=selected.transform;restored.scene_file_path=selected.scene_file_path
		selected.free();stage.add_child(restored);restored.owner=stage;restored.set_world_look(0)
		selected=restored;props[0]=restored;await frames(3);before[0]=state(restored)
	var history:=UndoRedo.new();var sessions:=Registry.new();sessions.source_directory=folder.path_join("models");sessions.prefab_directory=folder.path_join("prefabs");sessions.recovery_directory=folder.path_join("recovery");sessions.configure(history,save_scene)
	var entry:=sessions.open_object(selected,stage)
	check(not entry.is_empty(),sessions.error)
	var view:=Workspace.new();view.setup(null,history);root.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(view.open_world_draft(entry,sessions,func():return sessions.save_all(stage)),"actual world draft opens")
	await frames(8);view.hide();await frames(4)
	print("APPEARANCE_WORLDS ",JSON.stringify({"same_world":view._viewport.world_3d==root.world_3d,"canvas_own_world":view._viewport.own_world_3d}))
	var white_after:float=await capture("after-canvas")
	check(absf(white_before-white_after)<0.02,"neighbour house must not whiten when Canvas opens")
	check(not is_instance_valid(entry.preview),"opening a clean cliff must not replace detailed textured world appearance with a voxel projection")
	compare(props,before,"world material/look unchanged after Canvas")
	var adding:bool="--add-preview" in OS.get_cmdline_user_args()
	var cell:int=entry.resource.voxels.find(0 if adding else 1)
	check(view._actions.apply_stroke(entry.resource,{cell:{"before":0 if adding else 1,"after":1 if adding else 2 if "--paint-preview" in OS.get_cmdline_user_args() else 0}}),"real sculpt still activates the world draft")
	check(is_instance_valid(entry.preview) and entry.preview.surface()==entry.resource,"first edit creates the existing live projection")
	if "--draft-preview" in OS.get_cmdline_user_args():
		await draft_preview(view,sessions,entry,selected,history,camera,source.resource_path)
		view.free();history.clear_history();sessions.release();stage.free();quit(0 if problems.is_empty() else 1);return
	history.undo()
	check(not is_instance_valid(entry.preview) and not sessions.dirty(entry),"Undo to clean state restores the original world presentation")
	check(view.save_changes(),sessions.error)
	var white_save:float=await capture("after-save")
	check(absf(white_before-white_save)<0.02,"neighbour house must not whiten on no-op Save")
	compare(props,before,"world material/look unchanged after no-op Save")
	for look in [1,2,0]:
		for prop in props:prop.set_world_look(look)
		await frames(2)
		var expected:Array=[]
		for prop in props:expected.append(state(prop))
		sessions.preview(entry)
		check(view.save_changes(),sessions.error);await frames(3)
		compare(props,expected,"return/Save retains look%d and neighbours"%look)
	print("APPEARANCE ",JSON.stringify({"pass":problems.is_empty(),"errors":problems,"preview":is_instance_valid(entry.preview),"dirty":sessions.dirty_count(stage)}))
	view.free();history.clear_history();sessions.release();stage.free();quit(0 if problems.is_empty() else 1)
