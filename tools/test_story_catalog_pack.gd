extends SceneTree
## Focused binary action/dialogue PCK gate; no VN image/render acceptance.

const Fixture = preload("res://tools/fixtures/ember_story_test_fixture.gd")
const Packer = preload("res://tools/fixtures/ember_native_catalog_pack_fixture.gd")
var _setup: Dictionary


func _init() -> void:
	if "--read-pack" in OS.get_cmdline_user_args():
		Fixture.Content.Maps.prepare(self, "user://ember-tests/story-pack-read-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
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
	var path := Packer.build(_setup.directory, [EmberActionCatalog.NATIVE_DIR, EmberDialogueCatalog.NATIVE_DIR,
		EmberItemCatalog.NATIVE_DIR, EmberItemCatalog.ICON_DIR, EmberShopCatalog.NATIVE_DIR, EmberQuestCatalog.NATIVE_DIR])
	var errors: Array[String] = []
	Fixture.verify_sources(_setup, errors)
	if path.is_empty() or not errors.is_empty():
		quit(1)
		return
	print("STORY_PACK: ", path)
	print("PASS build binary story pack")
	quit(0)


func _read() -> void:
	var errors: Array[String] = []
	if EmberActionCatalog.ids().size() != 4 or EmberDialogueCatalog.ids().size() != 6:
		errors.append("binary story enumeration lost native IDs")
	for catalog in [EmberActionCatalog, EmberDialogueCatalog]:
		for id in catalog.ids():
			var path: String = catalog.native_path(id)
			if FileAccess.file_exists(path) or not ResourceLoader.exists(path) or catalog.owner(id) != "native" or catalog.document(id).get("id") != id:
				errors.append("binary story remap did not resolve " + id)
	var resolved := EmberInteractionContent.resolve_script_ref(Fixture.Content.NOTICE)
	if resolved.get("kind") != "script": errors.append("binary action/dialogue ID priority changed")
	var queue := EmberActionScript.queue_for(Fixture.Content.CHAIN)
	var steps: Array = queue.get("steps", [])
	if not bool(queue.get("ok", false)) or steps.size() != 4 or steps[1].type != "give_item" or steps[2].value != true:
		errors.append("binary action lost ordered runtime steps or typed flag")
	var dialogue := EmberInteractionContent.dialogue_for_id(Fixture.Content.BRANCH)
	var session := EmberDialogueSession.new()
	if not session.start(dialogue) or session.current_kind() != "choice" or session.choice_labels().size() != 2:
		errors.append("binary dialogue lost native branch")
	else:
		session.choose(1)
		if session.current_text() != "Выбран второй вариант.": errors.append("binary branch routed to wrong native line")
	for catalog in [EmberActionCatalog, EmberDialogueCatalog]:
		if not catalog.document("retired_story").is_empty(): errors.append("binary story revived legacy document")
	if not errors.is_empty():
		printerr("FAIL story catalog PCK: ", "; ".join(errors))
		quit(1)
		return
	print("PASS story catalog PCK; native resolution/order/branching without source tres/JSON/JOI")
	quit(0)
