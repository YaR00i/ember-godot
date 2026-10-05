@tool
extends EditorPlugin
## Run with --world-startup-f6 only in the disposable Forward+ QA project.

const QA_SCENE := "res://qa_selection/scenes/world_startup.tscn"
const RESULT := "res://qa_selection/world_startup_result.json"
var _errors: Array[String] = []


func _enter_tree() -> void:
	if "--world-startup-f6" in OS.get_cmdline_user_args(): _run.call_deferred()


func _frames(count: int) -> void:
	for frame in count: await get_tree().process_frame


func _run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember River Preview QA": return
	while EditorInterface.get_resource_filesystem().is_scanning(): await _frames(1)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer != null:
		while not importer._editor_preparation._complete: await _frames(1)
	var scene := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate()
	# QA copies can retain duplicate UIDs from old profiling fixtures. Pin the
	# explicit terrain path both before packing and in the saved test scene.
	scene.get_node("Map").compact_terrain = ResourceLoader.load("res://content/world_terrains/compact_material_relief_study.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	var probe := Node.new()
	probe.set_script(load("res://tools/test_compact_world_startup_playback.gd"))
	probe.name = "StartupProbe"
	scene.add_child(probe)
	probe.owner = scene
	var packed := PackedScene.new()
	packed.pack(scene)
	ResourceSaver.save(packed, QA_SCENE)
	scene.free()
	var uid_pattern := RegEx.new()
	uid_pattern.compile('(\\[ext_resource type="Resource") uid="[^"]+"( path="res://content/world_terrains/compact_material_relief_study.res")')
	var scene_text := uid_pattern.sub(FileAccess.get_file_as_string(QA_SCENE), "$1$2", true)
	var scene_file := FileAccess.open(QA_SCENE, FileAccess.WRITE)
	scene_file.store_string(scene_text)
	scene_file.close()
	EditorInterface.get_resource_filesystem().scan()
	await _frames(2)
	EditorInterface.open_scene_from_path(QA_SCENE)
	EditorInterface.set_main_screen_editor("3D")
	for cycle in 2:
		if FileAccess.file_exists(RESULT): DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
		EditorInterface.play_current_scene()
		var deadline := Time.get_ticks_msec() + 180000
		while not FileAccess.file_exists(RESULT) and Time.get_ticks_msec() < deadline: await _frames(1)
		var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESULT)) if FileAccess.file_exists(RESULT) else null
		if not result is Dictionary or not result.get("ok", false) or result.get("source_sections", 0) != 20:
			_errors.append("F6 cycle %d: %s" % [cycle, str(result)])
		print("WORLD_STARTUP_EDITOR cycle=", cycle, " ", result)
		EditorInterface.stop_playing_scene()
		await _frames(15)
	var editor_scene := EditorInterface.get_edited_scene_root()
	var controller := editor_scene.get_node("PlanarReflection")
	var deadline := Time.get_ticks_msec() + 180000
	while not controller._prepared and Time.get_ticks_msec() < deadline: await _frames(1)
	if not controller._prepared or editor_scene.get_node_or_null("WorldLoadingScreen") != null:
		_errors.append("3D preview was blocked by runtime startup")
	if _errors.is_empty(): print("WORLD_STARTUP_EDITOR PASS: repeated real F6, 3D preview")
	else: printerr("WORLD_STARTUP_EDITOR FAIL: ", _errors)
	EditorInterface.get_base_control().get_tree().quit(0 if _errors.is_empty() else 1)
