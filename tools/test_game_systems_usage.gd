extends SceneTree
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Hub = preload("res://addons/ember_import/ember_game_systems_workspace.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _errors: Array[String] = []
var _files: Array[String] = []
var _undo := UndoRedo.new()
var _revealed := ""

func _init() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL usage gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	Maps.prepare(self, "user://ember-tests/usage-%d" % OS.get_process_id())
	_run.call_deferred()

func _save(resource: Resource, path: String) -> void:
	_check(ResourceSaver.save(resource, path) == OK, "usage fixture save failed")
	_files.append(path)

func _run() -> void:
	var effect := Catalog.Effects.resource("apply_wet").duplicate(true) as EmberCombatEffectResource
	effect.effect_id = "usage_effect"
	effect.display_name = "Проверочный эффект"
	var effect_path := Store.path_for("effect", effect.effect_id)
	_save(effect, effect_path)
	effect = ResourceLoader.load(effect_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var action := Catalog.Actions.resource("strike").duplicate(true) as EmberCombatActionResource
	action.action_id = "usage_action"
	action.display_name = "Одинаковое имя"
	action.effect_steps = [effect]
	var path_a := Store.path_for("action", action.action_id)
	var path_b := "res://content/combat/actions/usage_action_duplicate.tres"
	_save(action, path_a)
	_save(action.duplicate(true), path_b)
	var mention := Catalog.Actions.resource("strike").duplicate(true) as EmberCombatActionResource
	mention.action_id = "usage_mention"
	mention.requirements_text = effect.effect_id
	var mention_path := Store.path_for("action", mention.action_id)
	_save(mention, mention_path)
	var dependency := Resource.new()
	dependency.set_meta("used_effect", effect)
	var dependency_path := "res://content/action_scripts/usage_dependency_fixture.tres"
	_save(dependency, dependency_path)
	var script_path := "res://scripts/usage_reference_fixture.gd"
	var script := FileAccess.open(script_path, FileAccess.WRITE)
	script.store_string('extends Node\nconst REFERENCED = "usage_effect"\n')
	script.close()
	_files.append(script_path)
	var cached := ResourceLoader.load(path_a) as EmberCombatActionResource
	cached.display_name = "Несохранённое имя"
	cached.effect_steps = []
	var target := Catalog.saved_record("effect", effect_path, Store.SPECS)
	var rows := Catalog.incoming_links("effect", target, Store.SPECS)
	var by_path := {}
	for source in rows:
		_check(not by_path.has(source.path), "multiple rows for one incoming file")
		by_path[source.path] = source
	_check(by_path.has(path_a) and by_path.has(path_b) and by_path[path_a].name == "Одинаковое имя" and by_path[path_b].name == "Одинаковое имя", "duplicate ID/name or dirty cache hid a saved consumer")
	_check(by_path[path_a].confirmed and "Прямая связь · Эффект" in by_path[path_a].reasons, "semantic relation not distinguished")
	_check(by_path.has(mention_path) and not by_path[mention_path].confirmed and by_path[mention_path].module == "action", "text ID misclassified as confirmed")
	_check(by_path.has(dependency_path) and by_path[dependency_path].confirmed and by_path[dependency_path].module.is_empty(), "external resource dependency lost")
	_check(by_path.has(script_path) and not by_path[script_path].confirmed and by_path[script_path].module.is_empty(), "external script mention lost")
	_check(cached.display_name == "Несохранённое имя" and cached.effect_steps.is_empty(), "usage scan mutated dirty cache")
	Catalog.refresh()
	var hub := Hub.new()
	root.add_child(hub)
	hub.configure(_undo)
	hub.setup()
	hub.library_file_requested.connect(func(path: String) -> void: _revealed = path)
	hub.select_module("effect", effect.effect_id)
	var library_search := hub.find_child("GameSystemsSearch", true, false) as LineEdit
	library_search.text = "Проверочный"
	library_search.text_changed.emit(library_search.text)
	(hub.find_child("GameSystemsUsage", true, false) as Button).pressed.emit()
	var panel := hub.get("_usage_panel") as ConfirmationDialog
	_check(panel != null and not hub.has_unsaved_changes(), "opening usage dirtied authoring")
	var tree := panel.find_child("UsageRecords", true, false) as Tree
	var row := tree.get_root().get_first_child()
	while row != null:
		if row.get_metadata(0).path == path_b: row.select(0)
		row = row.get_next()
	panel.call("_select")
	(tree.item_activated).emit()
	_check(hub.selected_record().get("path") == path_b and hub.selected_record().get("name") == "Одинаковое имя", "usage double-click selected another file sharing the same ID")
	_check(hub.find_child("GameSystemsUsageBack", true, false) != null, "return-to-origin action missing")
	(hub.find_child("GameSystemsUsageBack", true, false) as Button).pressed.emit()
	_check(hub.selected_record().get("path") == effect_path, "Back lost original library selection")
	_check(library_search.text == "Проверочный", "Back lost source search context")
	hub.call("_show_usage", hub.selected_record())
	var search := panel.find_child("UsageSearch", true, false) as LineEdit
	search.text = "usage_action_duplicate"
	search.text_changed.emit(search.text)
	_check(tree.get_root().get_first_child() != null and tree.get_root().get_first_child().get_next() == null, "usage filter not local/exact")
	search.text = "no-such-usage-row"
	search.text_changed.emit(search.text)
	_check(tree.get_root().get_first_child() == null and (panel.find_child("UsageOpen", true, false) as Button).disabled, "empty filter retained stale Open action")
	hub.begin_edit()
	hub.get("_session").set_value("display_name", "Несохранённый эффект")
	_check(not hub.call("_open_usage_record", by_path[path_b]) and hub.has_unsaved_changes() and hub.get("_session").draft.display_name == "Несохранённый эффект", "incoming navigation discarded dirty draft")
	_check("В черновике" in (panel.find_child("UsageDetail", true, false) as RichTextLabel).text, "dirty navigation feedback missing")
	hub.discard_changes()
	hub.select_module("effect", effect.effect_id)
	hub.call("_show_usage", hub.selected_record())
	var bytes := FileAccess.get_file_as_bytes(path_b)
	var changed := ResourceLoader.load(path_b, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberCombatActionResource
	changed.display_name = "Изменённый файл"
	ResourceSaver.save(changed, path_b)
	_check(not hub.call("_open_usage_record", by_path[path_b]) and hub.selected_record().get("path") == effect_path, "stale incoming link bypassed saved hash")
	(panel.find_child("UsageRefresh", true, false) as Button).pressed.emit()
	var refreshed: Dictionary = {}
	for source in panel.get("_rows"):
		if source.path == path_b: refreshed = source
	_check(not refreshed.is_empty() and refreshed.name == "Изменённый файл" and hub.call("_open_usage_record", refreshed), "Refresh did not unlock updated saved record")
	hub.call("_return_usage_origin")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
	_check(not hub.call("_open_usage_record", refreshed) and hub.selected_record().get("path") == effect_path, "deleted incoming link opened an ID alias")
	var restored := FileAccess.open(path_b, FileAccess.WRITE)
	restored.store_buffer(bytes)
	restored.close()
	_check(hub.call("_open_usage_file", by_path[script_path]) and _revealed == script_path and hub.selected_record().get("path") == effect_path, "external file route changed author draft/library record")
	# Existing conservative delete protection still sees these saved references.
	_check(not Catalog.incoming("effect", target).is_empty(), "usage work weakened delete reference guard")
	panel.hide()
	hub.free()
	_undo.clear_history(false)
	_undo.free()
	for path in _files: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _errors.is_empty(): print("PASS game systems usage: saved direct/candidate/file links, duplicate identity/path, dirty cache isolation, double-click/Back/filter, draft guard, stale/deleted/refreshed links and external file route")
	else: printerr("FAIL usage: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
