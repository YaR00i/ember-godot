extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Export = preload("res://addons/ember_import/ember_terrain_cache_export.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const FILE := "user://ember-tests/terrain-plan/terrain.res"
const SCENE := "user://ember-tests/terrain-plan/map.tscn"
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE.get_base_dir()))
	var creation := Creation.new()
	assert(creation.prepare_sections("plan_fixture", 1, 1, 12))
	assert(ResourceSaver.save(creation.source, FILE) == OK)
	var scene := Node3D.new(); scene.scene_file_path = SCENE; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(24, 24)
	map.compact_terrain = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE)
	scene.add_child(map); map.owner = scene
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene
	var history := UndoRedo.new()
	editor.sessions.configure(history, func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene)
		return ResourceSaver.save(packed, SCENE) if error == OK else error)
	editor.sessions.recovery_directory = FILE.get_base_dir().path_join("recovery")
	var entry := editor.sessions.open_map(map, scene)
	var terrain: Resource = entry.resource
	var saved: Resource = map.compact_terrain
	var hash := FileAccess.get_sha256(FILE)
	assert(Plan.read(map) == null and not editor.sessions.dirty(entry))
	var plan := Plan.new()
	plan.regions.append({"id": "hill", "name": "Холмы", "bounds": Rect2i(2, 3, 12, 10), "parameters": Math.DEFAULTS.duplicate(true)})
	plan.regions.append({"id": "bay", "name": "Залив", "bounds": Rect2i(10, 5, 8, 8), "parameters": Math.DEFAULTS.duplicate(true)})
	assert(plan.validation_errors(Vector2i(24, 24)).is_empty())
	assert(plan.overlaps("hill") == PackedStringArray(["Залив"]))
	assert(editor.commit_terrain_plan(map, plan).is_empty())
	assert(editor.sessions.dirty(entry) and entry.resource == terrain)
	history.undo(); assert(Plan.read(map) == null and not editor.sessions.dirty(entry))
	history.redo(); assert(Plan.same(Plan.read(map), plan))
	assert(editor.sessions.save_all(scene), editor.sessions.error)
	assert(FileAccess.get_sha256(FILE) == hash and map.compact_terrain == saved and entry.resource == terrain)
	assert(not editor.sessions.dirty(entry))
	var packed := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := packed.instantiate()
	assert(Plan.same(Plan.read(reopened.get_node("Map")), plan))
	assert(Export.strip_authoring_plan(reopened))
	assert(Plan.read(reopened.get_node("Map")) == null and Plan.read(map) != null)
	reopened.free()
	var edited: Resource = plan.working_copy()
	edited.regions[0].name = "Горный край"; edited.regions[0].parameters.seed = 123
	assert(plan.regions[0].name == "Холмы" and plan.regions[0].parameters.seed != 123)
	assert(editor.commit_terrain_plan(map, edited).is_empty())
	editor.sessions.write_recovery()
	var manifest := ConfigFile.new()
	assert(manifest.load(editor.sessions.recovery_directory.path_join("manifest.cfg")) == OK)
	var section: String = manifest.get_sections()[0]
	assert(manifest.get_value(section, "plan_only", false))
	assert(not FileAccess.file_exists(manifest.get_value(section, "draft", "")), "metadata recovery wrote terrain")
	editor.sessions.discard(scene)
	assert(Plan.same(Plan.read(map), plan))
	assert(editor.sessions.restore_recovery(scene) == 1, editor.sessions.error)
	assert(Plan.same(Plan.read(map), edited) and entry.resource.same_terrain_data(terrain))
	editor.sessions.discard(scene)
	# Reject malformed recovery before changing the scene or terrain.
	manifest.set_value(section, "terrain_plan", {"version": 99, "regions": []})
	assert(manifest.save(editor.sessions.recovery_directory.path_join("manifest.cfg")) == OK)
	assert(editor.sessions.restore_recovery(scene) == 0 and Plan.same(Plan.read(map), plan))
	var invalid: Resource = edited.working_copy(); invalid.regions[1].id = "hill"
	assert(not editor.commit_terrain_plan(map, invalid).is_empty())
	invalid = edited.working_copy(); invalid.regions[0].bounds = Rect2i(23, 0, 2, 2)
	assert(not editor.commit_terrain_plan(map, invalid).is_empty())
	invalid = edited.working_copy(); invalid.regions[0].parameters.relief_m = NAN
	assert(not editor.commit_terrain_plan(map, invalid).is_empty())
	assert(editor.commit_terrain_plan(map, null).is_empty())
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	assert(editor.sessions.restore_recovery(scene) == 1 and Plan.read(map) == null)
	editor.sessions.discard(scene)
	# Failed scene save keeps a recoverable draft and doesn't change terrain.
	assert(editor.commit_terrain_plan(map, edited).is_empty())
	editor.sessions.save_scene = func() -> int: return ERR_CANT_CREATE
	assert(not editor.sessions.save_all(scene) and editor.sessions.dirty(entry))
	assert(FileAccess.get_sha256(FILE) == hash and Plan.same(Plan.read(map), edited))
	editor.sessions.discard(scene)
	var shifted: Resource = plan.translated(Vector2i(24, 48))
	assert(shifted.regions[0].bounds.position == plan.regions[0].bounds.position + Vector2i(24, 48))
	assert(Plan.same(shifted.translated(Vector2i(-24, -48)), plan))
	var positions := {"Map": map.position}
	var enlarged: Resource = Extension.expanded(entry.resource, "west")
	assert(enlarged != null)
	editor._apply_selected_sections(map, entry, enlarged, Vector2i(48, 24), {"Map": map.position - Vector3(24 * map.imported_tile_size, 0, 0)}, Rect2i())
	assert(Plan.read(map).regions[0].bounds.position == plan.regions[0].bounds.position + Vector2i(24, 0))
	editor._apply_selected_sections(map, entry, terrain, Vector2i(24, 24), positions, Rect2i())
	assert(Plan.same(Plan.read(map), plan), "map growth Undo moved authoring intent")
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("TERRAIN_PLAN PASS scene/independent-copy/Undo-Redo/save-no-terrain-write/reopen/discard/recovery/delete/corruption/validation/export-strip/failed-save/coordinates")
	quit()
