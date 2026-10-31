extends SceneTree
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Creation=preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var errors:Array[String]=[]
const DIR="user://ember-tests/grove-scaling"
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func template()->PackedScene:
	var prop:=EmberVoxelProp.new();prop.model_id="vox_scale_fixture";prop.name="ScaleTree"
	var visual:=MeshInstance3D.new();visual.name="Mesh";var box:=BoxMesh.new();box.size=Vector3(4,16,4)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,box.get_mesh_arrays());visual.mesh=mesh;visual.position.y=8
	prop.add_child(visual);visual.owner=prop
	var packed:=PackedScene.new();packed.pack(prop);prop.free()
	ResourceSaver.save(packed,DIR.path_join("fixture.tscn"))
	return load(DIR.path_join("fixture.tscn"))
func world()->Resource:
	var creator:=Creation.new();creator.prepare_sections("scale",1,1,24)
	var part:Resource=creator.source
	var source:=Terrain.new();source.schema_version=2;source.height_limit=part.height_limit
	source.palette=part.palette;source.palette_surface_roles=part.palette_surface_roles;source.palette_material_ids=part.palette_material_ids
	source.width=9216;source.depth=9216;source.sections={}
	for z in 24:
		for x in 24:source.sections[Vector2i(x,z)]=part
	return source
func recipe()->Resource:
	var plan:=Plan.new();plan.schema_version=Plan.VERSION
	var values:Dictionary=Plan.Influence.GROVE_DEFAULTS.duplicate(true)
	values.model_ids=PackedStringArray(["vox_scale_fixture"]);values.spacing_m=4.0;values.density=8.0*16/(72*72);values.seed=20261029
	plan.regions=[{"id":"trees","name":"Trees","kind":"grove","enabled":true,"bounds":Rect2i(0,0,576,576),"parameters":values}]
	var dense:=values.duplicate(true);dense.density=0.9;dense.seed+=2
	plan.regions.append({"id":"dense","name":"Dense","kind":"grove","enabled":true,"bounds":Rect2i(240,240,48,48),"parameters":dense})
	return plan
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var scene:=Node3D.new();root.add_child(scene)
	var map:=EmberMapLoader.new();map.name="Map";scene.add_child(map);map.owner=scene;map.compact_ground_style=1
	var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	var source:=world();var plan:=recipe();var catalog:Dictionary={"vox_scale_fixture":template()}
	var job:=Grove.new();var accepted:=job.begin(source,map,scene,plan,catalog)
	check(accepted,"576m planner admission: "+job.error)
	if accepted:check(job._smooth_keys.is_empty(),"no full-area smooth queue before the first candidate")
	if not accepted or "--admission-only" in OS.get_cmdline_user_args():
		scene.free();print("GROVE_SCALING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1);return
	var began:=Time.get_ticks_msec()
	while not job.finished and Time.get_ticks_msec()-began<120000:
		job.step(4000)
		await process_frame
	check(job.finished and job.error.is_empty(),"mass generation: "+job.error)
	check(job.placements.size()>256,"more than old global cap admitted")
	var dense_count:=0
	for spec:Dictionary in job.placements:
		if spec.region=="dense":dense_count+=1
		check(is_finite(spec.transform.origin.y),"finite support")
	check(dense_count>64,"dense region exceeds obsolete regional cap")
	check(job._smooth_fields.size()<=16,"bounded candidate field cache")
	var delta:=job.finalize(props);check(not delta.is_empty(),"existing finalize")
	if not delta.is_empty():
		var history:=UndoRedo.new();history.create_action("Mass grove")
		history.add_do_method(Grove.apply_delta.bind(delta,true));history.add_undo_method(Grove.apply_delta.bind(delta,false));history.commit_action()
		map.set_meta(Plan.META,delta.plan)
		check(props.get_child_count()==job.placements.size(),"one apply matches preview")
		history.undo();check(props.get_child_count()==0,"one Undo removes batch")
		history.redo();check(props.get_child_count()==job.placements.size(),"Redo restores batch")
		check(delta.plan.validation_errors(Vector2i(576,576)).is_empty(),"large output plan validates")
		var path:=DIR.path_join("plan.res");ResourceSaver.save(delta.plan,path,ResourceSaver.FLAG_COMPRESS)
		check(Plan.same(load(path),delta.plan),"save/reopen large plan")
		var snapshot:PackedScene=Grove.snapshot(map);var pose:Transform3D=delta.added[0].transform
		delta.added[0].position.x+=1
		check(Grove.restore_snapshot(map,scene,snapshot).is_empty() and delta.added[0].transform==pose,"Discard restores author pose")
		history.clear_history();history.free()
	print("GROVE_SCALING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"count":job.placements.size(),"dense_count":dense_count,"field_cache":job._smooth_fields.size(),"elapsed_ms":Time.get_ticks_msec()-began}))
	scene.free();await process_frame;quit(0 if errors.is_empty() else 1)
