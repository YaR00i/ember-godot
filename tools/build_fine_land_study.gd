extends SceneTree
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Composition=preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for fine in [false,true]:
		var source:=Fixture.base();source.width=512;source.depth=384
		for channel: String in source.Sections.CHANNELS:
			var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
			data.resize(source.width*source.depth);data.fill(32 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 3 if channel=="cap_depths" else 0);source.set(channel,data)
		var params:=Math.DEFAULTS.duplicate(true)
		params.merge({"profile":"hills","seed":71,"sea_m":0.5,"land_m":1.5,"relief_m":0.3,"feature_m":24.0,"shore_m":4.0,"land_fraction":0.9,"terrain_operation":"generate"},true)
		if fine:params.terrain_sampling="fine16"
		var generate:=Generation.new();if not generate.begin(source,Rect2i(0,0,32,24),params):printerr(generate.error);quit(1);return
		while not generate.finished:generate.step(4000)
		source=generate.candidate
		var plan:=Plan.new();plan.schema_version=Plan.VERSION
		var shape:={"height_m":8.0,"summit_m":2.0,"slope_m":7.0}
		if fine:shape.merge({"terrain_sampling":"fine16","mountain_shape":"massif","shape_seed":7})
		# Entire compact footprint stays on dry land; old/new use the same bounds.
		plan.regions=[{"id":"mountain","name":"Горный массив","kind":"mountain","enabled":true,"bounds":Rect2i(8,4,16,16),"parameters":shape}]
		var compose:=Composition.new();if not compose.begin(source,plan):printerr(compose.error);quit(1);return
		while not compose.finished and compose.error.is_empty():compose.step(4000)
		if not compose.error.is_empty():printerr(compose.error);quit(1);return
		source=compose.candidate
		var covers:=params.duplicate(true);covers.merge(Math.COVERAGE_DEFAULTS,true);covers.merge(Math.ZONE_DEFAULTS,true)
		covers.merge({"terrain_operation":"coverage","coverage_soil_amount":0.0,"coverage_stone_slope":75.0,"coverage_sand_width_m":0.5},true)
		var coverage:=Generation.new();if not coverage.begin(source,Rect2i(0,0,32,24),covers):printerr(coverage.error);quit(1);return
		while not coverage.finished:coverage.step(4000)
		source=coverage.candidate.dense_window(Rect2i(0,0,512,384))
		var suffix:="fine" if fine else "legacy"
		var path:="res://content/world_terrains/landform_"+suffix+"_study.res"
		if ResourceSaver.save(source,path)!=OK:quit(1);return
		var scene=load("res://scenes/compact_mountain_anomaly_study.tscn").instantiate()
		scene.name="LandformStudy";scene.walk_test_enabled=false
		scene.anomaly_zones.assign([Vector4(19,15,2.8,0.9)]);scene.orbit_center=Vector3(16,2.5,12)
		var map=scene.get_node("Map");map.compact_terrain=load(path);map.map_id="landform_"+suffix+"_study";map.authored_size_blocks=Vector2i(32,24)
		scene.get_node("Camera3D").look_at_from_position(Vector3(37,23,41),scene.orbit_center)
		scene.get_node("Instructions/Caption").text="Общая форма 32×24 м · гора, подножие и берег · "+suffix
		var packed:=PackedScene.new();packed.pack(scene)
		if ResourceSaver.save(packed,"res://scenes/compact_landform_"+suffix+"_study.tscn")!=OK:quit(1);return
		scene.free()
	print("FINE_LAND_BUILD PASS");quit()
