extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_vn_test_fixture.gd")
const Packer = preload("res://tools/fixtures/ember_native_catalog_pack_fixture.gd")
var _state: Dictionary

func _init() -> void:
	if "--build-imported" in OS.get_cmdline_user_args():
		_state = Fixture.prepare(self)
		if _state.refused:
			quit.call_deferred(2)
			return
		_build_imported.call_deferred()
		return
	if FileAccess.file_exists("res://.vn-pack-reader"):
		Fixture.Maps.prepare(self, "user://ember-tests/vn-pack-%d" % OS.get_process_id())
		_read.call_deferred()
		return
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_build.call_deferred()

func _build() -> void:
	var background := Fixture.import_fixture(_state, false)
	var portrait := Fixture.import_fixture(_state, true)
	if not background.get("ok", false) or not portrait.get("ok", false):
		quit(1)
		return
	var marker := FileAccess.open("res://.vn-pack-reader", FileAccess.WRITE)
	marker.store_string("binary descriptor reader")
	marker.close()
	var path := Packer.build(_state.directory, [Fixture.Assets.NATIVE_BACKGROUND_DIR, Fixture.Assets.NATIVE_PORTRAIT_DIR])
	if path.is_empty():
		quit(1)
		return
	print("VN_PACK: ", path)
	print("PASS native VN binary pack build")
	quit(0)

func _build_imported() -> void:
	var excluded: Array[String] = []
	var assets := Fixture.Assets.new()
	for entry in assets.art_entries() + assets.portrait_entries("fixture_speaker"):
		excluded.append(str(entry.path))
	var marker := FileAccess.open("res://.vn-pack-imported", FileAccess.WRITE)
	marker.store_string("raw source images excluded")
	marker.close()
	var path := Packer.build(_state.directory, [Fixture.Assets.NATIVE_BACKGROUND_DIR, Fixture.Assets.NATIVE_PORTRAIT_DIR], excluded)
	if path.is_empty():
		quit(1)
		return
	print("VN_PACK: ", path)
	print("PASS native VN imported-texture pack build")
	quit(0)

func _read() -> void:
	var assets := Fixture.Assets.new()
	var errors: Array[String] = []
	if assets.art_entries().size() != 3 or assets.speaker_ids() != ["fixture_speaker"] or not assets.has_portrait("fixture_speaker", "expression"):
		errors.append("PCK native metadata enumeration failed")
	for entry in assets.art_entries() + assets.portrait_entries("fixture_speaker"):
		if FileAccess.file_exists(entry.resourcePath) or not ResourceLoader.exists(entry.resourcePath): errors.append("native binary remap missing")
		if FileAccess.file_exists("res://.vn-pack-imported") and (FileAccess.file_exists(str(entry.path)) or not ResourceLoader.exists(str(entry.path))):
			errors.append("imported-texture pack retained source image or lost import")
		var image := assets._image_for_path(str(entry.path))
		if image == null or image.is_empty(): errors.append("PCK image not readable: " + str(entry.path))
	if not assets.art_path("retired_art").is_empty() or not assets.portrait_path("retired_speaker", "retired_expression").is_empty(): errors.append("PCK revived retired assets")
	if not errors.is_empty():
		printerr("FAIL native VN PCK: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native VN PCK; binary descriptors and image bytes without source tres/JOI")
	quit(0)
