extends RefCounted
## Neutral native shops for mechanics gates, never historical author shops.

const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const SHOP := "shop_fixture"
const OTHER := "shop_fixture_other"
const KEY := "shop_fixture_key"


static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/shops-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_SHOP_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.shop-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_shop_tests.py; native shop fixtures require a disposable project")
		return state
	state.error = EmberItemCatalog.write_native({"id": KEY, "nameRu": "Тестовый ключ", "kind": "key", "stackMax": 1, "unsellable": true})
	for id in [SHOP, OTHER]:
		var error := EmberShopCatalog.write_native(document(id))
		if error != OK: state.error = error
	state.source_hashes = {}
	for folder in [EmberItemCatalog.NATIVE_DIR, EmberItemCatalog.ICON_DIR, EmberShopCatalog.NATIVE_DIR]:
		for name in DirAccess.get_files_at(folder):
			var path: String = str(folder).path_join(name)
			state.source_hashes[path] = FileAccess.get_sha256(path)
	return state


static func document(id: String) -> Dictionary:
	return {"id": id, "nameRu": "Тестовая лавка", "listings": [
		{"itemId": "qingxin_tea", "buyPrice": 6, "sellPrice": 3, "stock": 2},
		{"itemId": "meat_bun", "buyPrice": 4, "sellPrice": 2},
		{"itemId": "herb", "buyPrice": 3, "sellPrice": 1, "stock": 12},
	]}


static func verify_sources(state: Dictionary, errors: Array[String]) -> void:
	for path in state.source_hashes:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != state.source_hashes[path]:
			errors.append("runtime changed native shop/item source " + path)
