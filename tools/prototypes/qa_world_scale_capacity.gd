extends SceneTree
## Reproducible scale dataset/admission probe. Never instantiates a large world.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Creation=preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_plan_math.gd")
const Generation=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const SEED:=20261029
const SIDES: Array[int]=[72,144,288,576]
var output:="C:/Users/novos/Documents/Codex/2026-10-29/ember-scale-576"
var capacity_only:=false
var verify_only:=false
func _initialize()->void:run.call_deferred()
func header(side:int,part:Resource)->Resource:
	var source:=Terrain.new()
	source.schema_version=Terrain.SECTION_SCHEMA_VERSION
	source.width=side*16;source.depth=side*16;source.height_limit=part.height_limit
	source.palette=part.palette;source.palette_surface_roles=part.palette_surface_roles;source.palette_material_ids=part.palette_material_ids
	for z in side/24:
		for x in side/24:source.sections[Vector2i(x,z)]=part
	return source
func candidate_points(side:int,models:Array,seed_value:int,count_per_72:float)->Array:
	var settings:Dictionary=Math.GROVE_DEFAULTS.duplicate()
	settings.model_ids=models;settings.seed=seed_value;settings.spacing_m=4.0
	settings.density=count_per_72*16.0/(72.0*72.0);settings.pattern="groups"
	var noise:=Math.placement_group_noise(settings)
	var result:Array=[]
	for z in ceili(side/4.0):
		for x in ceili(side/4.0):
			var point:Dictionary=Math.grove_candidate(Rect2i(0,0,side,side),settings,Vector2i(x,z),noise)
			if not point.is_empty():
				point.model=models[point.variant];result.append(point)
	return result
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--capacity-only":capacity_only=true
		elif arg=="--verify":verify_only=true
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	if verify_only:
		verify_saved()
		return
	var creator:=Creation.new()
	assert(creator.prepare_sections("scale_seed_part",1,1,24),creator.error)
	var part:Resource=creator.source
	var results:Array=[]
	for side in SIDES:
		var source:Resource=header(side,part)
		var extent_errors:Array[String]=source.validation_errors()
		var map:=Map.new();map.compact_smooth_study_column_limit=1572864
		map.compact_ground_style=1;map.compact_terrain=source
		var counts:Dictionary={"side_m":side,"logical_columns":source.width*source.depth,"section_count":source.sections.size(),"tile_count":source.tile_keys(64).size(),"section_errors":extent_errors,"detailed_admitted":map.compact_ground_style==1,"current_detailed_budget":map.smooth_column_limit()}
		map.free()
		results.append(counts)
		print("SCALE_ADMISSION ",JSON.stringify(counts))
		if capacity_only:continue
		var sampler:=Generation.new();var settings:Dictionary=Generation.DEFAULTS.duplicate()
		settings.profile="hills";settings.land_shape="mainland";settings.seed=SEED;settings.sea_m=0.0;settings.land_m=2.0;settings.relief_m=2.0
		sampler.configure(Rect2(0,0,576,576),settings)
		# Unique generated height payloads, not repeated copies of the small map.
		# The same world-coordinate sampler makes the smaller worlds true prefixes.
		var began:=Time.get_ticks_usec()
		for key:Vector2i in source.sections:
			var payload:Resource=part.working_copy()
			var heights:=PackedInt32Array();var segment:=PackedInt32Array();segment.resize(16)
			for z in 24:
				var row:=PackedInt32Array()
				for x in 24:
					var point:=Vector2(key*24+Vector2i(x,z))
					segment.fill(clampi(roundi(sampler.height_m(point)*4.0)*4,4,128));row.append_array(segment)
				for dz in 16:heights.append_array(row)
			payload.heights=heights;source.sections[key]=payload
			if (key.y*(side/24)+key.x)%24==0:await process_frame
		var errors:Array[String]=source.validation_errors()
		counts.generation_ms=(Time.get_ticks_usec()-began)/1000.0;counts.generated_validation=errors
		if not errors.is_empty():continue
		var path:=output.path_join("terrain_%d.res"%side)
		counts.save_error=ResourceSaver.save(source,path,ResourceSaver.FLAG_COMPRESS)
		var trees:=candidate_points(side,["res://prefabs/voxels/vox_painted_oak.tscn","res://prefabs/voxels/vox_painted_birch.tscn"],SEED,8.0)
		var rocks:=candidate_points(side,["res://prefabs/voxels/vox_painted_rock_group.tscn","res://prefabs/voxels/vox_external_coastal_rock.tscn"],SEED+1,5.0)
		var dense:Array=[]
		if side>=288:
			var settings_dense:Dictionary=Math.GROVE_DEFAULTS.duplicate();settings_dense.model_ids=["res://prefabs/voxels/vox_painted_oak.tscn","res://prefabs/voxels/vox_painted_birch.tscn"]
			settings_dense.seed=SEED+2;settings_dense.spacing_m=4.0;settings_dense.density=0.9
			for z in 12:
				for x in 12:
					var item:Dictionary=Math.grove_candidate(Rect2i(240,240,48,48),settings_dense,Vector2i(x,z))
					if not item.is_empty():item.model=settings_dense.model_ids[item.variant];dense.append(item)
		counts.tree_candidates=trees.size();counts.rock_candidates=rocks.size();counts.dense_forest_candidates=dense.size()
		counts.estimated_detail_instances=77878*(side/72)*(side/72)
		counts.placement_admitted=trees.size()+rocks.size()+dense.size()<=Plan.new().member_limit(Vector2i(side,side)) and dense.size()<=Plan.region_member_limit(Rect2i(240,240,48,48))
		var population:Dictionary={"phase":"candidate_plan_not_spawned","seed":SEED,"trees":trees,"rocks":rocks,"dense_forest":dense,"grass_reference_instances_per_72m":77878,"grass_generator":"res://scripts/ember_detail_scatter.gd"}
		FileAccess.open(output.path_join("population_%d.bin"%side),FileAccess.WRITE).store_var(population)
		FileAccess.open(output.path_join("progress.json"),FileAccess.WRITE).store_string(JSON.stringify(results))
		print("SCALE_DATA_READY ",JSON.stringify(counts))
		await process_frame
	var result:Dictionary={"seed":SEED,"phase":"capacity_only" if capacity_only else "data_and_candidate_plan","cases":results,"renderer_pass":false,"renderer_note":"Large scene not instantiated: current detailed/placement admission and full queue must be fixed before render measurement. No FPS claim."}
	FileAccess.open(output.path_join("capacity.json" if capacity_only else "dataset.json"),FileAccess.WRITE).store_string(JSON.stringify(result))
	quit()

func verify_saved()->void:
	var failures:Array[String]=[]
	var cases:Array=[]
	var sampler:=Generation.new();var settings:Dictionary=Generation.DEFAULTS.duplicate()
	settings.profile="hills";settings.land_shape="mainland";settings.seed=SEED;settings.sea_m=0.0;settings.land_m=2.0;settings.relief_m=2.0
	sampler.configure(Rect2(0,0,576,576),settings)
	for side in SIDES:
		var began:=Time.get_ticks_usec()
		var source:Resource=load(output.path_join("terrain_%d.res"%side))
		if source==null:
			failures.append("missing source %d"%side)
			continue
		var errors:Array[String]=source.validation_errors()
		if not errors.is_empty():failures.append("invalid source %d: %s"%[side,errors])
		if source.width!=side*16 or source.depth!=side*16 or source.sections.size()!=(side/24)*(side/24):failures.append("extent %d"%side)
		# Verify generated data at every section edge and centre after decoding.
		var samples:=0
		for key:Vector2i in source.sections:
			for offset in [Vector2i.ZERO,Vector2i(12,12),Vector2i(23,23)]:
				var point:Vector2i=key*24+offset
				var expected:=clampi(roundi(sampler.height_m(Vector2(point))*4.0)*4,4,128)
				if source.column_value("heights",source.column_index(point.x*16,point.y*16))!=expected:failures.append("height %d %s"%[side,point])
				samples+=1
		var population:Dictionary=FileAccess.open(output.path_join("population_%d.bin"%side),FileAccess.READ).get_var()
		for entry in ["trees","rocks","dense_forest"]:
			for item:Dictionary in population[entry]:
				if not ResourceLoader.exists(item.model):failures.append("missing model %s"%item.model)
		cases.append({"side_m":side,"samples":samples,"validation":errors,"decode_and_verify_ms":(Time.get_ticks_usec()-began)/1000.0})
		source=null
	var result:Dictionary={"pass":failures.is_empty(),"errors":failures,"cases":cases,"renderer_pass":false}
	FileAccess.open(output.path_join("verify.json"),FileAccess.WRITE).store_string(JSON.stringify(result))
	print("SCALE_SAVED_VERIFY ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
