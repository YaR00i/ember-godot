extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Selection = preload("res://addons/ember_import/ember_compact_section_selection.gd")
const Generation = preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const DIR := "user://ember-tests/section-selection"

func _initialize() -> void:
	_run.call_deferred()


func generate(source: Terrain, area: Rect2i, budget := 4000) -> RefCounted:
	var job := Generation.new()
	assert(job.begin(source, Rect2i(area.position * 24, area.size * 24), Math.DEFAULTS, true), job.error)
	var steps := 0
	while not job.finished:
		job.step(budget)
		steps += 1
		assert(steps < 10000)
	assert(job.candidate.validation_errors().is_empty())
	return job


func retained(source: Terrain, candidate: Terrain, offset: Vector2i) -> void:
	for key: Vector2i in source.sections:
		var old: Terrain = source.sections[key]
		var kept: Terrain = candidate.sections[key + offset]
		for channel in Terrain.Sections.CHANNELS: assert(old.get(channel) == kept.get(channel), "changed retained " + channel)
		assert(old.water_flow == kept.water_flow)
		assert(old.column_material_overrides == kept.column_material_overrides)


func same_layout(a: Dictionary, b: Dictionary) -> bool:
	for name in b.positions:
		if not (a.positions[name] as Vector3).is_equal_approx(b.positions[name]): return false
	return true


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var creation := Creation.new()
	creation.scene_directory = DIR
	creation.terrain_directory = DIR
	assert(creation.prepare_sections("selection_fixture", 2, 2, 12))
	var source: Terrain = creation.source.sectioned_copy()
	var part: Terrain = source.sections[Vector2i.ZERO]
	part.water_flow.resize(24 * 24)
	part.water_flow.fill(Vector2(0.2, 0.8))
	part.column_material_overrides[40] = {4: 2}
	var snapshot := source.working_copy()
	assert(not Selection.plan(source, Rect2i(0, 0, 2, 2)).error.is_empty())
	assert(not Selection.plan(source, Rect2i(-22, 0, 1, 1)).error.is_empty())
	assert(not Selection.plan(source, Rect2i(2, 0, 5, 1)).error.is_empty())
	var east := generate(source, Rect2i(1, 0, 2, 2))
	assert(east.addition.keys.size() == 2 and east.candidate.sections.size() == 6)
	retained(source, east.candidate, Vector2i.ZERO)
	var corner := generate(source, Rect2i(-1, -1, 2, 2))
	assert(corner.addition.offset == Vector2i.ONE and corner.addition.keys.size() == 3)
	assert(corner.candidate.width == 1152 and corner.candidate.depth == 1152)
	retained(source, corner.candidate, Vector2i.ONE)
	var repeat := generate(source, Rect2i(-1, -1, 2, 2), 700)
	assert(repeat.candidate.same_terrain_data(corner.candidate), "budget changed result")
	assert(source.same_terrain_data(snapshot), "preview changed source")
	var cancel := Generation.new()
	assert(cancel.begin(source, Rect2i(-24, 0, 24, 24), Math.DEFAULTS, true))
	cancel.step(1000)
	cancel.cancel()
	assert(cancel.candidate == null and cancel.addition.is_empty() and source.same_terrain_data(snapshot))
	var bad := Math.DEFAULTS.duplicate()
	bad.sea_m = NAN
	assert(not cancel.begin(source, Rect2i(-24, 0, 24, 24), bad, true))
	assert(not cancel.begin(source, Rect2i(-23, 0, 24, 24), Math.DEFAULTS, true))
	# New joins read retained boundary height without replacing its columns.
	for y in [0, 64, 192, 383]:
		assert(east.candidate.column_value("heights", east.candidate.column_index(768, y)) == source.column_value("heights", source.column_index(767, y)))
	var frame := Node3D.new()
	frame.scene_file_path = DIR.path_join("scene.tscn")
	root.add_child(frame)
	var map := EmberMapLoader.new()
	map.name = "Map"
	frame.add_child(map)
	map.owner = frame
	map.position = Vector3(30, 5, 80)
	map.rotation.y = 0.3
	map.authored_size_blocks = Vector2i(48, 48)
	map.hydrate_legacy_regions = false
	assert(ResourceSaver.save(source, DIR.path_join("terrain.res")) == OK)
	map.compact_terrain = ResourceLoader.load(DIR.path_join("terrain.res"), "", ResourceLoader.CACHE_MODE_IGNORE)
	for name in ["Terrain", "Props", "Regions"]:
		var node := Node3D.new()
		node.name = name
		map.add_child(node)
		node.owner = frame
	var prop := Node3D.new()
	map.get_node("Props").add_child(prop)
	prop.owner = frame
	prop.position = Vector3(120, 15, 150)
	var prop_position := prop.global_position
	var old_ground := map.to_global(Vector3(120, 12, 150))
	var history := UndoRedo.new()
	var editor := Editor.new()
	root.add_child(editor)
	editor.scene = frame
	editor.sessions.configure(history, func() -> int:
		var packed := PackedScene.new()
		var result := packed.pack(frame)
		return ResourceSaver.save(packed, DIR.path_join("scene.tscn")) if result == OK else result)
	editor.sessions.recovery_directory = DIR.path_join("recovery")
	var draft := editor.sessions.open_map(map, frame)
	var original_layout := Sessions.compact_layout(map)
	var context := {"draft": draft, "version": draft.resource.working_copy(), "candidate": corner.candidate,
		"selection": corner.addition, "layout": original_layout.positions}
	assert(editor.commit_selected_sections(map, context).is_empty())
	assert(draft.resource == corner.candidate and editor.sessions.dirty(draft))
	assert(prop.global_position.is_equal_approx(prop_position), "left/top growth moved authored object")
	assert(map.to_global(Vector3(504, 12, 534)).is_equal_approx(old_ground), "left/top growth moved retained ground")
	assert(map.authored_size_blocks == Vector2i(72, 72))
	history.undo()
	assert(draft.resource.same_terrain_data(source) and Sessions.compact_layout(map) == original_layout)
	history.redo()
	assert(prop.global_position.is_equal_approx(prop_position))
	assert(not editor.commit_selected_sections(map, context).is_empty(), "stale candidate accepted")
	editor.sessions.write_recovery()
	editor.sessions.discard(frame)
	assert(same_layout(Sessions.compact_layout(map), original_layout) and map.authored_size_blocks == Vector2i(48, 48))
	var recovery := Sessions.new()
	recovery.configure(UndoRedo.new())
	recovery.recovery_directory = editor.sessions.recovery_directory
	assert(recovery.restore_recovery(frame) == 1, recovery.error)
	assert(prop.global_position.is_equal_approx(prop_position) and map.authored_size_blocks == Vector2i(72, 72))
	recovery.discard(frame)
	assert(same_layout(Sessions.compact_layout(map), original_layout) and map.authored_size_blocks == Vector2i(48, 48))
	assert(editor.commit_selected_sections(map, context).is_empty())
	assert(editor.sessions.save_all(frame), editor.sessions.error)
	var saved := ResourceLoader.load(DIR.path_join("terrain.res"), "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(saved.same_terrain_data(corner.candidate))
	var reopened := (ResourceLoader.load(DIR.path_join("scene.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reopened)
	assert(reopened.get_node("Map/Props").global_position.is_equal_approx(map.get_node("Props").global_position), "reopen lost layout")
	print("SECTION_SELECTION PASS signed/multiple/overlap/joins/deterministic/cancel/validation/world-space/Undo-Redo/stale/recovery/Discard/Save-Reopen · calculation=", corner.elapsed_us / 1000.0, " ms worst-step=", corner.worst_step_us / 1000.0)
	reopened.free()
	history.clear_history()
	(recovery.undo as UndoRedo).clear_history()
	(recovery.undo as UndoRedo).free()
	history.free()
	editor.sessions.entries.clear()
	editor.sessions.save_scene = Callable()
	recovery.entries.clear()
	context.clear()
	editor.free()
	frame.free()
	await process_frame
	quit()
