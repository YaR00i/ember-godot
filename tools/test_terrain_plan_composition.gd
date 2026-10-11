extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Job = preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const FILE := "user://ember-tests/terrain-composition/terrain.res"
const SCENE := "user://ember-tests/terrain-composition/map.tscn"
func _initialize() -> void: _run.call_deferred()
func compose(source: EmberTerrainPilotResource, plan: Resource, budget := 4000) -> RefCounted:
	var job := Job.new(); assert(job.begin(source, plan), job.error)
	for i in 10000:
		job.step(budget)
		assert(job.error.is_empty(), job.error)
		if job.finished: break
	assert(job.finished and job.candidate.validation_errors().is_empty())
	assert(job.output_plan.validation_errors().is_empty())
	return job
func _run() -> void:
	var creation := Creation.new(); assert(creation.prepare_sections("compose_fixture", 2, 2, 48))
	var source: EmberTerrainPilotResource = creation.source.sectioned_copy()
	var plan := Plan.new(); plan.schema_version = 2
	plan.regions.append({"id": "p", "name": "Равнина", "kind": "plateau", "enabled": true, "bounds": Rect2i(3, 4, 12, 10), "parameters": {"height_m": 5.0, "transition_m": 2.0}})
	var first := compose(source, plan)
	var index: int = source.column_index(8 * 16, 8 * 16)
	assert(first.candidate.column_value("heights", index) == 80)
	assert(source.column_value("heights", index) == 48 and plan.patches.is_empty())
	assert(first.candidate.column_value("heights", 0) == 48)
	var repeat := compose(first.candidate, first.output_plan, 1200)
	assert(repeat.candidate.same_terrain_data(first.candidate), "repeating accumulated deformation")
	assert(Plan.same(repeat.output_plan, first.output_plan), "repeating changed provenance")
	var independent := compose(source, plan, 800)
	assert(independent.candidate.same_terrain_data(first.candidate))
	var moved: Resource = first.output_plan.working_copy(); moved.regions[0].bounds = Rect2i(28, 28, 12, 10)
	var result := compose(first.candidate, moved)
	assert(result.candidate.column_value("heights", index) == 48, "old footprint not restored")
	assert(result.candidate.column_value("heights", source.column_index(32 * 16, 32 * 16)) == 80)
	var disabled: Resource = result.output_plan.working_copy(); disabled.regions[0].enabled = false
	var off := compose(result.candidate, disabled)
	assert(off.candidate.same_terrain_geometry(source, true) and off.output_plan.patches.is_empty())
	var manual: EmberTerrainPilotResource = first.candidate.working_copy()
	var section: EmberTerrainPilotResource = manual.sections[Vector2i.ZERO].working_copy()
	var local := 8 * 16 + 8 * 16 * section.width
	section.heights[local] = 92; manual.sections[Vector2i.ZERO] = section
	var protected_result := compose(manual, moved)
	assert(protected_result.candidate.column_value("heights", index) == 92)
	assert(protected_result.protected_blocks.has(Vector2i(8, 8)))
	assert(compose(protected_result.candidate, protected_result.output_plan).candidate.column_value("heights", index) == 92)
	var overlap: Resource = plan.working_copy()
	overlap.regions.append({"id": "q", "name": "Верхнее", "kind": "plateau", "enabled": true, "bounds": Rect2i(6, 6, 10, 10), "parameters": {"height_m": 7.0, "transition_m": 1.0}})
	assert(compose(source, overlap).candidate.column_value("heights", index) == 112)
	var corrupt: Dictionary = first.output_plan.data(); corrupt.patches[0].before = PackedInt32Array()
	assert(Plan.from_data(corrupt) == null)
	var old := {"version": 1, "regions": []}
	assert(Plan.from_data(old) != null)
	var invalid_local: EmberTerrainPilotResource = source.working_copy()
	var invalid_part: EmberTerrainPilotResource = invalid_local.sections[Vector2i(1, 1)].working_copy()
	invalid_part.heights[0] = -1; invalid_local.sections[Vector2i(1, 1)] = invalid_part
	assert(not invalid_local.validation_errors().is_empty())
	assert(invalid_local.validation_errors([Vector2i.ZERO]).is_empty(), "local check inspected unrelated payload")
	invalid_part.width -= 1
	assert(not invalid_local.validation_errors([Vector2i.ZERO]).is_empty(), "local check skipped global structure")
	var interrupted := Job.new(); assert(interrupted.begin(source, plan)); interrupted.step(1000); interrupted.cancel()
	assert(interrupted.candidate == null and source.column_value("heights", index) == 48)
	assert(interrupted.begin(source, plan))
	while not interrupted.finished: interrupted.step()
	assert(interrupted.candidate.same_terrain_data(first.candidate), "cancelled job could not be reused")
	var wet: EmberTerrainPilotResource = source.working_copy(); section = wet.sections[Vector2i.ZERO].working_copy()
	section.water_levels[local] = 100; wet.sections[Vector2i.ZERO] = section
	var rejected := Job.new(); assert(rejected.begin(wet, plan))
	for i in 10000:
		rejected.step()
		if not rejected.error.is_empty() or rejected.finished: break
	assert(not rejected.error.is_empty() and rejected.candidate == null)
	# Vertical state: terrain and provenance commit/Undo/save/recovery together.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE.get_base_dir()))
	assert(ResourceSaver.save(source, FILE) == OK)
	var scene := Node3D.new(); scene.scene_file_path = SCENE; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48, 48)
	map.compact_terrain = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene
	map.set_meta(Plan.META, plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene
	var history := UndoRedo.new()
	editor.sessions.configure(history, func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene)
		return ResourceSaver.save(packed, SCENE) if error == OK else error)
	editor.sessions.recovery_directory = FILE.get_base_dir().path_join("recovery")
	var draft := editor.sessions.open_map(map, scene)
	var context := {"draft": draft, "version": draft.resource.working_copy(), "candidate": first.candidate, "output_plan": first.output_plan,
		"plan_version": plan.data(), "layout": Sessions.compact_layout(map).positions}
	assert(editor.commit_terrain_composition(map, context).is_empty())
	assert(draft.resource == first.candidate and not Plan.read(map).patches.is_empty())
	history.undo(); assert(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty())
	history.redo(); assert(draft.resource == first.candidate and Plan.same(Plan.read(map), first.output_plan))
	assert(not editor.commit_terrain_composition(map, context).is_empty(), "stale preview accepted")
	assert(editor.sessions.save_all(scene), editor.sessions.error)
	var reopened := (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert(Plan.same(Plan.read(reopened.get_node("Map")), first.output_plan))
	assert(compose(reopened.get_node("Map").compact_terrain, Plan.read(reopened.get_node("Map"))).candidate.same_terrain_data(first.candidate))
	reopened.free()
	assert(editor.commit_terrain_plan(map, moved).is_empty())
	context = {"draft": draft, "version": draft.resource.working_copy(), "candidate": result.candidate, "output_plan": result.output_plan,
		"plan_version": moved.data(), "layout": Sessions.compact_layout(map).positions}
	assert(editor.commit_terrain_composition(map, context).is_empty())
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	assert(draft.resource.same_terrain_data(first.candidate))
	assert(editor.sessions.restore_recovery(scene) == 1, editor.sessions.error)
	assert(draft.resource.same_terrain_data(result.candidate) and Plan.same(Plan.read(map), result.output_plan))
	editor.sessions.discard(scene)
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("TERRAIN_COMPOSITION PASS repeat/move/off/manual-preservation/overlap-order/determinism/v1/corruption/cancel/wet-refusal · calc_ms=", first.elapsed_us / 1000.0, " worst_step_ms=", first.worst_step_us / 1000.0)
	quit()
