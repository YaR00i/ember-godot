extends RefCounted
## All native/image writes are confined to a guarded disposable project.

const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Assets = preload("res://scripts/ember_vn_assets.gd")


static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/vn-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_VN_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.vn-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_vn_asset_tests.py; native import requires a disposable project")
		return state
	var legacy := directory.path_join("poison-legacy")
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(legacy))
	state.registries = {}
	for path in [legacy.path_join("arts/registry.json"), legacy.path_join("portraits/retired_speaker/registry.json")]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string('{"arts":[{"id":"retired_art","path":"retired.svg"}],"expressions":{"retired_expression":{"path":"retired.svg"}}}')
		file.close()
		state.registries[path] = FileAccess.get_sha256(path)
	return state


static func import_fixture(state: Dictionary, portrait: bool) -> Dictionary:
	var source: String = state.directory.path_join("expression.svg" if portrait else "background.svg")
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="48"><rect width="32" height="48" fill="#c96a88"/></svg>')
	file.close()
	var assets := Assets.new()
	return assets.import_portrait(ProjectSettings.globalize_path(source), "fixture_speaker") if portrait else assets.import_background(ProjectSettings.globalize_path(source))


static func check_detached(state: Dictionary, errors: Array[String]) -> void:
	var assets := Assets.new()
	if not assets.art_path("retired_art").is_empty() or "retired_speaker" in assets.speaker_ids() or not assets.portrait_path("retired_speaker", "retired_expression").is_empty():
		errors.append("catalog revived retired JSON entries")
	for path in state.registries:
		if FileAccess.get_sha256(path) != state.registries[path]: errors.append("catalog changed poison JSON")
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(state.directory.path_join("absent-pack")))
	assets.reload()
	if not assets.art_path("retired_art").is_empty(): errors.append("missing JOI changed native catalog")


static func run_library(state: Dictionary, portrait: bool) -> int:
	var errors: Array[String] = []
	var imported := import_fixture(state, portrait)
	if not bool(imported.get("ok", false)):
		printerr("FAIL native VN import: ", imported)
		return 1
	var path := str(imported.assetPath)
	var resource_path := str(imported.resourcePath)
	var assets := Assets.new()
	var resolved := assets.portrait_path("fixture_speaker", imported.portraitKey) if portrait else assets.art_path(imported.id)
	if resolved != path or not FileAccess.file_exists(path) or not ResourceLoader.exists(resource_path): errors.append("native import/reopen lost paths")
	var image := assets._image_for_path(resolved)
	if image == null or image.get_size() != Vector2i(32, 48) or image.get_pixel(12, 12).a < 0.99: errors.append("native image decoding changed")
	var held := ResourceLoader.load(resource_path)
	held.display_name = "Held cached name"
	var edited := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	edited.display_name = "Saved new name"
	if ResourceSaver.save(edited, resource_path) != OK: errors.append("native metadata save failed")
	assets.reload()
	var entries := assets.portrait_entries("fixture_speaker") if portrait else assets.art_entries()
	var found := false
	for entry in entries:
		if entry.get("resourcePath") == resource_path:
			found = true
			if entry.get("labelRu" if portrait else "captionRu") != "Saved new name": errors.append("reload reused stale cached Resource")
	if not found: errors.append("native enumeration lost imported metadata")
	var duplicate := import_fixture(state, portrait)
	if not duplicate.get("ok", false) or duplicate.get("resourcePath") == resource_path: errors.append("repeat import overwrote existing asset")
	var missing: String = state.directory.path_join("missing.png")
	var rejected := assets.import_portrait(missing, "fixture_speaker") if portrait else assets.import_background(missing)
	if rejected.get("ok", false): errors.append("missing source accepted")
	var invalid: Resource = EmberVnPortrait.new() if portrait else EmberVnBackground.new()
	if portrait:
		invalid.speaker_id = "invalid_speaker"
		invalid.portrait_key = "invalid_expression"
	else: invalid.id = "invalid_art"
	invalid.image_path = "relative/retired.svg"
	var invalid_path := (Assets.NATIVE_PORTRAIT_DIR if portrait else Assets.NATIVE_BACKGROUND_DIR).path_join("invalid.tres")
	ResourceSaver.save(invalid, invalid_path)
	assets.reload()
	var invalid_resolved := assets.portrait_path("invalid_speaker", "invalid_expression") if portrait else assets.art_path("invalid_art")
	if not invalid_resolved.is_empty(): errors.append("relative metadata path fell back to old pack")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))
	check_detached(state, errors)
	if not errors.is_empty():
		printerr("FAIL native VN assets: ", "; ".join(errors))
		return 1
	print("PASS native VN ", "portrait" if portrait else "background", "; import/reopen/reload/image/unique IDs; poison and absent JOI ignored")
	return 0
