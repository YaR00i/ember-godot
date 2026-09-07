extends SceneTree
## Shared exploration pause/quit menu over a real agent_sandbox runtime scene.

const SANDBOX_SCENE := preload("res://scenes/agent_sandbox.tscn")


func _init() -> void:
	root.size = Vector2i(1280, 720)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	if change_scene_to_packed(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox")
	else:
		await scene_changed
		await process_frame
		await physics_frame
	var sandbox := current_scene
	var player := sandbox.get_node_or_null("Player") as EmberPlayer if sandbox != null else null
	var pause_ui := sandbox.get_node_or_null("CanvasLayer/ExplorePauseUI") as EmberExplorePauseMenu if sandbox != null else null
	var inventory_ui := sandbox.get_node_or_null("CanvasLayer/InventoryUI") as EmberInventoryUi if sandbox != null else null
	var menu_button := sandbox.find_child("ExploreMenuButton", true, false) as Button if sandbox != null else null
	var overlay := sandbox.find_child("ExplorePauseOverlay", true, false) as ColorRect if sandbox != null else null
	if player == null or pause_ui == null or inventory_ui == null or menu_button == null or overlay == null:
		errors.append("exploration scene lost Player/PauseUI/InventoryUI/menu button wiring")
	else:
		var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
		if progress != null:
			progress.storage_root = "user://ember-tests/pause-save-v2-%d" % Time.get_ticks_usec()
			progress.legacy_storage_root = progress.storage_root.path_join("legacy")
			progress.persistence_enabled = true
			progress.reset_new_game()
		if player.pause_ui != pause_ui:
			errors.append("Player does not share the map-owned pause menu")
		inventory_ui.toggle()
		pause_ui.open_menu()
		if pause_ui.is_open() or paused:
			errors.append("pause menu opened over an active inventory instead of letting Esc close it first")
		inventory_ui.close()
		pause_ui.open_menu()
		if not pause_ui.is_open() or not overlay.visible or not paused:
			errors.append("exploration menu did not pause the SceneTree")
		pause_ui.call("_save_game")
		var feedback := sandbox.find_child("ExplorePauseFeedback", true, false) as Label
		if feedback == null or not feedback.text.contains("сохранена"):
			errors.append("manual save did not report success")
		for slot in EmberExploreState.MANUAL_SLOT_COUNT:
			if (
				sandbox.find_child("ExploreSaveSlot%dLabel" % (slot + 1), true, false) == null
				or sandbox.find_child("ExploreSaveSlot%d" % (slot + 1), true, false) == null
				or sandbox.find_child("ExploreLoadSlot%d" % (slot + 1), true, false) == null
				or sandbox.find_child("ExploreDeleteSlot%d" % (slot + 1), true, false) == null
			):
				errors.append("pause menu lost manual slot %d controls" % (slot + 1))
		if (
			sandbox.find_child("ExploreAutosaveLabel", true, false) == null
			or sandbox.find_child("ExploreDeleteAutosave", true, false) == null
		):
			errors.append("pause menu does not expose separate autosave metadata")
		pause_ui.call("_request_delete_slot", 0)
		if feedback == null or not feedback.text.contains("ещё раз"):
			errors.append("manual delete did not require a second confirmation")
		pause_ui.call("_request_delete_slot", 0)
		if progress != null and bool(progress.slot_metadata(0).get("exists", false)):
			errors.append("confirmed manual delete left the slot loadable")
		if feedback == null or not feedback.text.contains("резервная копия"):
			errors.append("confirmed manual delete did not explain recovery archive")
		pause_ui.close_menu()
		if pause_ui.is_open() or paused:
			errors.append("exploration menu did not resume the SceneTree")
	current_scene.free()
	if not errors.is_empty():
		printerr("FAIL explore pause menu")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS explore pause menu")
	print("  every fan_town.gd map creates one visible Esc menu")
	print("  modal UI closes first; pause exposes save/load/delete with confirmation")
	quit(0)
