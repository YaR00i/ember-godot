extends SceneTree
## Only Grab's solid-profile transaction; all mutations are on a duplicate/user copy.
const Fragment=preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Actions=preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Session=preload("res://addons/ember_import/ember_voxel_object_session.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("SOLID_GRAB_FAIL ",label)
func model(source:EmberVoxelModelResource)->Dictionary:
	return EmberVoxelPrefab.model_of(source.to_definition())
func run()->void:
	var recipe:=Generator.default_recipe(Generator.CLIFF);recipe.seed=27
	var source:EmberVoxelModelResource=Generator.build(recipe,Color.WHITE,{},"Grab fixture","solid_grab_fixture").geometry
	var before:=source.to_definition().duplicate(true)
	if DisplayServer.get_name()!="headless":
		var scene:=Node3D.new();root.add_child(scene);current_scene=scene
		var prop:=EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
		scene.add_child(prop)
		if "--colour-only" in OS.get_cmdline_user_args():
			await check_grass_colour(prop,source,scene)
			print("SOLID_GRAB_COLOUR ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
			prop.free();quit(0 if errors.is_empty() else 1);return
		var session:=Session.new()
		var data:=model(source)
		prop._hull_mesh=prop.get_node("Mesh").mesh
		prop._voxel_mesh=Solid.build_voxel_look(data)
		prop._living_mesh=Solid.living_mesh(data,1.0,Solid.living_pulls(source.solid_surface.material_ids))
		for mesh in [prop._hull_mesh,prop._voxel_mesh,prop._living_mesh]:
			prop.get_node("Mesh").mesh=mesh
			check(session._projection_errors(prop,source).is_empty(),"presentation is not an external edit")
		var visual:=prop.get_node("Mesh") as MeshInstance3D
		var original_mesh:=visual.mesh;visual.mesh=ArrayMesh.new()
		check(not session._projection_errors(prop,source).is_empty(),"unknown replacement remains protected")
		visual.mesh=original_mesh;prop.free()
	var job:=Fragment.start_grab(source,Vector3(64.5,13.5,32.5),16,Vector3(3,0,0),75)
	while not job.done:job.step(8192,4000)
	var plan:Dictionary=job.result
	check(not plan.has("error"),str(plan.get("error","grab plan")))
	if plan.has("error"):quit(1);return
	var draft:EmberVoxelModelResource=source.duplicate(true)
	for key in plan.properties:draft.set(key,plan.properties[key])
	check(source.to_definition()==before,"preview leaves Source unchanged")
	check(Solid.active(model(draft)),"Grab preview retains the solid hull")
	var bad_owners:=draft.voxel_part_ids.duplicate()
	for i in draft.voxels.size():
		if draft.voxels[i]>0:bad_owners[i]=0;break
	check(Solid.grab_profile(source,draft.voxels,bad_owners).has("error"),"unowned output rejected")
	if not errors.is_empty():quit(1);return
	var history:=UndoRedo.new();var actions:=Actions.new();actions.configure(history)
	check(actions.apply_fragment(source,plan),"one Grab transaction")
	check(source.to_definition()==draft.to_definition(),"commit equals exact preview")
	check(source.validation_errors().is_empty(),"modified Source validates")
	var after:=source.to_definition().duplicate(true)
	history.undo();check(source.to_definition()==before and not history.has_undo(),"single Undo restores volume and profile")
	history.redo();check(source.to_definition()==after,"Redo exact")
	check(not actions.apply_fragment(source,plan),"stale plan rejected")
	check(source.solid_surface.roles==draft.solid_surface.roles and source.solid_surface.material_ids==draft.solid_surface.material_ids,"material roles unchanged")
	var old_hull:=Solid.build(EmberVoxelPrefab.model_of(before))
	var new_hull:=Solid.build(model(source))
	check(old_hull.get_faces()!=new_hull.get_faces(),"outer hull visibly changes")
	var voxel:=Solid.build_voxel_look(model(source))
	var detailed:=Solid.living_mesh(model(source),1.0,Solid.living_pulls(source.solid_surface.material_ids))
	check(new_hull.get_surface_count()>0 and voxel.get_surface_count()>0 and detailed.get_surface_count()>0,"three look meshes exist")
	# A later carve uses the volume boundary instead of closing it with the hull.
	var removed:EmberVoxelModelResource=source.duplicate(true)
	for i in removed.voxels.size():
		if removed.voxels[i]>0:removed.voxels[i]=0;break
	check(Solid.active(model(removed)) and Solid.uses_volume(model(removed)),"carve retains a concave volume boundary")
	var path:="user://ember-tests/solid-grab.tres";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(source,path)==OK,"save manual shape")
	var saved:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.voxels==source.voxels and saved.solid_surface==source.solid_surface and Solid.active(model(saved)),"fresh reopen keeps volume and profile")
	var changed:EmberVoxelModelResource=saved.duplicate(true);changed.voxels.fill(0)
	check((ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource).voxels==saved.voxels,"discard unsaved draft")
	print("SOLID_GRAB ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"kernel_ms":job.elapsed_usec/1000.0,"changed":plan.changed_indices.size()}))
	history.clear_history();quit(0 if errors.is_empty() else 1)

func check_grass_colour(prop:EmberVoxelProp,source:EmberVoxelModelResource,scene:Node3D)->void:
	var camera:=Camera3D.new();scene.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=120;camera.far=1000
	camera.look_at_from_position(Vector3(120,100,140),Vector3(0,14,0));camera.make_current()
	var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-45,-30,0)
	var mesh:=Solid.living_mesh(model(source),1.0,Solid.living_pulls(source.solid_surface.material_ids))
	Solid.apply_materials(mesh,model(source))
	var visual:=prop.get_node("Mesh") as MeshInstance3D
	visual.mesh=mesh;visual.material_override=Solid.material_for(mesh,true)
	Solid.set_world_scale(visual.material_override,16.0)
	var centre:=Vector3.ZERO;var found:=false
	for face:Dictionary in Solid.hull_faces(model(source)).faces:
		if face.slot==3 and face.plane.normal.y>0.85:
			for point:Vector3 in face.face:centre+=point
			centre/=float(face.face.size());found=true;break
	check(found,"grass face exists")
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var pixel:=camera.unproject_position(prop.get_node("Mesh").to_global(centre/float(source.normalized_density())))
	var colour:=Color(0,0,0,0)
	for x in range(-2,3):
		for y in range(-2,3):colour+=image.get_pixel(int(pixel.x)+x,int(pixel.y)+y)
	colour/=25.0
	check(colour.g>colour.r*1.01 and colour.g>colour.b*1.1,"stone relief must not recolour grass")
