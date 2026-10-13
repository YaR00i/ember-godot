extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Forms=preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func build(source,parameters: Dictionary,area:=Rect2i(0,0,8,8),budget:=4000):
	var job:=Generation.new();check(job.begin(source,area,parameters),job.error)
	if job.candidate==null:return job
	while not job.finished:job.step(budget)
	check(job.candidate.validation_errors().is_empty(),"valid candidate")
	return job
func same_channel(a,b,channel: String) -> bool:
	return a.dense_window(Rect2i(0,0,a.width,a.depth)).get(channel)==b.dense_window(Rect2i(0,0,b.width,b.depth)).get(channel)
func run() -> void:
	var source:=Fixture.base();source.water_flow.resize(64);source.water_flow.fill(Vector2(.25,-.5))
	source.heights[12+12*128]=12;source.water_levels[12+12*128]=32;source.water_materials[12+12*128]=5
	var original:=source.working_copy()
	var params:=Math.DEFAULTS.duplicate(true);params.merge({"terrain_operation":"detail","surface_strength":0.75,"surface_scale":1.0,"surface_seed":731},true)
	var detail=build(source,params)
	check(not same_channel(source,detail.candidate,"heights"),"detail changes relief")
	for channel: String in ["top_materials","base_materials","cap_depths","water_levels","water_materials","water_flow"]:check(same_channel(source,detail.candidate,channel),"detail preserves "+channel)
	check(detail.candidate.height_limit==source.height_limit,"detail keeps source header")
	var layered:=source.working_copy()
	for i in layered.heights.size():layered.cap_depths[i]=layered.heights[i]
	var layered_detail=build(layered,params)
	check(same_channel(layered,layered_detail.candidate,"cap_depths"),"detail never cuts through authored paint-layer depth")
	check(detail.candidate.column_value("heights",12+12*128)==12,"detail preserves underwater floor")
	check(source.same_terrain_data(original),"input immutable")
	var zero:=params.duplicate(true);zero.surface_strength=0.0
	check(build(source,zero).candidate.same_terrain_data(source.sectioned_copy()),"zero detail exactly preserves painted source")
	var forms:=Forms.new();forms.configure(731)
	var changes:=0
	for i in source.heights.size():
		if source.water_levels[i]>0:continue
		var p:=Vector2((i%128+.5)/16.0,(floori(float(i)/128)+.5)/16.0)
		var expected:=forms.brush_offset_voxels(p,source.surface_role_for_palette(source.top_materials[i]),1.0,12,1.0,1,0)
		check(detail.candidate.column_value("heights",i)==source.heights[i]+expected,"same detail maths as old brush")
		if expected!=0:changes+=1
	var coverage:=params.duplicate(true);coverage.terrain_operation="coverage";coverage.merge(Math.COVERAGE_DEFAULTS,true);coverage.coverage_sea_m=0.0
	var covered=build(source,coverage)
	check(not same_channel(source,covered.candidate,"top_materials"),"coverage changes coverings explicitly")
	for channel: String in ["heights","cap_depths","water_levels","water_materials","water_flow"]:check(same_channel(source,covered.candidate,channel),"coverage preserves "+channel)
	var unrelated:=coverage.duplicate(true);unrelated.surface_strength=0.0;unrelated.surface_scale=3.0;unrelated.surface_seed=543
	check(build(source,unrelated).candidate.same_terrain_data(covered.candidate),"coverage independent of detail knobs")
	var shape:=params.duplicate(true);shape.seed=123;shape.relief_m=24.0;shape.sea_m=12.0;shape.coverage_seed=456;shape.coverage_scale=8.0
	check(build(source,shape).candidate.same_terrain_data(detail.candidate),"detail independent of macro and coverage knobs")
	var generated:=Math.DEFAULTS.duplicate(true);generated.terrain_operation="generate"
	var generated_job=build(source,generated)
	check(same_channel(source,generated_job.candidate,"top_materials") and same_channel(source,generated_job.candidate,"base_materials"),"explicit shape generation preserves hand paint")
	var shape_detail:=generated.duplicate(true);shape_detail.merge({"surface_strength":.75,"surface_seed":731,"surface_scale":1.0},true)
	var generated_detail=build(source,shape_detail)
	check(same_channel(generated_job.candidate,generated_detail.candidate,"top_materials"),"macro finish never redistributes coverings")
	var area:=Rect2i(1,1,6,6);var selected=build(source,params,area)
	for i in source.heights.size():
		if not Rect2i(area.position*16,area.size*16).has_point(Vector2i(i%128,i/128)):check(selected.candidate.column_value("heights",i)==source.heights[i],"outside selection preserved")
	check(build(source,params,Rect2i(0,0,8,8),700).candidate.same_terrain_data(detail.candidate),"budget parity")
	var cancelled:=Generation.new();check(cancelled.begin(source,area,params),cancelled.error);cancelled.step(700);cancelled.cancel();check(cancelled.candidate==null and source.same_terrain_data(original),"cancel preserves authoring source")
	for bad in [{"terrain_operation":"wrong"},{"coverage_seed":1.5},{"coverage_scale":NAN},{"coverage_scale":9.0}]:
		var invalid:=params.duplicate(true);invalid.merge(bad,true);check(not Math.parameter_error(invalid).is_empty(),"new recipe validation")
	check(not Math.surface_bounds_error(Rect2i(0,0,33,1),zero).is_empty(),"detail zero still bounded")
	var addition:=Generation.new();check(not addition.begin(source,Rect2i(0,0,24,24),params,true),"surface operation cannot create sections")
	var plan:=Plan.new();plan.regions=[{"id":"detail","name":"Фактура","enabled":true,"kind":"generation","bounds":Rect2i(0,0,8,8),"parameters":params}]
	check(not plan.validation_errors().is_empty(),"operation cannot masquerade as legacy version")
	plan.schema_version=Plan.VERSION
	check(plan.validation_errors().is_empty() and ResourceSaver.save(plan,"user://generation-split-plan.tres")==OK,"optional recipe Plan Save")
	var reopened=ResourceLoader.load("user://generation-split-plan.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.regions[0].parameters==params,"Plan Reopen operation/knobs")
	var old_plan:=Plan.new();old_plan.schema_version=8;old_plan.regions=[{"id":"old","name":"Старый","enabled":true,"kind":"generation","bounds":Rect2i(0,0,8,8),"parameters":Math.DEFAULTS.duplicate(true)}]
	check(Plan.from_data(old_plan.data())!=null and old_plan.schema_version==8,"old v8 preserved on read")
	var dialog:=Dialog.new();root.add_child(dialog);await process_frame
	dialog.open_plan(Rect2i(0,0,8,8),params)
	check(dialog._operation.selected==1 and not dialog._macro_grid.visible and dialog._surface_box.visible and not dialog._plains_grid.visible,"detail UI hides macro")
	check(dialog.parameters().terrain_operation=="detail" and dialog.parameters().surface_strength==.75,"detail UI parameters")
	dialog.open_plan(Rect2i(0,0,8,8),coverage)
	check(dialog._operation.selected==2 and not dialog._surface_box.visible and dialog._coverage_grid.visible,"coverage UI separate knobs")
	check(dialog.parameters().coverage_seed==731 and dialog.parameters().coverage_sea_m==0.0,"coverage UI recipe")
	dialog.open_plan(Rect2i(0,0,8,8),Math.DEFAULTS.duplicate(true));check(dialog._operation.selected==0,"old plans readable")
	dialog.open_for(Rect2i(0,0,24,24),1);check(dialog._operation.disabled and dialog.parameters().terrain_operation=="generate","new sections only generate")
	dialog.queue_free();await process_frame
	print("GENERATION_SPLIT ","PASS" if errors.is_empty() else "FAIL"," changed=",changes," same brush/paint/water/flow/macro/coverage/plan/UI/cancel/budget ",errors)
	quit(0 if errors.is_empty() else 1)
