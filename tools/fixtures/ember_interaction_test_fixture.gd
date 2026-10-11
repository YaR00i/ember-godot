extends RefCounted
## Synthetic native content shared by interaction gates. Native writes are
## permitted only in the disposable project made by run_interaction_tests.py.

const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const GUARD := "interaction_guard"
const NOTICE := "interaction_notice"
const NOTICE_TALK := "interaction_notice_talk"
const CHAIN := "interaction_chain"
const BRANCH := "interaction_branch"
const SHOP := "interaction_shop"
const INTRO := "interaction_shop_intro"
const VN := "interaction_visual_projection"
const QUEST := "interaction_quest"
const STATUS := "interaction_quest_status"
const READ := "interaction_quest_read"
const MIDDLE := "interaction_quest_middle"
const FINAL := "interaction_quest_final"
const GUARD_LINES := ["Первая тестовая реплика.", "Вторая тестовая реплика.", "Третья тестовая реплика."]


static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/interactions-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# Isolate autoload even on refusal: it must not migrate/read real user saves.
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	state.textures = []
	var expected := OS.get_environment("EMBER_INTERACTION_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.interaction-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_interaction_tests.py; native fixtures require a disposable project")
		return state
	state.error = _write_content()
	for id in ["available", "active", "done"]:
		var path := "res://assets/world_markers/quest_%s.svg" % id
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(path))
		if error != OK:
			state.error = error
			return state
		var texture := ImageTexture.create_from_image(image)
		texture.take_over_path(path)
		state.textures.append(texture)
	state.source_hashes = {}
	for directory_name in [EmberDialogueCatalog.NATIVE_DIR, EmberActionCatalog.NATIVE_DIR, EmberItemCatalog.NATIVE_DIR, EmberShopCatalog.NATIVE_DIR, EmberQuestCatalog.NATIVE_DIR]:
		for name in DirAccess.get_files_at(directory_name):
			var path: String = str(directory_name).path_join(name)
			state.source_hashes[path] = FileAccess.get_sha256(path)
	return state


static func verify_sources(state: Dictionary, errors: Array[String]) -> void:
	for path in state.source_hashes:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != state.source_hashes[path]:
			errors.append("runtime changed native content source " + path)


static func save_map(map_id: String, directory: String) -> PackedScene:
	var interactions: Array[Dictionary] = [
		{"id": "talk_npc", "position": Vector3(8, 0, 8), "values": {"kind": "talk", "script_id": GUARD}},
		{"id": "branch_npc", "position": Vector3(20, 0, 8), "values": {"kind": "talk", "script_id": BRANCH}},
		{"id": "shop", "position": Vector3(32, 0, 8), "values": {"kind": "shop", "script_id": INTRO, "shop_id": SHOP}},
	]
	for index in 3:
		interactions.append({"id": ["quest_start", "quest_middle", "quest_final"][index], "position": Vector3(8 + index * 16, 0, 48), "marker_mesh": true,
			"values": {"kind": "quest_marker", "quest_id": QUEST, "script_id": [NOTICE, "interaction_middle", "interaction_final"][index], "icon_id": "quest", "quest_status": "available" if index == 0 else "active"}})
	return Maps.save_map(map_id, directory, [], [], [], 16.0, interactions, [{"id": "chain_demo", "script": CHAIN, "position": Vector3(28, 4, 28)}])


static func _dialogue(id: String, steps: Array) -> Dictionary:
	return {"id": id, "nameRu": id, "startStepId": steps[0].id, "steps": steps}


static func _lines(id: String, texts: Array) -> Dictionary:
	var steps: Array = []
	for index in texts.size():
		steps.append({"id": "line%d" % index, "type": "dialogue", "textRu": texts[index], "next": "line%d" % (index + 1) if index + 1 < texts.size() else "end"})
	steps.append({"id": "end", "type": "end"})
	return _dialogue(id, steps)


static func _write_content() -> Error:
	var documents := [_lines(GUARD, GUARD_LINES), _lines(NOTICE_TALK, ["Тестовое событие.", "Теперь награда."]), _lines(NOTICE, ["Тень action ID."]), _lines(INTRO, ["Тестовая лавка."]),
		_dialogue(BRANCH, [{"id": "choice", "type": "choice", "options": [{"labelRu": "Первый вариант.", "next": "first"}, {"labelRu": "Второй вариант.", "next": "second"}]},
			{"id": "first", "type": "dialogue", "textRu": "Выбран первый вариант.", "next": "end"}, {"id": "second", "type": "dialogue", "textRu": "Выбран второй вариант.", "next": "end"}, {"id": "end", "type": "end"}]),
		_dialogue(VN, [{"id": "splash", "type": "splash", "artId": "fixture_art", "next": "line"},
			{"id": "line", "type": "dialogue", "textRu": "Visual projection", "bgArtId": "fixture_bg", "portraitSide": "right", "actors": [{"artId": "fixture_portrait", "lockY": true, "scale": 1.0}], "next": "choice"},
			{"id": "choice", "type": "choice", "options": [{"labelRu": "End", "next": "end"}]}, {"id": "end", "type": "end"}])]
	for document in documents:
		var error := EmberDialogueCatalog.write_native(document)
		if error != OK: return error
	var actions := [
		{"id": NOTICE, "steps": [{"type": "talk", "dialogueId": NOTICE_TALK}, {"type": "set_flag", "flag": STATUS, "value": "active"}, {"type": "set_flag", "flag": READ, "value": true}]},
		{"id": CHAIN, "steps": [{"type": "talk", "dialogueId": NOTICE_TALK}, {"type": "give_item", "itemId": "coin", "count": 1}, {"type": "set_flag", "flag": "interaction_chain_done", "value": true}, {"type": "wait", "sec": 0.0}]},
		{"id": "interaction_middle", "steps": [{"type": "set_flag", "flag": MIDDLE, "value": true}]},
		{"id": "interaction_final", "steps": [{"type": "set_flag", "flag": FINAL, "value": true}]},
	]
	for document in actions:
		var error := EmberActionCatalog.write_native(document)
		if error != OK: return error
	var error: int = OK
	error = EmberShopCatalog.write_native({"id": SHOP, "nameRu": "Тестовая лавка", "listings": [
		{"itemId": "qingxin_tea", "buyPrice": 6, "sellPrice": 3, "stock": 2}, {"itemId": "meat_bun", "buyPrice": 4, "sellPrice": 2, "stock": 8},
		{"itemId": "herb", "buyPrice": 3, "sellPrice": 1, "stock": 12}, {"itemId": "revival_spark", "buyPrice": 12, "sellPrice": 6, "stock": 2}]})
	if error != OK: return error
	var quest := EmberQuestResource.new()
	quest.quest_id = QUEST
	quest.definition = {"id": QUEST, "titleRu": "Тестовое задание", "statusFlagId": STATUS, "showWhenAvailable": true, "objectives": [
		{"id": "read", "flagId": READ, "progressMode": "flag", "textRu": "Первая цель", "requiresObjectiveIds": []},
		{"id": "middle", "flagId": MIDDLE, "progressMode": "flag", "textRu": "Вторая цель", "requiresObjectiveIds": ["read"]},
		{"id": "final", "flagId": FINAL, "progressMode": "flag", "textRu": "Последняя цель", "requiresObjectiveIds": ["middle"]}]}
	error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EmberQuestCatalog.NATIVE_DIR))
	return ResourceSaver.save(quest, EmberQuestCatalog.native_path(QUEST)) if error == OK else error
