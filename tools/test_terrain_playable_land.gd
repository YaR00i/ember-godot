extends SceneTree
const TerrainMath = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Generation = preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const TerrainPanel = preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
var errors: Array[String] = []
const GOLDEN := {"hills":[0.25,7.37689623236656,5.93652129173279,2.0025969421036],
	"ridges":[0.25,6.94187541346596,6.13930807023659,2.00167646484037],
	"eroded":[0.25,6.38932159079693,6.60206622461552,2.00134931055946]}
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func recipe_matches(a: Dictionary,b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for key in b:
		if not a.has(key): return false
		if typeof(b[key]) == TYPE_FLOAT:
			if not is_equal_approx(float(a[key]),b[key]): return false
		elif a[key] != b[key]: return false
	return true
func sample(values: Dictionary,bounds := Rect2(0,0,96,96)) -> RefCounted:
	var sampler := TerrainMath.new(); sampler.configure(bounds,values); return sampler
func flat_count(sampler: RefCounted) -> int:
	var count := 0
	for z in range(25,70):
		for x in range(25,70):
			var point := Vector2(x,z); var height: float = sampler.height_m(point)
			if absf(height-sampler.height_m(point+Vector2(0.5,0))) < 0.000001 and absf(height-sampler.height_m(point+Vector2(0,0.5))) < 0.000001: count += 1
	return count
func check_transition_seams(sampler: RefCounted) -> void:
	# Equal-distance lines of competing sites also cross the interior of a
	# third site's cell. Heights must remain continuous there, not only at
	# the boundary where the nearest site changes.
	var sites: Array[Vector2] = []
	for z in range(1,4):
		for x in range(1,4): sites.append(sampler._site(Vector2i(x,z)).point)
	for a in sites.size():
		for b in range(a+1,sites.size()):
			var normal := (sites[b]-sites[a]).normalized()
			var tangent := Vector2(-normal.y,normal.x)
			for offset in range(-12,13):
				var point := (sites[a]+sites[b])*0.5+tangent*float(offset)
				check(absf(sampler.height_m(point-normal*0.0001)-sampler.height_m(point+normal*0.0001)) < 0.005,"jump across competing-site seam")
func build(source: Resource,values: Dictionary,budget: int,size_m := 48) -> RefCounted:
	var job := Generation.new(); check(job.begin(source,Rect2i(0,0,size_m,size_m),values),job.error)
	while not job.finished and job.error.is_empty(): job.step(budget)
	check(job.finished and job.candidate != null,job.error); return job
func _run() -> void:
	var points := [Vector2(3.25,17.75),Vector2(24,24),Vector2(18,17),Vector2(42,24)]
	for profile in GOLDEN:
		var values := TerrainMath.DEFAULTS.duplicate(); values.profile = profile
		var old := sample(values,Rect2(0,0,48,48))
		for i in points.size(): check(absf(old.height_m(points[i])-GOLDEN[profile][i]) < 0.00000001,"legacy sampler changed "+profile)
	var values := TerrainMath.DEFAULTS.duplicate(); values.profile = "plains"
	values.merge(TerrainMath.PLAINS_DEFAULTS); values.micro_m = 0.0; values.flat_fraction = 0.0
	var plain_zero := sample(values); var old_values := TerrainMath.DEFAULTS.duplicate(); var hills := sample(old_values)
	for point in points: check(is_equal_approx(plain_zero.height_m(point),hills.height_m(point)),"zero flatness changed macro height")
	values.land_fraction = 0.9; values.shore_m = 0.5; values.flat_fraction = 1.0
	var plain_full := sample(values); var full_count := flat_count(plain_full)
	check_transition_seams(plain_full)
	values.flat_fraction = 0.0; var zero_count := flat_count(sample(values))
	check(full_count > 800 and full_count > zero_count+600,"flat control ineffective: "+str(full_count)+" / "+str(zero_count))
	values.flat_fraction = 1.0; values.flat_size_m = 32.0
	check(flat_count(sample(values)) > full_count,"larger flat sites did not increase interiors")
	values.flat_size_m = 16.0; values.flat_transition_m = 0.5
	check(flat_count(sample(values)) > full_count,"transition width did not change flat interiors")
	values.flat_transition_m = 2.0
	var repeat := sample(values); var changed := values.duplicate(); changed.seed += 1; var different := sample(changed)
	var changed_samples := 0
	for z in range(24,72,3):
		for x in range(24,72,3):
			var point := Vector2(x,z)
			check(repeat.height_m(point) == plain_full.height_m(point),"deterministic sampler mismatch")
			if not is_equal_approx(repeat.height_m(point),different.height_m(point)): changed_samples += 1
			# A tiny movement must not jump at a Voronoi boundary.
			check(absf(repeat.height_m(point)-repeat.height_m(point+Vector2(0.0001,0.0001))) < 0.005,"cell-boundary discontinuity")
	check(changed_samples > 200,"seed did not change placement")
	changed = values.duplicate(); changed.micro_m = 0.7; var detailed := sample(changed); var variation := 0.0
	for point in points:
		var difference := absf(detailed.height_m(point)-repeat.height_m(point)); variation += difference
		check(difference <= 0.7,"micro detail exceeded budget")
	check(variation > 0.01,"micro control ineffective")
	for key in TerrainMath.PLAINS_DEFAULTS:
		changed = values.duplicate(); changed[key] = NAN; check(not TerrainMath.parameter_error(changed).is_empty(),"NaN accepted "+key)
	changed = values.duplicate(); changed.flat_transition_m = 12.0; check(not TerrainMath.parameter_error(changed).is_empty(),"invalid transition/size accepted")
	var implicit := TerrainMath.DEFAULTS.duplicate(); implicit.profile = "plains"
	check(TerrainMath.parameter_error(implicit).is_empty(),"optional recipe defaults rejected")
	for fraction in [0.3,0.9]:
		changed = implicit.duplicate(); changed.land_fraction = fraction
		check(TerrainMath.parameter_error(changed).is_empty(),"valid island fraction endpoint rejected")
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := TerrainPanel.new(); dock.add_child(panel); await process_frame
	panel.open_plan(Rect2i(0,0,48,48),values)
	check(panel._plains_grid.visible and recipe_matches(panel.parameters(),values),"panel lost persisted profile settings")
	panel.set_ready("Ready"); panel._plains_fields.micro_m.value = 0.35
	check(panel.get_apply_button().disabled,"small profile input retained stale Apply")
	values = panel.parameters()
	for frame in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302,"new fields overflow narrow dock")
	panel._scroll.scroll_vertical = 10000
	for frame in 3: await process_frame
	check(dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()) and dock.get_global_rect().encloses(panel._preview_button.get_global_rect()),"profile actions not pinned")
	panel.open_plateau(Rect2i(0,0,16,16),{"height_m":4.0,"transition_m":3.0})
	check(not panel._plains_grid.visible and panel.parameters() == {"height_m":4.0,"transition_m":3.0},"plains fields leaked into plateau")
	panel.open_plan(Rect2i(0,0,48,48),TerrainMath.DEFAULTS)
	check(not panel._plains_grid.visible and recipe_matches(panel.parameters(),TerrainMath.DEFAULTS),"old recipe changed / gained new keys")
	var plan := Plan.new(); plan.regions = [{"id":"game","name":"Игровая суша","bounds":Rect2i(0,0,48,48),"parameters":values}]
	check(plan.validation_errors().is_empty() and Plan.from_data(plan.data()) != null,"plan rejected profile")
	var scene := Node3D.new(); scene.set_meta(Plan.META,plan)
	var packed := PackedScene.new(); check(packed.pack(scene) == OK,"pack profile plan")
	var folder := "user://ember-tests/playable-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("plan.tscn"); check(ResourceSaver.save(packed,path) == OK,"save profile plan")
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened),plan),"profile plan Save-Reopen"); reopened.free(); scene.free(); dock.free()
	var creation := Creation.new(); check(creation.prepare_sections("playable_fixture",2,2,48),creation.error)
	var source: Resource = creation.source.sectioned_copy(); var before: Resource = source.working_copy()
	var small := build(source,values,1500); var large := build(source,values,50000)
	if small.candidate == null or large.candidate == null: quit(1); return
	check(small.candidate.same_terrain_data(large.candidate) and source.same_terrain_data(before),"budget changed result / preview mutated source")
	print("PLAYABLE_LAND_METRICS flat=",full_count," zero=",zero_count," ms=",small.elapsed_us/1000.0," step_ms=",small.worst_step_us/1000.0," sites=",repeat._sites.size())
	check(creation.prepare_sections("playable_large_fixture",4,4,48),creation.error)
	var large_source: Resource = creation.source.sectioned_copy()
	var max_values := implicit.duplicate(); max_values.merge(TerrainMath.PLAINS_DEFAULTS)
	max_values.flat_size_m = 8.0; max_values.flat_fraction = 1.0
	var max_job := build(large_source,max_values,4000,96)
	check(max_job.candidate != null,"96 m playable generation failed")
	print("PLAYABLE_LAND_96_METRICS ms=",max_job.elapsed_us/1000.0," step_ms=",max_job.worst_step_us/1000.0)
	print("TERRAIN_PLAYABLE_LAND ","PASS" if errors.is_empty() else "FAIL"," legacy/controls/continuity/seed/budget/UI/plan/Save-Reopen/preview/source errors=",errors)
	quit(0 if errors.is_empty() else 1)
