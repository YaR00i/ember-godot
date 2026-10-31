extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Placement=preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const DIR="user://ember-tests/smooth-placement"
var errors: Array[String]=[]
var worst_step_us:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);push_error(message)
func settle(projection) -> void:
	var deadline:=Time.get_ticks_msec()+60000
	while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(projection.pending_tile_count()==0,"tile timeout")
	await physics_frame;await physics_frame
func model(id: String,rock: bool) -> PackedScene:
	var prop:=EmberVoxelProp.new();prop.name=id;prop.model_id=id
	var mesh:=MeshInstance3D.new();mesh.name="Mesh";mesh.mesh=BoxMesh.new()
	mesh.mesh.size=Vector3(8,8 if rock else 32,8);mesh.position.y=0 if rock else 16
	var native_mesh:=ArrayMesh.new();native_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.mesh.get_mesh_arrays());mesh.mesh=native_mesh
	prop.add_child(mesh);mesh.owner=prop
	var packed:=PackedScene.new();check(packed.pack(prop)==OK,"pack object");prop.free()
	var path:=DIR.path_join(id+".tscn");check(ResourceSaver.save(packed,path)==OK,"save object")
	return ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
func recipe(kind: String) -> Resource:
	var plan:=Plan.new();plan.schema_version=Plan.VERSION
	var values: Dictionary=(Plan.Influence.PLACEMENT_DEFAULTS if kind=="placement" else Plan.Influence.GROVE_DEFAULTS).duplicate(true)
	values.model_ids=PackedStringArray(["vox_fixture_smooth_tree","vox_fixture_smooth_rock"]);values.spacing_m=2.0;values.density=1.0;values.slope_percent=50.0
	plan.regions=[{"id":"objects","name":"Опора","kind":kind,"enabled":true,"bounds":Rect2i(1,1,6,6),"parameters":values}]
	return plan
func prepare(source,map,scene,plan,catalog,budget:=4000):
	var job:=Grove.new();check(job.begin(source,map,scene,plan,catalog),job.error)
	var deadline:=Time.get_ticks_msec()+60000
	while not job.finished and Time.get_ticks_msec()<deadline:job.step(budget)
	check(job.finished and job.error.is_empty(),"placement job: "+job.error)
	worst_step_us=maxi(worst_step_us,job.worst_step_us)
	return job
func support(map,job,spec: Dictionary) -> float:
	var radius:=0.5;var point: Vector2=spec.point
	if spec.get("kind","")=="placement":
		var foot: Dictionary=Placement.footprint(job._template_bounds[spec.model_id],spec.transform)
		point=foot.point;radius=foot.radius
	var high: float=-INF
	for offset in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var sample: Dictionary=map.surface_floor_sample(job._frame*Vector3((point.x+offset.x)*16,0,(point.y+offset.y)*16))
		check(sample.get("solid",false),"support query solid")
		high=maxf(high,(job._frame.affine_inverse()*sample.position).y/16.0)
	return high
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var catalog={"vox_fixture_smooth_tree":model("vox_fixture_smooth_tree",false),"vox_fixture_smooth_rock":model("vox_fixture_smooth_rock",true)}
	var source:=Fixture.detailed(Fixture.base());var original:=source.working_copy()
	var scene:=Node3D.new();root.add_child(scene)
	var map:=Map.new();map.name="Map";map.hydrate_legacy_regions=false;map.imported_tile_size=1.0;map.compact_ground_style=1;map.compact_terrain=source
	scene.add_child(map);map.owner=scene
	if map.get_node_or_null("Props")==null:
		var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	var projection=map._visual_surface_projection;projection.runtime_geometry_cache_enabled=false;await settle(projection)
	var oversized:=source.working_copy();oversized.width=4096
	var invalid:=Grove.new()
	check(not invalid.begin(oversized,map,scene,recipe("grove"),catalog) and not invalid.error.is_empty(),"smooth map limit enforced by planner")
	# A map may explicitly raise its retained detailed budget after adding sections.
	var wide:=Fixture.base();wide.width=768;wide.depth=400
	for channel: String in wide.Sections.CHANNELS:
		var values=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(wide.width*wide.depth)
		values.fill(24 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0)
		wide.set(channel,values)
	check(wide.validation_errors().is_empty(),"expanded fixture validates")
	map.compact_smooth_study_column_limit=524288
	var wide_job:=Grove.new();var accepts:bool=wide_job.begin(wide,map,scene,recipe("placement"),catalog)
	check(accepts,"placement honors expanded map budget: "+wide_job.error)
	if accepts:
		while not wide_job.finished:wide_job.step(4000)
		check(wide_job.error.is_empty() and not wide_job.placements.is_empty(),"expanded map produces supported objects")
		for spec:Dictionary in wide_job.placements:
			check(absf(spec.transform.origin.y/16.0+wide_job._template_bounds[spec.model_id].position.y/16.0-1.5)<0.00001,"expanded detailed support")
	var seam_plan:=recipe("placement");seam_plan.regions[0].bounds=Rect2i(22,1,6,6)
	var seam_dense=prepare(wide,map,scene,seam_plan,catalog)
	var seam_sections=prepare(wide.sectioned_copy(),map,scene,seam_plan,catalog,800)
	check(not seam_dense.placements.is_empty() and seam_dense.placements==seam_sections.placements,"lazy support across section seam preserves exact positions at different frame budgets")
	map.compact_smooth_study_column_limit=0
	var capped:=Grove.new();check(not capped.begin(wide,map,scene,recipe("placement"),catalog),"default budget remains enforced")
	var placements_checked:=0
	for kind: String in ["grove","placement"]:
		var plan:=recipe(kind)
		var job=prepare(source,map,scene,plan,catalog)
		check(not job.placements.is_empty(),kind+" produces objects")
		var repeat=prepare(source,map,scene,plan,catalog,800)
		check(job.placements==repeat.placements,"budget parity "+kind)
		var sectioned=prepare(source.sectioned_copy(),map,scene,plan,catalog)
		check(job.placements==sectioned.placements,"sectioned parity "+kind)
		for spec in job.placements:
			spec.kind=kind
			var bottom: float=spec.transform.origin.y/16.0+(job._template_bounds[spec.model_id].position.y/16.0 if kind=="placement" else 0.0)
			check(absf(bottom-support(map,job,spec))<0.00001,"physical support "+kind)
			placements_checked+=1
		# A changed style or map frame must invalidate a prepared preview.
		check(not job.stale(),"fresh preview")
		map.compact_ground_style=0;check(job.stale(),"style invalidates preview")
		map.compact_ground_style=1;await settle(projection)
		map.position.x+=1;check(job.stale(),"frame invalidates preview");map.position.x-=1
		var cancelled:=Grove.new();check(cancelled.begin(source,map,scene,plan,catalog),"cancel begins")
		cancelled.step(1);cancelled.cancel();cancelled.step()
		check(cancelled.placements.is_empty() and cancelled._smooth_fields.is_empty() and cancelled._smooth_job==null,"cancel releases smooth preparation")
	# Voxel mode retains its original five-column support calculation.
	map.compact_ground_style=0;await settle(projection)
	var legacy=prepare(source,map,scene,recipe("placement"),catalog)
	check(legacy._smooth_fields.is_empty(),"voxel mode never prepares smooth fields")
	for spec in legacy.placements:
		spec.kind="placement"
		check(absf(spec.transform.origin.y/16.0+legacy._template_bounds[spec.model_id].position.y/16.0-support(map,legacy,spec))<0.00001,"legacy support")
	map.compact_ground_style=1;await settle(projection)
	var plan:=recipe("placement");var job=prepare(source,map,scene,plan,catalog)
	# Detailed stone can lie below its source column: reject water according
	# to the rendered/physical support too, even when the raw column is dry.
	var water_checked:=false
	for z in range(16,112,4):
		for x in range(16,112,4):
			var p:=Vector2(x+0.25,z+0.25)
			var floor_sample: Dictionary=projection.floor_surface_sample(job._frame*Vector3(p.x,0,p.y))
			var level:=ceili((job._frame.affine_inverse()*floor_sample.position).y-source.origin_y)
			var index: int=source.column_index(x,z)
			if level<=0 or level>=source.heights[index]:continue
			source.water_levels[index]=level;source.water_materials[index]=5
			check(not is_finite(job._ground(p/16.0,50.0)),"water over smooth surface rejected")
			source.water_levels[index]=0;source.water_materials[index]=0;water_checked=true;break
		if water_checked:break
	check(water_checked,"wet smooth/raw counterexample exercised")
	# Translated, rotated and scaled maps still use their one projection frame.
	map.transform=Transform3D(Basis(Vector3.UP,0.3).scaled(Vector3(1.2,0.9,1.1)),Vector3(10,3,-4))
	var transformed=prepare(source,map,scene,plan,catalog)
	for spec in transformed.placements:
		spec.kind="placement"
		check(absf(spec.transform.origin.y/16.0+transformed._template_bounds[spec.model_id].position.y/16.0-support(map,transformed,spec))<0.00001,"transformed map support")
	map.transform=Transform3D.IDENTITY
	var delta: Dictionary=job.finalize(map.get_node("Props"));check(not delta.is_empty(),"finalize")
	var history:=UndoRedo.new();history.create_action("Objects")
	history.add_do_method(Grove.apply_delta.bind(delta,true));history.add_undo_method(Grove.apply_delta.bind(delta,false));history.commit_action()
	map.set_meta(Plan.META,delta.plan)
	check(map.get_node("Props").get_child_count()==job.placements.size(),"Apply matches preview")
	history.undo();check(map.get_node("Props").get_child_count()==0,"atomic Undo")
	history.redo();check(map.get_node("Props").get_child_count()==job.placements.size(),"Redo")
	var mixed:Resource=delta.plan.working_copy()
	var first:Dictionary=mixed.object_layers.values()[0][0]
	first.expected=Grove.fingerprint(delta.added[0],map,job._frame,"",{},true)
	var compatible=prepare(source,map,scene,mixed,catalog)
	check(compatible.protected_members.is_empty(),"legacy and v2 fingerprints coexist without discarding protection")
	var prop:=delta.added[0] as EmberVoxelProp;prop.position.x+=3;var manual:=prop.transform
	var updated=prepare(source,map,scene,delta.plan,catalog)
	check(prop in updated.protected_nodes and prop not in updated.removals,"manual object protected")
	check(prop.transform==manual and source.same_terrain_data(original),"manual pose and terrain preserved")
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack authored map")
	var path:=DIR.path_join("map.tscn");check(ResourceSaver.save(packed,path)==OK,"Save")
	var reopened=(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),delta.plan),"recipe Reopen")
	check(reopened.get_node("Map/Props").get_child_count()==delta.added.size(),"objects Reopen")
	check(reopened.get_node("Map").compact_ground_style==1 and reopened.get_node("Map").compact_terrain.same_terrain_data(original),"surface/source Reopen")
	reopened.free();history.clear_history();history.free();scene.queue_free();await process_frame
	print("SMOOTH_PLACEMENT ","PASS" if errors.is_empty() else "FAIL"," support/legacy/budget/sections/style/frame/cancel/manual/Apply/Undo/Redo/Save/Reopen objects=",placements_checked," worst_step_ms=",worst_step_us/1000.0," errors=",errors)
	quit(0 if errors.is_empty() else 1)
