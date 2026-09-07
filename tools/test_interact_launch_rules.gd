extends SceneTree
## Conditions and one-shot routing reuse EmberInteract, typed explore flags and
## the existing action sequencer. No condition data is written into JOI JSON.

const Store = preload("res://addons/ember_import/ember_action_script_store.gd")
const PRIMARY_ID := "ember_test_launch_primary"
const FALLBACK_ID := "ember_test_launch_fallback"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var old_primary := Store.document(PRIMARY_ID)
	var old_fallback := Store.document(FALLBACK_ID)
	_write_fixtures(errors)
	_test_pure_contract(errors)
	_test_editor_contract(errors)
	await _test_runtime_contract(errors)
	_restore_fixture(PRIMARY_ID, old_primary)
	_restore_fixture(FALLBACK_ID, old_fallback)
	if not errors.is_empty():
		printerr("FAIL interact launch rules")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS interact launch rules")
	print("  typed bool/string condition routes primary/fallback through one Interact")
	print("  one-shot is consumed only after successful primary completion")
	print("  aborted dialogue and fallback route do not consume completion flag")
	return 0


func _write_fixtures(errors: Array[String]) -> void:
	for document in [
		{
			"id": PRIMARY_ID,
			"nameRu": "Launch primary test",
			"steps": [{"type": "set_flag", "flag": "launch_primary_seen", "value": true}],
		},
		{
			"id": FALLBACK_ID,
			"nameRu": "Launch fallback test",
			"steps": [{"type": "set_flag", "flag": "launch_fallback_seen", "value": true}],
		},
	]:
		if Store.write_document(document) != OK:
			errors.append("could not write temporary launch-rule action list")


func _test_pure_contract(errors: Array[String]) -> void:
	var fallback := EmberInteractRules.route(
		PRIMARY_ID, "quest_ready", true, FALLBACK_ID, true, "launch_used", {},
	)
	if not bool(fallback.get("available", false)) or bool(fallback.get("primary", true)):
		errors.append("missing required flag did not select fallback")
	elif str(fallback.get("scriptId", "")) != FALLBACK_ID:
		errors.append("fallback route lost its script id")
	var primary := EmberInteractRules.route(
		PRIMARY_ID, "quest_ready", true, FALLBACK_ID, true, "launch_used", {"quest_ready": true},
	)
	if not bool(primary.get("primary", false)) or str(primary.get("scriptId", "")) != PRIMARY_ID:
		errors.append("matching bool flag did not select primary")
	var consumed := EmberInteractRules.route(
		PRIMARY_ID, "quest_ready", true, FALLBACK_ID, true, "launch_used",
		{"quest_ready": true, "launch_used": true},
	)
	if bool(consumed.get("available", true)) or str(consumed.get("reason", "")) != "already_completed":
		errors.append("completion flag did not disable one-shot interaction")
	var expected_false := EmberInteractRules.route(
		PRIMARY_ID, "not_started", false, "", false, "", {},
	)
	if not bool(expected_false.get("primary", false)):
		errors.append("expected Нет did not accept an absent flag")
	var active_status := EmberInteractRules.route(
		PRIMARY_ID, "quest_status", "active", FALLBACK_ID, false, "",
		{"quest_status": "active"},
	)
	if not bool(active_status.get("primary", false)):
		errors.append("typed string condition could not match active quest status")
	var wrong_status := EmberInteractRules.route(
		PRIMARY_ID, "quest_status", "active", FALLBACK_ID, false, "",
		{"quest_status": "done"},
	)
	if bool(wrong_status.get("primary", true)) or str(wrong_status.get("scriptId", "")) != FALLBACK_ID:
		errors.append("typed string condition did not route a mismatched quest status")
	if EmberSceneAuthoring.suggested_completion_flag("fan-town", "Trigger 4") != "fan_town_trigger_4_used":
		errors.append("suggested completion flag is not stable/safe")


func _test_editor_contract(errors: Array[String]) -> void:
	var editor := EmberInteractEditor.new()
	editor.setup(
		EmberSceneAuthoring.normalized_interact_values({"kind": "trigger", "script_id": PRIMARY_ID}),
		false,
		"agent_sandbox",
		"agent_sandbox_trigger_1_used",
	)
	var condition := editor.find_child("Field_condition_flag_id", true, false) as LineEdit
	var expected_row := editor.find_child("FieldRow_condition_value", true, false) as Control
	var expected := editor.find_child("Field_condition_value", true, false) as EmberTypedValueEditor
	var fallback_row := editor.find_child("FieldRow_fallback_script_id", true, false) as Control
	var once := editor.find_child("Field_one_shot", true, false) as CheckBox
	var completion := editor.find_child("Field_completion_flag_id", true, false) as LineEdit
	var activation := editor.find_child("Field_activation_mode", true, false) as OptionButton
	if condition == null or expected_row == null or expected == null or fallback_row == null or once == null or completion == null or activation == null:
		errors.append("Inspector launch-rule controls are incomplete")
	else:
		if activation.get_item_text(1) != "Клавиша F" or activation.get_item_text(2) != "При входе":
			errors.append("activation mode does not use guided Russian labels")
		if expected_row.visible or fallback_row.visible:
			errors.append("condition details are visible before a flag is entered")
		var advanced := editor.find_child("ToggleInteractAdvanced", true, false) as Button
		if advanced == null:
			errors.append("launch rules have no advanced disclosure")
		else:
			advanced.pressed.emit()
		condition.text = "quest_ready"
		condition.text_changed.emit(condition.text)
		if not expected_row.visible or not fallback_row.visible:
			errors.append("condition details did not open after flag input")
		if editor.find_child("OpenConditionQuestFlagLibrary", true, false) == null:
			errors.append("launch condition has no quest flag reference picker")
		once.button_pressed = true
		once.toggled.emit(true)
		if completion.text != "agent_sandbox_trigger_1_used":
			errors.append("one-shot did not suggest a stable completion flag")
	editor.free()


func _test_runtime_contract(errors: Array[String]) -> void:
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	await process_frame
	var interact := EmberSceneAuthoring.make_interact({
		"kind": "trigger",
		"script_id": PRIMARY_ID,
		"condition_flag_id": "quest_ready",
		"condition_expected": true,
		"fallback_script_id": FALLBACK_ID,
		"one_shot": true,
		"completion_flag_id": "launch_used",
	}, 16.0)
	root.add_child(interact)
	await process_frame
	ui.activate(interact)
	if state.flags.get("launch_fallback_seen", false) != true:
		errors.append("runtime fallback chain did not execute")
	if state.flags.has("launch_used"):
		errors.append("fallback chain consumed one-shot completion")
	state.set_flag("quest_ready", true, false)
	ui.activate(interact)
	if state.flags.get("launch_primary_seen", false) != true:
		errors.append("runtime primary chain did not execute")
	if state.flags.get("launch_used", false) != true:
		errors.append("successful primary did not persist one-shot completion")
	if interact.runtime_available(state.flags):
		errors.append("completed one-shot remained runtime-available")
	var typed_interact := EmberSceneAuthoring.make_interact({
		"kind": "trigger",
		"script_id": PRIMARY_ID,
		"condition_flag_id": "quest_status",
		"condition_value": "active",
	}, 16.0)
	if not typed_interact.runtime_available({"quest_status": "active"}):
		errors.append("typed scene-authored quest status condition was not preserved")
	if typed_interact.runtime_available({"quest_status": "done"}):
		errors.append("typed scene-authored condition accepted the wrong quest status")
	typed_interact.free()

	state.flags.erase("launch_used")
	interact.script_id = "sandbox_guard_talk"
	interact.condition_flag_id = ""
	interact.fallback_script_id = ""
	ui.activate(interact)
	if str(ui.view_state().get("mode", "")) != EmberInteractionUi.MODE_DIALOGUE:
		errors.append("abort fixture did not start dialogue")
	ui.close()
	if state.flags.has("launch_used"):
		errors.append("aborted dialogue consumed one-shot completion")

	state.flags.erase("launch_primary_seen")
	var player := EmberPlayer.new()
	player.name = "LaunchRulePlayer"
	player.progress_state = state
	player.interaction_ui = ui
	root.add_child(player)
	var auto := EmberSceneAuthoring.make_interact({
		"kind": "trigger",
		"script_id": PRIMARY_ID,
		"activation_mode": "enter",
		"one_shot": true,
		"completion_flag_id": "auto_launch_used",
	}, 16.0)
	auto.name = "AutoLaunch"
	root.add_child(auto)
	await process_frame
	if auto.is_in_group("ember_interact") or not auto.monitoring or auto.collision_mask != 2:
		errors.append("enter mode did not replace F-group with player Area monitoring")
	auto._on_body_entered(player)
	if state.flags.get("launch_primary_seen", false) != true:
		errors.append("body_entered did not route through the existing action sequencer")
	if state.flags.get("auto_launch_used", false) != true:
		errors.append("successful auto-trigger did not consume one-shot")
	state.flags.erase("auto_launch_used")
	auto.activation_mode = "press"
	auto.refresh_runtime_binding()
	if not auto.is_in_group("ember_interact") or auto.monitoring or auto.collision_mask != 0:
		errors.append("switching back to F did not restore the existing interaction path")
	ui.economy_state = null
	auto.queue_free()
	player.queue_free()
	interact.queue_free()
	ui.queue_free()
	state.free()
	await process_frame


func _restore_fixture(script_id: String, document: Dictionary) -> void:
	if document.is_empty():
		Store.delete_document(script_id)
	else:
		Store.write_document(document)
