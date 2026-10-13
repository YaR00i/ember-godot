extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Editor=preload("res://addons/ember_import/ember_world_editor.gd")
const Preview=preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
var errors: Array[String]=[]
const AREA:=Rect2i(4,2,12,12)
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func build(source,params: Dictionary,budget:=4000):
	var job:=Generation.new();check(job.begin(source,AREA,params),job.error)
	if job.candidate==null:return job
	var calls:=0
	while not job.finished and calls<10000:job.step(budget);calls+=1
	check(job.finished and job.candidate.validation_errors().is_empty(),"bounded valid generation")
	return job
func channel_digest(source,channel: String) -> String:
	var data: PackedByteArray=source.dense_window(Rect2i(0,0,source.width,source.depth)).get(channel)
	return data.hex_encode().sha256_text()
func distance(a,b) -> int:
	var sum:=0
	for z in range(AREA.position.y*16,AREA.end.y*16):
		for x in range(AREA.position.x*16,AREA.end.x*16):sum+=absi(a.column_value("heights",a.column_index(x,z))-b.column_value("heights",b.column_index(x,z)))
	return sum
func run() -> void:
	var source=load("res://content/world_terrains/cartoon_generated_base.res")
	var before=source.working_copy()
	var params:=Math.DEFAULTS.duplicate(true);params.merge({"seed":71,"sea_m":1.25,"land_m":0.9,"relief_m":2.5,"feature_m":11.0,"shore_m":2.4},true)
	var legacy=build(source,params)
	var zero:=params.duplicate(true);zero.merge(Math.SURFACE_DEFAULTS,true)
	check(legacy.candidate.same_terrain_data(build(source,zero).candidate),"strength zero exactly preserves legacy output")
	var enabled:=zero.duplicate(true);enabled.surface_strength=1.0
	var full=build(source,enabled)
	var low:=enabled.duplicate(true);low.surface_strength=0.5
	var half=build(source,low)
	check(distance(legacy.candidate,full.candidate)>distance(legacy.candidate,half.candidate) and distance(legacy.candidate,half.candidate)>0,"strength controls geometric amplitude")
	check(channel_digest(full.candidate,"top_materials")==channel_digest(half.candidate,"top_materials"),"strength preserves detail distribution")
	var other:=enabled.duplicate(true);other.surface_seed+=1
	var variant=build(source,other,900)
	check(distance(full.candidate,variant.candidate)>0,"independent seed changes details")
	var scaled:=enabled.duplicate(true);scaled.surface_scale=2.0
	var large=build(source,scaled)
	check(distance(full.candidate,large.candidate)>0,"scale changes geometric pattern")
	for p: Vector2 in [Vector2(5,4),Vector2(9,7),Vector2(13,10)]:
		check(full._sampler.height_m(p)==variant._sampler.height_m(p) and full._sampler.height_m(p)==large._sampler.height_m(p),"detail seed/scale leave macro sampler unchanged")
	var repeat=build(source,enabled,700)
	check(full.candidate.same_terrain_data(repeat.candidate),"finish independent of work budget")
	var added:=Generation.new()
	check(added.begin(source,Rect2i(24,0,24,24),enabled,true),"new-section surface generation begins")
	while not added.finished:added.step(900)
	check(added.candidate.validation_errors().is_empty(),"new-section finished terrain valid")
	for z in range(0,source.depth,7):
		for x in range(0,source.width,7):
			check(added.candidate.column_value("heights",added.candidate.column_index(x,z))==source.heights[source.column_index(x,z)],"new-section finish preserves existing terrain")
	check(full.worst_step_us<25000,"surface calculation stays sliced")
	for z in source.depth:
		for x in source.width:
			var index: int=source.column_index(x,z)
			if not Rect2i(AREA.position*16,AREA.size*16).has_point(Vector2i(x,z)):
				check(full.candidate.column_value("heights",index)==source.heights[index] and full.candidate.column_value("top_materials",index)==source.top_materials[index],"outside selection unchanged")
			else:
				check(full.candidate.column_value("water_levels",index)==legacy.candidate.column_value("water_levels",index),"water intent same as macro generation")
	check(source.same_terrain_data(before),"input untouched")
	var cancelled:=Generation.new();check(cancelled.begin(source,AREA,enabled),"cancel begin")
	while not cancelled._surface_phase:cancelled.step(700)
	cancelled.cancel();check(cancelled.candidate==null and cancelled._macro==null and source.same_terrain_data(before),"cancel releases private finishing snapshot")
	for pair in [["surface_strength",NAN],["surface_strength",1.1],["surface_scale",0.0],["surface_scale",INF],["surface_seed",1.5],["surface_seed",-1]]:
		var bad:=enabled.duplicate(true);bad[pair[0]]=pair[1]
		check(not Math.parameter_error(bad).is_empty(),"invalid surface parameter rejected")
	var bounded:=Generation.new();check(not bounded.begin(source,Rect2i(0,0,33,12),enabled) and bounded.error.contains("32"),"surface area limit explicit")
	var dialog:=Dialog.new();root.add_child(dialog);await process_frame
	dialog.open_for(AREA)
	check(dialog.parameters().surface_strength==0.0 and not dialog._surface_fields.surface_seed.editable,"legacy default and inactive detail controls")
	dialog._surface_fields.surface_strength.value=70;dialog._surface_fields.surface_scale.value=1.5;dialog._surface_fields.surface_seed.value=88
	var chosen: Dictionary=dialog.parameters()
	check(absf(chosen.surface_strength-0.7)<0.00001 and chosen.surface_scale==1.5 and chosen.surface_seed==88,"UI units route correctly")
	dialog.open_plan(AREA,chosen);check(dialog.parameters()==chosen,"plan panel restores detail controls")
	var old:=params.duplicate(true);dialog.open_plan(AREA,old);check(dialog.parameters().surface_strength==0.0 and dialog.parameters().surface_seed==731,"old plan gets zero-strength defaults")
	var plan:=Plan.new();plan.regions=[{"id":"surface","name":"Фактура","bounds":AREA,"parameters":chosen,"enabled":true,"kind":"generation"}]
	plan.schema_version=Plan.VERSION
	check(plan.validation_errors().is_empty(),"plan validates surface settings")
	check(ResourceSaver.save(plan,"user://surface-generation-plan.tres")==OK,"plan Save")
	var saved=ResourceLoader.load("user://surface-generation-plan.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.data()==plan.data(),"plan Reopen retains all three controls")
	plan.regions[0].bounds=Rect2i(0,0,33,12);check(not plan.validation_errors().is_empty(),"plan rejects unsupported detail area")
	dialog.queue_free()
	var packed=load("res://scenes/compact_cartoon_generated_study.tscn")
	var scene=packed.instantiate();root.add_child(scene)
	var map:=scene.get_node("Map") as EmberMapLoader
	var projection=map._visual_surface_projection
	while projection.pending_tile_count()>0:await process_frame
	var preview:=Preview.new();map.add_child(preview)
	check(preview.show_area(map,full.candidate,Rect2i(AREA.position*16,AREA.size*16)),"native preview opens")
	while not preview._pending.is_empty():await process_frame
	var expected:=Mesher.build_tile(full.candidate,64,64,64,projection.water_mesh_step,projection.water_volume_sides,PackedVector4Array(),{},false,false,true,true)
	var mesh: ArrayMesh=preview.get_node("PreviewTile_1_1").get_child(0,true).mesh
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==expected.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"preview uses exact smooth candidate geometry")
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==expected.terrain.surface_get_arrays(0)[Mesh.ARRAY_COLOR],"preview uses same feathered materials")
	preview.clear_preview();preview.queue_free();scene.queue_free();await process_frame
	print("SURFACE_GENERATION ","PASS" if errors.is_empty() else "FAIL"," full_ms=",full.elapsed_us/1000.0," worst_step_ms=",full.worst_step_us/1000.0," ",errors)
	quit(0 if errors.is_empty() else 1)
