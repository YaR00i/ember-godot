extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Composition=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const SIZE:=Vector2i(64,48)
var failed:=false
func _initialize() -> void:run.call_deferred()
func generate(source: Resource,values: Dictionary) -> Resource:
	var areas: Array[Rect2i]=[]
	areas.assign([Rect2i(0,0,64,48)] if values.get("terrain_operation","generate")=="generate" else [Rect2i(0,0,32,24),Rect2i(32,0,32,24),Rect2i(0,24,32,24),Rect2i(32,24,32,24)])
	var current: Resource=source
	for area in areas:
		var job:=Generation.new()
		if not job.begin(current,area,values):printerr(job.error);failed=true;return null
		while not job.finished:job.step(4000)
		current=job.candidate
	return current.dense_window(Rect2i(Vector2i.ZERO,SIZE*16))
func run() -> void:
	var seed_source:=Fixture.base();seed_source.width=SIZE.x*16;seed_source.depth=SIZE.y*16
	for channel: String in seed_source.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(seed_source.width*seed_source.depth);data.fill(44 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0)
		seed_source.set(channel,data)
	var values:=Math.DEFAULTS.duplicate(true)
	values.merge({"profile":"plains","seed":71,"sea_m":0.5,"land_m":2.25,"relief_m":0.1,"feature_m":30.0,"shore_m":2.0,"land_fraction":0.9},true)
	var source: Resource=generate(seed_source,values)
	if failed:quit(1);return
	var plan:=Plan.new();plan.schema_version=Plan.VERSION
	var river_params:={"width_m":2.5,"depth_m":0.25,"shore_m":1.5,"flow":0.35}
	var river:=PackedVector2Array([Vector2(18,35),Vector2(14,28),Vector2(15,21),Vector2(13,12),Vector2(9,3)])
	plan.regions.assign([
		{"id":"meadow","name":"Поляна","kind":"plateau","enabled":true,"bounds":Rect2i(18,14,24,24),"parameters":{"height_m":2.75,"transition_m":2.0}},
		{"id":"mountain","name":"Гора сбоку","kind":"mountain","enabled":true,"bounds":Rect2i(32,12,20,20),"parameters":{"height_m":18.0,"summit_m":3.0,"slope_m":8.0}},
		{"id":"walk_mound","name":"Невысокий холмик в пятне","kind":"mountain","enabled":true,"bounds":Rect2i(22,24,10,10),"parameters":{"height_m":3.25,"summit_m":1.0,"slope_m":4.0}},
		{"id":"pond","name":"Исток","kind":"lake","enabled":true,"bounds":Rect2i(14,31,8,8),"parameters":{"water_m":2.25,"depth_m":0.5,"shore_m":1.25}},
		{"id":"river","name":"Речка","kind":"river","enabled":true,"points_m":river,"bounds":Plan.Influence.river_bounds(river,river_params,SIZE),"parameters":river_params}])
	var job:=Composition.new()
	for region: Dictionary in plan.regions:
		if region.kind not in ["mountain","plateau"]:continue
		var wet:=0
		for z in range(region.bounds.position.y*16,region.bounds.end.y*16):
			for x in range(region.bounds.position.x*16,region.bounds.end.x*16):
				var i: int=source.column_index(x,z)
				if source.column_value("water_levels",i)>source.column_value("heights",i):wet+=1
		print("MEADOW_DRY_CHECK ",region.id," wet=",wet)
	if not job.begin(source,plan):printerr(job.error);quit(1);return
	while not job.finished and job.error.is_empty():job.step(4000)
	if job.candidate==null or not job.error.is_empty():printerr(job.error);quit(1);return
	source=job.candidate
	values.merge(Math.COVERAGE_DEFAULTS,true);values.merge(Math.ZONE_DEFAULTS,true)
	values.merge({"terrain_operation":"coverage","coverage_soil_amount":0.08,"coverage_zone_m":20.0,"coverage_stone_slope":65.0,"coverage_sand_width_m":0.8},true)
	source=generate(source,values)
	if failed:quit(1);return
	values.merge({"terrain_operation":"detail","surface_seed":731,"surface_scale":1.0,"surface_strength":0.2},true)
	source=generate(source,values)
	if failed:quit(1);return
	var path:="res://content/world_terrains/meadow_anomaly_study.res"
	if not source.validation_errors().is_empty():printerr(source.validation_errors());quit(1);return
	if ResourceSaver.save(source,path)!=OK:quit(1);return
	var scene=load("res://scenes/compact_mountain_anomaly_study.tscn").instantiate()
	scene.name="MeadowAnomalyWalkStudy";scene.walk_test_enabled=true
	scene.anomaly_zones.assign([Vector4(27,29,3.2,1.0),Vector4(38,30,2.4,0.8)])
	scene.walk_start=Vector2(23,29);scene.walk_route=PackedVector2Array([Vector2(23,29),Vector2(31,29)])
	scene.orbit_center=Vector3(32,3,24)
	var map=scene.get_node("Map");map.compact_smooth_study_column_limit=SIZE.x*SIZE.y*256
	map.compact_terrain=load(path);map.map_id="meadow_anomaly_walk_study";map.authored_size_blocks=SIZE
	var camera:=scene.get_node("Camera3D") as Camera3D
	camera.look_at_from_position(Vector3(92,69,98),scene.orbit_center)
	scene.get_node("Instructions/Caption").text="Поляна 64×48 м · гора сбоку · речка · WASD — ходить · V — камера"
	var packed:=PackedScene.new();packed.pack(scene)
	if ResourceSaver.save(packed,"res://scenes/compact_meadow_anomaly_walk_study.tscn")!=OK:quit(1);return
	scene.free();print("MEADOW_FIXTURE PASS 64x48 meadow/mountain/river");quit()
