extends SceneTree
## I2 contract: the actual Inspector action owner supports add/edit/remove,
## Undo/Redo and save/reopen without touching source scene or JOI map JSON.

const SOURCE_SCENE := "res://scenes/fan_town.tscn"
const SOURCE_MAP_ID := "fan_town"
const TEMP_SCENE := "user://ember_inspector_interact_roundtrip.tscn"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var scene_hash := FileAccess.get_sha256(SOURCE_SCENE)
	var map_hash := FileAccess.get_sha256(EmberPack.map_path(SOURCE_MAP_ID))
	var packed := ResourceLoader.load(SOURCE_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed else null
	if root == null:
		printerr("FAIL object inspector actions: fan_town unavailable")
		return 1
	var prop := root.get_node_or_null("Map/Props/ft_fountain") as EmberVoxelProp
	if prop == null or prop.get_node_or_null("Interact") != null:
		errors.append("clean ft_fountain fixture unavailable")
	else:
		var history := _test_action_history(errors, root, prop)
		_test_save_reopen(errors, root, prop)
		if history != null:
			history.clear_history(false)
			history.free()
	root.free()

	if FileAccess.get_sha256(SOURCE_SCENE) != scene_hash:
		errors.append("Inspector actions changed source fan_town.tscn")
	if FileAccess.get_sha256(EmberPack.map_path(SOURCE_MAP_ID)) != map_hash:
		errors.append("Inspector actions changed JOI fan_town.json")
	var temp_path := ProjectSettings.globalize_path(TEMP_SCENE)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	if not errors.is_empty():
		printerr("FAIL object inspector actions")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS object inspector actions")
	print("  add/edit/remove use one scene-owned Interact contract")
	print("  Undo/Redo restores nodes and all authored fields")
	print("  save/reopen preserves Interact + Shape ownership")
	print("  source .tscn and JOI map JSON unchanged")
	return 0


func _test_action_history(errors: Array[String], root: Node, prop: EmberVoxelProp) -> UndoRedo:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var talk := {
		"kind": "talk",
		"script_id": "sandbox_guard_talk",
		"note": "Inspector add test",
	}
	if not actions.save(prop, talk, root):
		errors.append("add action was rejected")
		return history
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null or interact.kind != "talk" or interact.script_id != "sandbox_guard_talk":
		errors.append("add action did not author talk fields")
		return history
	var shape := interact.get_node_or_null("Shape") as CollisionShape3D
	if interact.owner != root or shape == null or shape.owner != root:
		errors.append("added Interact/Shape is not scene-owned")
	history.undo()
	if prop.get_node_or_null("Interact") != null:
		errors.append("undo add did not detach Interact")
	history.redo()
	interact = prop.get_node_or_null("Interact") as EmberInteract
	if interact == null or interact.script_id != "sandbox_guard_talk":
		errors.append("redo add did not restore Interact")

	var shop := {
		"kind": "shop",
		"shop_id": "village_kiosk",
		"script_id": "sandbox_shop_intro",
		"note": "Inspector edit test",
	}
	actions.save(prop, shop, root)
	if interact.kind != "shop" or interact.shop_id != "village_kiosk":
		errors.append("edit action did not apply shop fields")
	history.undo()
	if interact.kind != "talk" or interact.script_id != "sandbox_guard_talk":
		errors.append("undo edit did not restore talk fields")
	history.redo()
	if interact.kind != "shop" or interact.script_id != "sandbox_shop_intro":
		errors.append("redo edit did not restore shop fields")

	actions.remove(prop, root)
	if prop.get_node_or_null("Interact") != null:
		errors.append("remove action did not detach Interact")
	history.undo()
	interact = prop.get_node_or_null("Interact") as EmberInteract
	if interact == null or interact.kind != "shop" or interact.owner != root:
		errors.append("undo remove did not restore owned shop Interact")
	return history


func _test_save_reopen(errors: Array[String], root: Node, prop: EmberVoxelProp) -> void:
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null:
		errors.append("save fixture lost Interact")
		return
	var staged := PackedScene.new()
	var pack_error := staged.pack(root)
	if pack_error != OK or ResourceSaver.save(staged, TEMP_SCENE) != OK:
		errors.append("temporary scene could not be saved")
		return
	var reopened_packed := ResourceLoader.load(TEMP_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var reopened := reopened_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if reopened_packed else null
	if reopened == null:
		errors.append("temporary scene could not be reopened")
		return
	var saved := reopened.get_node_or_null("Map/Props/ft_fountain/Interact") as EmberInteract
	if saved == null or saved.kind != "shop" or saved.shop_id != "village_kiosk":
		errors.append("saved Interact fields did not survive reopen")
	elif saved.get_node_or_null("Shape") == null:
		errors.append("saved Interact Shape did not survive reopen")
	reopened.free()
