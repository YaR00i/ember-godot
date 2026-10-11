extends SceneTree
## Binary/remap shop gate, not a full game export or Forward+ acceptance gate.

const Fixture = preload("res://tools/fixtures/ember_shop_test_fixture.gd")
const Packer = preload("res://tools/fixtures/ember_native_catalog_pack_fixture.gd")
const Catalog = preload("res://scripts/ember_shop_catalog.gd")
var _setup: Dictionary


func _init() -> void:
	if "--read-pack" in OS.get_cmdline_user_args():
		Fixture.Maps.prepare(self, "user://ember-tests/shop-pack-read-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
		_read.call_deferred()
		return
	_setup = Fixture.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_build.call_deferred()


func _build() -> void:
	if _setup.error != OK or not _setup.progress_isolated:
		quit(1)
		return
	var path := Packer.build(_setup.directory, [Catalog.NATIVE_DIR, EmberItemCatalog.NATIVE_DIR, EmberItemCatalog.ICON_DIR])
	var errors: Array[String] = []
	Fixture.verify_sources(_setup, errors)
	if path.is_empty() or not errors.is_empty():
		quit(1)
		return
	print("SHOP_PACK: ", path)
	print("PASS build binary shop pack")
	quit(0)


func _read() -> void:
	var errors: Array[String] = []
	if Catalog.ids() != [Fixture.SHOP, Fixture.OTHER]: errors.append("binary pack shop enumeration lost native IDs")
	for id in [Fixture.SHOP, Fixture.OTHER]:
		var path := Catalog.native_path(id)
		if FileAccess.file_exists(path) or not ResourceLoader.exists(path) or Catalog.owner(id) != "native" or Catalog.definition(id) != Fixture.document(id):
			errors.append("binary shop remap did not resolve " + id)
		var view := EmberInteractionContent.shop_view(id)
		var listings: Array = view.get("listings", [])
		if listings.size() != 3 or listings[0].buyPrice != 6 or listings[1].stock != null or listings[2].stock != 12:
			errors.append("binary shop lost prices or finite/infinite stock")
	if not Catalog.definition("retired_shop").is_empty(): errors.append("binary shop lookup revived legacy data")
	if not errors.is_empty():
		printerr("FAIL shop catalog PCK: ", "; ".join(errors))
		quit(1)
		return
	print("PASS shop catalog PCK; native shops/prices/stock resolve without source tres/JSON/JOI")
	quit(0)
