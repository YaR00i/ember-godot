extends SceneTree
## Editor-first standalone trigger: scene-owned sibling survives Map reimport,
## exposes visible bounds, writes the same action-list, and supports Undo/Redo.

const SOURCE_SCENE := "res://scenes/fan_town.tscn"
const TEMP_SCENE := "user://ember_test_standalone_trigger.tscn"
const TEMP_SCRIPT_ID := "ember_test_standalone_trigger_actions"
const Store = preload("res://addons/ember_import/ember_action_script_store.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var source_hash := FileAccess.get_sha256(SOURCE_SCENE)
	var old_document := Store.document(TEMP_SCRIPT_ID)
	Store.delete_document(TEMP_SCRIPT_ID)
	var packed := ResourceLoader.load(SOURCE_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var scene := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed else null
	if scene == null:
		errors.append("fan_town fixture unavailable")
	else:
		_run_history(errors, scene)
		scene.free()
	if FileAccess.get_sha256(SOURCE_SCENE) != source_hash:
		errors.append("standalone authoring changed source fan_town.tscn")
	_restore_fixture(old_document)
	if FileAccess.file_exists(TEMP_SCENE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SCENE))
	if not errors.is_empty():
		printerr("FAIL standalone trigger authoring")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS standalone trigger authoring")
	print("  root/AuthoredTriggers survives Map reimport and save/reopen")
	print("  Box bounds + typed quest gate + action chain use one Undo/Redo owner")
	print("  distance uses the full volume; deleting the zone is reversible")
	return 0


func _run_history(errors: Array[String], scene: Node) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var anchor := scene.get_node_or_null("Map/Props/ft_fountain") as Node3D
	if anchor == null:
		errors.append("standalone anchor fixture missing")
		history.free()
		return
	# Props and AuthoredTriggers are identity siblings in the authored scene.
	var expected_world := anchor.position + Vector3(0.0, 4.0, 0.0)
	var interact := actions.create_standalone_trigger(scene, expected_world)
	if interact == null:
		errors.append("create_standalone_trigger failed")
		history.free()
		return
	var container := scene.get_node_or_null("AuthoredTriggers")
	var shape := interact.get_node_or_null("Shape") as CollisionShape3D
	var box := shape.shape as BoxShape3D if shape else null
	if container == null or interact.get_parent() != container:
		errors.append("standalone trigger is not under root/AuthoredTriggers")
	elif container.owner != scene or interact.owner != scene or shape.owner != scene:
		errors.append("standalone trigger subtree is not scene-owned")
	if box == null:
		errors.append("standalone trigger has no BoxShape3D")
	if not interact.position.is_equal_approx(expected_world):
		errors.append("standalone trigger was not created at selected anchor")
	var snapshot := EmberObjectInspectorModel.snapshot(interact)
	if str(snapshot.get("mapId", "")) != "fan_town":
		errors.append("standalone Inspector could not resolve sibling Map owner")
	if (snapshot.get("components", []) as Array).size() != 2:
		errors.append("standalone Inspector lacks volume + Interact cards")
	var panel := EmberObjectInspectorPanel.new()
	panel.setup(interact, snapshot)
	if panel.find_child("Component_trigger_volume", true, false) == null:
		errors.append("standalone Inspector has no trigger volume card")
	if panel.find_child("EditStandaloneBoundsButton", true, false) == null:
		errors.append("standalone Inspector has no bounds action")
	if panel.find_child("EditActionChainButton", true, false) == null:
		errors.append("standalone Inspector has no action-chain action")
	panel.free()

	var rules := EmberSceneAuthoring.interact_values(interact)
	rules.condition_flag_id = "sandbox_notice_status"
	rules.condition_value = "active"
	rules.fallback_script_id = "sandbox_notice"
	rules.one_shot = true
	rules.completion_flag_id = "fan_town_trigger_1_used"
	rules.activation_mode = "enter"
	if not actions.save_standalone(interact, rules, scene):
		errors.append("standalone launch rules save failed")
	elif (
		interact.condition_flag_id != "sandbox_notice_status"
		or interact.condition_value != "active"
		or interact.fallback_script_id != "sandbox_notice"
		or not interact.one_shot
		or interact.completion_flag_id != "fan_town_trigger_1_used"
		or interact.activation_mode != "enter"
	):
		errors.append("standalone launch rules changed during normalization")
	history.undo()
	if (
		not interact.condition_flag_id.is_empty()
		or interact.condition_value != true
		or interact.one_shot
		or interact.activation_mode != "press"
	):
		errors.append("standalone launch rules Undo did not restore defaults")
	history.redo()

	if not actions.save_standalone_bounds(interact, Vector3(48.0, 10.0, 32.0), scene):
		errors.append("standalone bounds save failed")
	elif not EmberSceneAuthoring.standalone_box_size(interact).is_equal_approx(Vector3(48.0, 10.0, 32.0)):
		errors.append("standalone bounds did not update")
	if interact.distance_to_world(interact.position + Vector3(20.0, 0.0, 0.0)) > 0.001:
		errors.append("interaction distance still uses center instead of box volume")
	if interact.distance_to_world(interact.position + Vector3(30.0, 0.0, 0.0)) < 5.9:
		errors.append("interaction distance outside box is incorrect")
	history.undo()
	if EmberSceneAuthoring.standalone_box_size(interact).is_equal_approx(Vector3(48.0, 10.0, 32.0)):
		errors.append("bounds Undo did not restore previous size")
	history.redo()

	var document := {
		"id": TEMP_SCRIPT_ID,
		"nameRu": "Самостоятельная тестовая зона",
		"steps": [
			{"type": "talk", "dialogueId": "sandbox_notice_talk"},
			{"type": "set_flag", "flag": "standalone_trigger_done", "value": true},
		],
	}
	if not actions.save_standalone_chain(interact, document, scene):
		errors.append("standalone action-chain save failed")
	elif interact.script_id != TEMP_SCRIPT_ID or not Store.exists(TEMP_SCRIPT_ID):
		errors.append("standalone action-chain did not bind JSON + Interact")

	var map := scene.get_node_or_null("Map") as EmberMapLoader
	if map == null:
		errors.append("fan_town Map missing before reimport survival check")
	else:
		# Full reimport starts by clearing every generated child below Map.
		# Calling that stage directly keeps this detached editor fixture free of
		# runtime lighting work while proving the ownership boundary we rely on.
		map._clear_generated()
		if scene.get_node_or_null("AuthoredTriggers/%s" % interact.name) != interact:
			errors.append("Map reimport deleted root-owned standalone trigger")

	var saved := PackedScene.new()
	if saved.pack(scene) != OK or ResourceSaver.save(saved, TEMP_SCENE) != OK:
		errors.append("standalone trigger scene could not be saved")
	else:
		var reopened_pack := ResourceLoader.load(TEMP_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		var reopened := reopened_pack.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if reopened_pack else null
		var reopened_interact := reopened.get_node_or_null("AuthoredTriggers/%s" % interact.name) as EmberInteract if reopened else null
		if reopened_interact == null or reopened_interact.script_id != TEMP_SCRIPT_ID:
			errors.append("standalone trigger did not survive save/reopen")
		elif not EmberSceneAuthoring.standalone_box_size(reopened_interact).is_equal_approx(Vector3(48.0, 10.0, 32.0)):
			errors.append("standalone bounds did not survive save/reopen")
		elif (
			reopened_interact.condition_flag_id != "sandbox_notice_status"
			or reopened_interact.condition_value != "active"
			or reopened_interact.fallback_script_id != "sandbox_notice"
			or not reopened_interact.one_shot
			or reopened_interact.completion_flag_id != "fan_town_trigger_1_used"
			or reopened_interact.activation_mode != "enter"
		):
			errors.append("standalone launch rules did not survive save/reopen")
		if reopened:
			reopened.free()

	if not actions.remove_standalone(interact, scene):
		errors.append("standalone zone remove failed")
	elif interact.get_parent() != null:
		errors.append("standalone zone remove left node attached")
	history.undo()
	if scene.get_node_or_null("AuthoredTriggers/%s" % interact.name) != interact:
		errors.append("standalone zone Undo did not restore node")
	history.redo()
	if interact.get_parent() != null:
		errors.append("standalone zone redo did not remove node")
	history.clear_history(false)
	history.free()


func _restore_fixture(old_document: Dictionary) -> void:
	if old_document.is_empty():
		Store.delete_document(TEMP_SCRIPT_ID)
	else:
		Store.write_document(old_document)
