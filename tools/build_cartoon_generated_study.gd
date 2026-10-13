extends SceneTree
## All three operations use the exact job from the existing generation panel.
const Generation=preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const PARAMS={"profile":"hills","seed":71,"sea_m":1.25,"land_m":0.9,"relief_m":2.5,"feature_m":11.0,"shore_m":2.4,"land_fraction":0.86}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var original=load("res://scenes/compact_cartoon_ground_study.tscn").instantiate()
	var source=original.get_node("Map").compact_terrain.working_copy()
	var job:=Generation.new()
	if not job.begin(source,Rect2i(0,0,24,16),PARAMS):printerr(job.error);quit(1);return
	while not job.finished:job.step(4000)
	var base=job.candidate.dense_window(Rect2i(0,0,384,256))
	base.palette_material_ids=PackedStringArray(["","cartoon_soil","cartoon_grass","cartoon_sand","cartoon_relief_stone",""])
	var coverage_params:=PARAMS.duplicate(true);coverage_params.merge({"terrain_operation":"coverage","coverage_seed":731,"coverage_scale":1.0,"coverage_sea_m":PARAMS.sea_m},true)
	var cover_job:=Generation.new()
	if not cover_job.begin(base,Rect2i(0,0,24,16),coverage_params):printerr(cover_job.error);quit(1);return
	while not cover_job.finished:cover_job.step(4000)
	base=cover_job.candidate.dense_window(Rect2i(0,0,384,256))
	var detail_params:=PARAMS.duplicate(true);detail_params.merge({"terrain_operation":"detail","surface_seed":731,"surface_scale":1.0,"surface_strength":.7},true)
	var detail_job:=Generation.new()
	if not detail_job.begin(base,Rect2i(0,0,24,16),detail_params):printerr(detail_job.error);quit(1);return
	while not detail_job.finished:detail_job.step(4000)
	var detail=detail_job.candidate.dense_window(Rect2i(0,0,384,256))
	var counts: Dictionary={"grass":0,"soil":0,"sand":0,"stone":0}
	for z in base.depth:
		for x in base.width:
			var index: int=base.column_index(x,z)
			var role:=base.surface_role_for_palette(base.top_materials[index])
			counts[role]+=1
	var paths: Dictionary={"base":"res://content/world_terrains/cartoon_generated_base.res","detail":"res://content/world_terrains/cartoon_generated_detail.res"}
	for kind: String in paths:
		var terrain=base if kind=="base" else detail
		if not terrain.validation_errors().is_empty():printerr(terrain.validation_errors());quit(1);return
		if ResourceSaver.save(terrain,paths[kind])!=OK:quit(1);return
	original.name="CartoonGeneratedStudy";original.baseline_terrain=load(paths.base)
	var map=original.get_node("Map");map.map_id="cartoon_generated_study"
	map.compact_terrain=load(paths.detail);map.compact_smooth_material_blend=true
	original.get_node("Instructions/Caption").text="Сгенерированный остров · B — основа / фактура · ПКМ — камера · колесо — масштаб · L — свет"
	var packed:=PackedScene.new();packed.pack(original)
	if ResourceSaver.save(packed,"res://scenes/compact_cartoon_generated_study.tscn")!=OK:quit(1);return
	original.free();print("CARTOON_GENERATED_FIXTURE PASS counts=",counts," generator_ms=",job.elapsed_us/1000.0," worst_step_ms=",job.worst_step_us/1000.0)
	quit()
