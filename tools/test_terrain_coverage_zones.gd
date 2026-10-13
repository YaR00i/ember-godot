extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const Forms=preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func parameters() -> Dictionary:
	var values:=Math.DEFAULTS.duplicate(true);values.merge(Math.COVERAGE_DEFAULTS,true);values.merge(Math.ZONE_DEFAULTS,true)
	values.terrain_operation="coverage";return values
func build(source,values: Dictionary,plan: Resource=null,budget:=4000):
	var job:=Generation.new();check(job.begin(source,Rect2i(0,0,source.width/16,source.depth/16),values,false,plan),job.error)
	var deadline:=Time.get_ticks_msec()+60000
	while job.candidate!=null and not job.finished and Time.get_ticks_msec()<deadline:job.step(budget)
	check(job.finished and job.candidate!=null,"bounded job finishes")
	return job
func count_role(source,role: String) -> int:
	var slot: int=source.palette_surface_roles.find(role);var count:=0
	for z in source.depth:
		for x in source.width:
			if source.column_value("top_materials",source.column_index(x,z))==slot:count+=1
	return count
func boundaries(source) -> int:
	var count:=0
	for z in source.depth-1:
		for x in source.width-1:
			var i: int=source.column_index(x,z);var slot: int=source.column_value("top_materials",i)
			count+=int(slot!=source.column_value("top_materials",source.column_index(x+1,z)))+int(slot!=source.column_value("top_materials",source.column_index(x,z+1)))
	return count
func flat() -> EmberTerrainPilotResource:
	var source:=Fixture.base();source.width=384;source.depth=256
	for channel: String in source.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(source.width*source.depth);data.fill(64 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0);source.set(channel,data)
	return source
func run() -> void:
	var source:=flat();var original:=source.working_copy();var values:=parameters()
	var covered=build(source,values)
	var legacy:=values.duplicate(true);legacy.erase("coverage_profile");legacy.coverage_sea_m=0.0
	var old=build(source,legacy)
	var new_edges:=boundaries(covered.candidate);var old_edges:=boundaries(old.candidate)
	check(new_edges<old_edges*0.5,"large zones reduce fragmentation")
	check(count_role(covered.candidate,"soil")>0 and count_role(covered.candidate,"grass")>source.width*source.depth/2,"grass base with soil pockets")
	for channel: String in source.Sections.CHANNELS:
		if channel not in ["top_materials","base_materials"]:check(covered.candidate.dense_window(Rect2i(0,0,384,256)).get(channel)==source.get(channel),"coverage preserves "+channel)
	check(source.same_terrain_data(original),"source immutable")
	var unrelated:=values.duplicate(true);unrelated.merge({"surface_strength":1.0,"surface_seed":999,"surface_scale":3.0,"seed":777,"relief_m":24.0,"coverage_scale":8.0,"coverage_sea_m":16.0},true)
	check(build(source,unrelated).candidate.same_terrain_data(covered.candidate),"zones independent from detail/macro/legacy knobs")
	check(build(source.sectioned_copy(),values,null,700).candidate.same_terrain_data(covered.candidate),"sections/budget parity")
	var fewer:=values.duplicate(true);fewer.coverage_soil_amount=0.0
	check(count_role(build(source,fewer).candidate,"soil")==0,"soil can be disabled")
	var more:=values.duplicate(true);more.coverage_soil_amount=1.0
	check(count_role(build(source,more).candidate,"soil")>count_role(covered.candidate,"soil"),"soil frequency changes coverage")
	var smaller:=values.duplicate(true);smaller.coverage_zone_m=4.0
	check(boundaries(build(source,smaller).candidate)>new_edges,"zone size affects shape scale")
	# Wet band: width follows current water, not a hard-coded sea height.
	var wet:=Fixture.base()
	for i in wet.heights.size():
		wet.heights[i]=32;wet.top_materials[i]=2
		if i/128<16:wet.water_levels[i]=48;wet.water_materials[i]=5
	var coast:=fewer.duplicate(true);coast.coverage_stone_slope=100.0
	var sand=build(wet,coast)
	check(sand.candidate.column_value("top_materials",64+24*128)==3 and sand.candidate.column_value("top_materials",64+88*128)==2,"sand near actual water only")
	var dry:=coast.duplicate(true);dry.coverage_sand_width_m=0.0
	check(build(wet,dry).candidate.column_value("top_materials",64+24*128)==2,"zero shore width disables sand")
	# A broad incline creates stone, while high threshold restores grass.
	var slope:=Fixture.base()
	for i in slope.heights.size():slope.heights[i]=32+roundi((i%128)*0.6);slope.top_materials[i]=2
	var rocky:=fewer.duplicate(true);rocky.coverage_stone_slope=25.0
	check(build(slope,rocky).candidate.column_value("top_materials",64+64*128)==4,"stone on broad slope")
	rocky.coverage_stone_slope=100.0
	check(build(slope,rocky).candidate.column_value("top_materials",64+64*128)==2,"stone slope threshold independent")
	# Manual paint is protected even when the chosen colour was already there.
	for sectioned in [false,true]:
		var painted:=Fixture.base().sectioned_copy() if sectioned else Fixture.base()
		var map:=Map.new();map.compact_terrain=painted
		var history:=UndoRedo.new();var brush:=Brush.new();brush.configure({"resource":painted,"target":weakref(map)},history,map)
		var snapshot:=painted.working_copy()
		brush.begin("paint",0.3,1,2,0,16,0,1,0);brush.stamp(Vector2i(64,64));brush.end()
		var protected: Resource=Plan.read(map)
		check(protected!=null and Plan.paint_locked(protected.paint_locks,Vector2i(64,64)),"same-colour paint protects")
		history.undo();check(Plan.read(map)==null and painted.same_terrain_data(snapshot),"paint and protection one Undo")
		history.redo();check(Plan.same(Plan.read(map),protected),"paint protection Redo")
		var forced:=more.duplicate(true);forced.coverage_zone_m=8.0
		var preserved=build(painted,forced,protected)
		check(preserved.candidate.column_value("top_materials",64+64*128)==painted.column_value("top_materials",64+64*128) and preserved.protected_paint_columns>0,"generator skips manual paint")
		var released: Resource=protected.working_copy();released.protect_paint_area(Rect2i(0,0,128,128),false)
		check(released.paint_locks.is_empty() and not protected.paint_locks.is_empty(),"release is copy-safe")
		protected.protect_paint_area(Rect2i(0,0,128,128),true)
		check(build(painted,forced,protected).candidate.same_terrain_data(painted.sectioned_copy()),"protected whole selection exact")
		check(Plan.from_data(protected.data()).data()==protected.data(),"protection roundtrip")
		var translated: Resource=protected.translated(Vector2i(1,3))
		check(Plan.paint_locked(translated.paint_locks,Vector2i(80,112)) and not Plan.paint_locked(translated.paint_locks,Vector2i(1,1)),"protection follows map expansion")
		history.clear_history();history.free();map.free()
	var plan:=Plan.new();plan.schema_version=9;plan.regions=[{"id":"zones","name":"Зоны","kind":"generation","bounds":Rect2i(0,0,24,16),"parameters":values}]
	check(not plan.validation_errors().is_empty(),"new recipe cannot masquerade as v9")
	plan.schema_version=Plan.VERSION;check(plan.validation_errors().is_empty() and Plan.from_data(plan.data())!=null,"new recipe version")
	for invalid in [{"coverage_profile":"wrong"},{"coverage_zone_m":NAN},{"coverage_soil_amount":2.0},{"coverage_stone_slope":0.0},{"coverage_sand_width_m":7.0}]:
		var bad:=values.duplicate(true);bad.merge(invalid,true);check(not Math.parameter_error(bad).is_empty(),"parameter validation")
	var cancelled:=Generation.new();cancelled.begin(source,Rect2i(0,0,24,16),values);cancelled.step(700);cancelled.cancel()
	check(cancelled.candidate==null and cancelled._coverage_field==null and source.same_terrain_data(original),"cancel releases field without mutation")
	var dialog:=Dialog.new();root.add_child(dialog);dialog.open_for(Rect2i(0,0,24,16));dialog._operation.select(2);dialog._operation.item_selected.emit(2)
	check(dialog.parameters().coverage_profile=="large" and dialog.parameters().coverage_soil_amount==0.2,"new UI defaults")
	dialog.open_plan(Rect2i(0,0,24,16),legacy);check(dialog.parameters().coverage_profile=="legacy" and not dialog._coverage_zone_grid.visible,"old recipe retains old profile")
	dialog.open_plan(Rect2i(0,0,24,16),values);check(dialog.parameters().coverage_zone_m==12 and dialog._coverage_zone_grid.visible,"new recipe UI roundtrip")
	dialog.queue_free();await process_frame
	print("COVERAGE_ZONES ","PASS" if errors.is_empty() else "FAIL"," edges old/new=",old_edges,"/",new_edges," soil=",count_role(covered.candidate,"soil")," plan10/protection/fields/independence/legacy/Undo/UI/cancel errors=",errors)
	quit(0 if errors.is_empty() else 1)
