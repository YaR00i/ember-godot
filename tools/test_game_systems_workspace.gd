extends SceneTree
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _errors: Array[String] = []
var _route := ""

func _init() -> void:
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	Maps.prepare(self, "user://game-systems-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	var workspace := Workspace.new()
	workspace.configure(null, null)
	workspace.size = Vector2(1280, 720)
	root.add_child(workspace)
	workspace.system_resource_requested.connect(func(path: String) -> void: _route = path)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	await process_frame
	_check(hub != null and hub.visible, "hub did not open independently of a scene")
	_check(hub.get_combined_minimum_size().x <= 1280, "prototype minimum width exceeds 1280")
	for module in Catalog.MODULES:
		hub.call("select_module", str(module[0]))
		_check(hub.get("_records").size() == Catalog.entries(str(module[0])).size(), "module does not project existing catalog: " + str(module[0]))
	hub.call("select_module", "equipment", "traveler_tunic")
	_check(hub.call("selected_record").get("id") == "traveler_tunic", "equipment lost the shared item source")
	var search := hub.find_child("GameSystemsSearch", true, false) as LineEdit
	search.text = "missing-prototype-record"
	search.text_changed.emit(search.text)
	_check(hub.call("selected_record").is_empty(), "empty search kept an actionable hidden record")
	hub.call("_open_existing_editor")
	_check(_route.is_empty(), "empty search opened a stale resource")
	hub.call("select_module", "effect", "missing-linked-effect")
	_check(hub.call("selected_record").is_empty(), "missing link silently selected another effect")
	hub.call("select_module", "action", "earth_wall")
	var links: Array = Catalog.relations("action", hub.call("selected_record"))
	_check(not links.is_empty(), "composed action lost effect links")
	hub.call("_open_existing_editor")
	_check(workspace.get("_current_kind") == "combat_content", "action did not reach existing combat editor")
	_check(workspace.get("_combat_content_workspace").get("_selected_id") == "earth_wall", "action route opened the wrong record")
	workspace.open_resource("systems", "systems_library")
	hub.call("select_module", "encounter", "colored_crossing_demo")
	var run := hub.find_child("GameSystemsRunEncounter", true, false) as Button
	_check(run != null and not run.disabled, "valid saved encounter has no Lab action")
	hub.call("begin_edit")
	hub.get("_session").set_value("victory_xp", 40)
	var blocked: Dictionary = hub.call("_run_selected_encounter")
	_check(not blocked.get("ok", true) and hub.has_unsaved_changes(), "Lab launch bypassed unsaved draft guard")
	hub.call("discard_changes")
	hub.call("select_module", "encounter", "colored_crossing_demo")
	hub.call("_open_existing_editor")
	_check(_route.ends_with("colored_crossing_demo.tres"), "encounter did not reach native Inspector route")
	hub.call("select_module", "lab")
	hub.call("_open_existing_editor")
	_check(_route == "res://scenes/combat_lab.tscn", "laboratory route started an unrelated scene")
	hub.call("select_module", "item", "herb")
	hub.call("_open_existing_editor")
	var item_window := workspace.find_child("GameSystemsItemWindow", true, false)
	_check(item_window != null and item_window.find_child("EmberItemEditor", true, false) != null, "item did not reach the existing form")
	if item_window != null: item_window.free()
	# The actual editor's unsaved-draft gate must still apply to the new entry.
	workspace.open_resource("dialogue", "colored_crossing_intro")
	workspace.set("_dialogue_history", [workspace.get("_dialogue_draft").duplicate(true)])
	var draft: Dictionary = workspace.get("_dialogue_draft")
	draft["nameRu"] = "Unsaved prototype gate"
	workspace.call("_request_navigation", "systems", "systems_library", false)
	_check(workspace.get("_current_kind") == "dialogue" and not workspace.get("_pending_navigation").is_empty(), "home bypassed the unsaved dialogue guard")
	workspace.call("_cancel_discard_navigation")
	_check(workspace.get("_dialogue_draft").get("nameRu") == "Unsaved prototype gate", "cancel lost the dialogue draft")
	workspace.free()
	await process_frame
	if not _errors.is_empty():
		printerr("FAIL game systems: ", "; ".join(_errors))
		quit(1)
		return
	print("PASS game systems navigation, real catalog links, search isolation, existing editor routes, item close, unsaved draft guard")
	quit(0)

func _check(condition: bool, error: String) -> void:
	if not condition: _errors.append(error)
