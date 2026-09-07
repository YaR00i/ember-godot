extends SceneTree
## Reproducible Forward+ screenshots of the functional Stage 2 party/save UI.

const SANDBOX_SCENE := preload("res://scenes/agent_sandbox.tscn")
const SLOTS_OUTPUT := "user://party_save_v2_slots.png"
const PARTY_OUTPUT := "user://party_save_v2_inventory.png"


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_capture_and_quit.call_deferred()


func _capture_and_quit() -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null:
		printerr("FAIL party/save v2 capture: progress autoload missing")
		quit(1)
		return
	progress.storage_root = "user://ember-tests/party-save-v2-capture"
	progress.legacy_storage_root = progress.storage_root.path_join("legacy")
	progress.persistence_enabled = true
	progress.restore_enabled = false
	progress.reset_new_game()
	progress.inventory = {"coin": 42, "funeral_polearm": 1, "herb": 3, "qingxin_tea": 1}
	var mira: Dictionary = progress.party.get("mira", {})
	mira["level"] = 3
	mira["xp"] = 47
	mira["hp"] = 11
	mira["mp"] = 23
	progress.party["mira"] = mira
	var sandbox := SANDBOX_SCENE.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	progress.playtime_seconds = 935.0
	progress.save_slot(0)
	progress.playtime_seconds = 3723.0
	progress.save_slot(1)
	progress.playtime_seconds = 7544.0
	progress.save_slot(2)
	progress.save_autosave()
	var pause := sandbox.find_child("ExplorePauseUI", true, false) as EmberExplorePauseMenu
	var inventory := sandbox.find_child("InventoryUI", true, false) as EmberInventoryUi
	if pause == null or inventory == null:
		printerr("FAIL party/save v2 capture: UI owner missing")
		sandbox.free()
		quit(1)
		return
	pause.open_menu()
	await process_frame
	await process_frame
	var error := root.get_texture().get_image().save_png(SLOTS_OUTPUT)
	if error != OK:
		printerr("FAIL party/save slot capture: ", error_string(error))
		sandbox.free()
		quit(1)
		return
	pause.close_menu()
	inventory.open()
	inventory.call("_select_hero", 1)
	await process_frame
	await process_frame
	error = root.get_texture().get_image().save_png(PARTY_OUTPUT)
	if error != OK:
		printerr("FAIL party inventory capture: ", error_string(error))
		sandbox.free()
		quit(1)
		return
	print("PASS Forward+ save slots capture: ", ProjectSettings.globalize_path(SLOTS_OUTPUT))
	print("PASS Forward+ party inventory capture: ", ProjectSettings.globalize_path(PARTY_OUTPUT))
	progress.persistence_enabled = false
	sandbox.free()
	quit(0)
