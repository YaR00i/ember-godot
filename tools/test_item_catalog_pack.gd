extends SceneTree
## Focused binary Resource/remap PCK gate, not a full game export gate.

const Catalog = preload("res://scripts/ember_item_catalog.gd")
const Packer = preload("res://tools/fixtures/ember_native_catalog_pack_fixture.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _directory := "user://ember-tests/item-pack-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _init() -> void:
	Maps.prepare(self, _directory)
	if "--read-pack" in OS.get_cmdline_user_args():
		_read.call_deferred()
		return
	var expected := OS.get_environment("EMBER_PARTY_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if expected != actual or expected.is_empty() or not FileAccess.file_exists("res://.party-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git"):
		printerr("REFUSED: item pack writes require the disposable runner")
		quit.call_deferred(2)
		return
	_build.call_deferred()


func _build() -> void:
	var path := Packer.build(_directory, [Catalog.NATIVE_DIR, Catalog.ICON_DIR])
	if path.is_empty():
		quit(1)
		return
	print("ITEM_PACK: ", path)
	print("PASS build binary item/icon pack")
	quit(0)


func _read() -> void:
	var errors: Array[String] = []
	if Catalog.ids().size() != 7 or Catalog.definitions().size() != 7 or Catalog.icon_ids().size() != 6 or Catalog.icon_definitions().size() != 6:
		errors.append("binary pack lost item/icon catalog enumeration")
	for id in Catalog.ids():
		var path := Catalog.native_path(id)
		if FileAccess.file_exists(path) or not ResourceLoader.exists(path) or Catalog.owner(id) != "native" or Catalog.definition(id).get("id") != id:
			errors.append("binary item remap did not resolve " + id)
	for id in Catalog.icon_ids():
		if FileAccess.file_exists(Catalog.ICON_DIR.path_join(id + ".tres")) or Catalog.icon_definition(id).get("id") != id or EmberItemVisuals.icon_image(id).is_invisible():
			errors.append("binary icon remap did not resolve " + id)
	if not errors.is_empty():
		printerr("FAIL item catalog PCK: ", "; ".join(errors))
		quit(1)
		return
	print("PASS item catalog PCK; seven binary items and six icons resolve without source tres/JOI")
	quit(0)
