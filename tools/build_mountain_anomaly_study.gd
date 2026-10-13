extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Composition=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
var failed:=false
func _initialize() -> void:run.call_deferred()
func generate(source: Resource,values: Dictionary) -> Resource:
	var job:=Generation.new()
	if not job.begin(source,Rect2i(0,0,32,32),values):printerr(job.error);failed=true;return null
	while not job.finished:job.step(4000)
	print("MOUNTAIN_GENERATION ",values.get("terrain_operation","generate")," ms=",job.elapsed_us/1000.0)
	return job.candidate.dense_window(Rect2i(0,0,512,512))
func run() -> void:
	var values:=Math.DEFAULTS.duplicate(true)
	values.merge({"profile":"plains","seed":71,"sea_m":0.5,"land_m":2.0,"relief_m":0.6,"feature_m":18.0,"shore_m":2.0,"land_fraction":0.9},true)
	var seed_source:=Fixture.base();seed_source.width=512;seed_source.depth=512
	for channel: String in seed_source.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(512*512);data.fill(40 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0)
		seed_source.set(channel,data)
	var source: Resource=generate(seed_source,values)
	if failed:quit(1);return
	var plan:=Plan.new();plan.schema_version=Plan.VERSION
	plan.regions.assign([{"id":"study_mountain","name":"Большая гора","kind":"mountain","enabled":true,"bounds":Rect2i(4,4,24,24),"parameters":{"height_m":18.0,"summit_m":3.0,"slope_m":10.0}}])
	var composition:=Composition.new()
	if not composition.begin(source,plan):printerr(composition.error);quit(1);return
	while not composition.finished:composition.step(4000)
	source=composition.candidate.dense_window(Rect2i(0,0,512,512))
	values.merge(Math.COVERAGE_DEFAULTS,true);values.merge(Math.ZONE_DEFAULTS,true)
	values.merge({"terrain_operation":"coverage","coverage_soil_amount":0.12,"coverage_zone_m":16.0,"coverage_stone_slope":65.0,"coverage_sand_width_m":0.0},true)
	source=generate(source,values)
	if failed:quit(1);return
	values.merge({"terrain_operation":"detail","surface_seed":731,"surface_scale":1.0,"surface_strength":0.45},true)
	source=generate(source,values)
	if failed:quit(1);return
	source.palette_material_ids=PackedStringArray(["","cartoon_soil","cartoon_grass","cartoon_sand","cartoon_relief_stone",""])
	if not source.validation_errors().is_empty():printerr(source.validation_errors());quit(1);return
	var path:="res://content/world_terrains/mountain_anomaly_study.res"
	if ResourceSaver.save(source,path)!=OK:quit(1);return
	var original=load("res://scenes/compact_smooth_tools_study.tscn").instantiate()
	original.name="MountainAnomalyStudy";original.set_script(load("res://scripts/prototypes/ember_mountain_anomaly_study.gd"))
	original.orbit_center=Vector3(16,8,16);original.baseline_terrain=null
	var map=original.get_node("Map");map.map_id="mountain_anomaly_study";map.compact_terrain=load(path);map.authored_size_blocks=Vector2i(32,32)
	var camera:=original.get_node("Camera3D") as Camera3D
	camera.position=Vector3(52,38,57);camera.look_at_from_position(camera.position,original.orbit_center)
	original.get_node("Instructions/Caption").text="Гора 32×32 м · локальное превращение · ПКМ — камера · колесо — масштаб · L — свет"
	var packed:=PackedScene.new();packed.pack(original)
	if ResourceSaver.save(packed,"res://scenes/compact_mountain_anomaly_study.tscn")!=OK:quit(1);return
	original.free();print("MOUNTAIN_FIXTURE PASS summit_m=",source.column_value("heights",source.column_index(256,256))/16.0)
	quit()
