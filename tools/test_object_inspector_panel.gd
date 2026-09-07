extends SceneTree
## I1 smoke: the native Inspector panel renders the read-only component cards,
## routes its actions, and repeated panel lifecycles leave no controls.
## EditorInspectorPlugin itself is covered by the headless editor lifecycle smoke.

const TOWN_SCENE := "res://scenes/fan_town.tscn"
const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"

var _rebuild_requests := 0
var _interact_save_requests := 0
var _interact_remove_requests := 0
var _chain_remove_requests := 0
var _last_interact_values: Dictionary = {}


func _init() -> void:
	var errors: Array[String] = []
	var packed := ResourceLoader.load(TOWN_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var town := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null
	if town == null:
		errors.append("fan_town could not be instantiated")
	else:
		var door := town.get_node_or_null("Map/Props/ft_mage_door") as EmberVoxelProp
		var lantern := _first_lantern(town)
		if door == null or lantern == null:
			errors.append("door/lantern fixtures missing")
		else:
			var door_panel := EmberObjectInspectorPanel.new()
			door_panel.setup(door, EmberObjectInspectorModel.snapshot(door))
			if door_panel.find_child("Component_interact", true, false) == null:
				errors.append("door panel has no Interact card")
			if door_panel.find_child("Component_renderer", true, false) == null:
				errors.append("door panel has no Renderer card")
			var renderer_content := door_panel.find_child("Content_renderer", true, false) as Control
			var interact_content := door_panel.find_child("Content_interact", true, false) as Control
			if renderer_content == null or renderer_content.visible:
				errors.append("Renderer card must start collapsed for a compact Inspector")
			if interact_content == null or not interact_content.visible:
				errors.append("Interact card must start expanded")
			if door_panel.find_child("InteractDestination", true, false) == null:
				errors.append("door panel has no compact destination block")
			door_panel.interact_remove_requested.connect(_on_interact_remove)
			var edit_interact := _button_with_text(door_panel, "Настройки")
			var remove_interact := _button_with_text(door_panel, "Удалить")
			if edit_interact == null or remove_interact == null:
				errors.append("existing Interact has no edit/remove actions")
			else:
				edit_interact.pressed.emit()
				if door_panel.find_child("InteractEditor", true, false) == null:
					errors.append("existing Interact editor is not created lazily")
				var outcome := door_panel.find_child("InteractOutcomeSummary", true, false) as Label
				if outcome == null or outcome.text.find("fan_town_mage") < 0:
					errors.append("Interact editor does not explain the in-game outcome")
				var advanced := door_panel.find_child("ToggleInteractAdvanced", true, false) as Button
				var condition_row := door_panel.find_child("FieldRow_condition_flag_id", true, false) as Control
				if advanced == null or condition_row == null or condition_row.visible:
					errors.append("unused technical launch rules are not collapsed")
				elif advanced != null:
					advanced.pressed.emit()
					if not condition_row.visible:
						errors.append("advanced launch rules do not expand on request")
				if _selected_metadata(door_panel, "Field_target_map_id") != "fan_town_mage":
					errors.append("door editor did not preload target map")
				remove_interact.pressed.emit()
				if _interact_remove_requests != 1:
					errors.append("remove Interact signal was not routed")
			var view_filter := door_panel.find_child("ViewFilter", true, false) as OptionButton
			if view_filter == null or view_filter.item_count != 2:
				errors.append("Inspector panel has no Все/Ошибки filter")
			door_panel.rebuild_requested.connect(_on_rebuild)
			door_panel.rebuild_requested.emit(door)
			if _rebuild_requests != 1:
				errors.append("Inspector rebuild signal was not emitted exactly once")
			door_panel.free()

			var omni := lantern.get_node_or_null("Omni")
			var light_panel := EmberObjectInspectorPanel.new()
			light_panel.setup(omni, EmberObjectInspectorModel.snapshot(omni))
			if light_panel.find_child("Component_light", true, false) == null:
				errors.append("generated Omni selection has no effective Light card")
			if light_panel.find_child("Actions", true, false) == null:
				errors.append("generated child panel has no owner/source actions")
			light_panel.interact_save_requested.connect(_on_interact_save)
			var add_interact := light_panel.find_child("AddInteractButton", true, false) as Button
			var quick_chain := light_panel.find_child("QuickTriggerChainButton", true, false) as Button
			if add_interact == null:
				errors.append("prop without Interact has no add action")
			else:
				add_interact.pressed.emit()
				var kind_option := light_panel.find_child("Field_kind", true, false) as OptionButton
				var script_option := light_panel.find_child("Field_script_id", true, false) as OptionButton
				if kind_option == null or script_option == null:
					errors.append("new Interact form has no kind/script catalogs")
				else:
					if _has_metadata(kind_option, "chest"):
						errors.append("new Interact form offers a non-authorable empty chest shell")
					_select_metadata(kind_option, "talk")
					kind_option.item_selected.emit(kind_option.selected)
					_select_metadata(script_option, "sandbox_guard_talk")
					var save_interact := light_panel.find_child("SaveInteract", true, false) as Button
					save_interact.pressed.emit()
					if _interact_save_requests != 1 or str(_last_interact_values.get("script_id", "")) != "sandbox_guard_talk":
						errors.append("add Interact form did not emit normalized talk values")
			if quick_chain == null:
				errors.append("prop without Interact has no quick trigger + chain action")
			else:
				quick_chain.pressed.emit()
				var chain_editor := light_panel.find_child("ActionChainEditor", true, false)
				var chain_id := light_panel.find_child("ActionChainId", true, false) as LineEdit
				if chain_editor == null or chain_id == null or chain_id.text.is_empty():
					errors.append("quick trigger did not create a lazy action-chain editor with suggested id")
				else:
					var step_type := light_panel.find_child("NewStepType", true, false) as OptionButton
					var add_step := light_panel.find_child("AddActionStepButton", true, false) as Button
					if step_type == null or step_type.item_count != 8 or add_step == null:
						errors.append("action-chain editor does not expose all eight canonical step types")
					else:
						_select_metadata(step_type, "change_map")
						add_step.pressed.emit()
						var map_field := light_panel.find_child("StepField_targetMapId", true, false) as OptionButton
						var region_field := light_panel.find_child("StepField_targetRegionId", true, false) as OptionButton
						if map_field == null or region_field == null:
							errors.append("change_map step has no map/entry catalogs")
						_select_metadata(step_type, "set_flag")
						add_step.pressed.emit()
						var flag_field := light_panel.find_child("StepField_flag", true, false) as LineEdit
						var flag_type := light_panel.find_child("StepField_value_type", true, false) as OptionButton
						var bool_field := light_panel.find_child("StepField_value_bool", true, false) as OptionButton
						var raw_value := light_panel.find_child("StepField_value", true, false) as LineEdit
						var quest_flag_library := light_panel.find_child("OpenQuestFlagLibrary", true, false) as Button
						if flag_field == null or flag_type == null or bool_field == null or raw_value == null:
							errors.append("set_flag step has no typed authoring controls")
						elif quest_flag_library == null:
							errors.append("set_flag step has no quest flag reference library")
						else:
							chain_editor.set("_quest_flag_target", flag_field)
							chain_editor.call("_choose_quest_flag_value", "sandbox_notice_read")
							if flag_field.text != "sandbox_notice_read":
								errors.append("quest flag library did not fill the action step")
							if not bool_field.visible or raw_value.visible:
								errors.append("boolean flag still exposes a raw true/false text field")
							_select_metadata(flag_type, "string")
							flag_type.item_selected.emit(flag_type.selected)
							if bool_field.visible or not raw_value.visible or not raw_value.placeholder_text.contains("west"):
								errors.append("text flag type did not switch to a guided text field")
							_select_metadata(flag_type, "bool")
							flag_type.item_selected.emit(flag_type.selected)
							flag_field.text = "editor_flag_false"
							bool_field.select(1)
							var authored: Dictionary = chain_editor.call("_document")
							var authored_steps: Array = authored.get("steps", [])
							var last_step: Dictionary = authored_steps.back() if not authored_steps.is_empty() else {}
							if str(last_step.get("flag", "")) != "editor_flag_false" or last_step.get("value", true) != false:
								errors.append("boolean flag UI did not serialize typed false")
					var cancel_chain := light_panel.find_child("CancelActionChain", true, false) as Button
					if cancel_chain == null:
						errors.append("new unsaved action-chain form has no explicit cancel button")
					else:
						cancel_chain.pressed.emit()
						if light_panel.find_child("ActionChainEditor", true, false) != null:
							errors.append("cancel did not dismiss the unsaved action-chain form")
			light_panel.free()

			var root := get_root()
			var baseline := root.get_child_count()
			for _index in 20:
				var panel := EmberObjectInspectorPanel.new()
				panel.setup(lantern, EmberObjectInspectorModel.snapshot(lantern))
				root.add_child(panel)
				panel.free()
			if root.get_child_count() != baseline:
				errors.append("repeated Inspector panel lifecycle leaked controls")
		town.free()
	_test_existing_chain_remove_ui(errors)
	_test_guided_quest_interact_ui(errors)
	if not errors.is_empty():
		printerr("FAIL object inspector panel")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS object inspector panel")
	print("  read-only panel fixtures")
	print("  compact cards + door destination + Все/Ошибки filter rendered")
	print("  action-chain palette + typed flag controls render")
	print("  rebuild signal routes to existing owner")
	print("  20 panel lifecycles leave no controls")
	quit(0)


func _on_rebuild(_prop: EmberVoxelProp) -> void:
	_rebuild_requests += 1


func _test_existing_chain_remove_ui(errors: Array[String]) -> void:
	var packed := ResourceLoader.load(SANDBOX_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var sandbox := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null
	var prop := sandbox.get_node_or_null("Map/Props/sbx_quest_active") as EmberVoxelProp if sandbox else null
	if prop == null:
		errors.append("existing action-chain UI fixture is missing")
		if sandbox:
			sandbox.free()
		return
	var panel := EmberObjectInspectorPanel.new()
	panel.setup(prop, EmberObjectInspectorModel.snapshot(prop))
	panel.chain_remove_requested.connect(_on_chain_remove)
	var edit_chain := panel.find_child("EditActionChainButton", true, false) as Button
	if edit_chain == null:
		errors.append("existing action chain has no editor button")
	else:
		edit_chain.pressed.emit()
		var delete_chain := panel.find_child("DeleteActionChain", true, false) as Button
		if delete_chain == null:
			errors.append("saved action chain has no delete button")
		else:
			delete_chain.pressed.emit()
			if _chain_remove_requests != 1:
				errors.append("delete action-chain signal was not routed")
			if panel.find_child("ActionChainEditor", true, false) != null:
				errors.append("delete did not dismiss the action-chain form")
	panel.free()
	sandbox.free()


func _test_guided_quest_interact_ui(errors: Array[String]) -> void:
	var packed := ResourceLoader.load(SANDBOX_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var sandbox := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null
	var prop := sandbox.get_node_or_null("Map/Props/sbx_quest_active") as EmberVoxelProp if sandbox else null
	if prop == null:
		errors.append("quest interaction UI fixture is missing")
		if sandbox:
			sandbox.free()
		return
	var panel := EmberObjectInspectorPanel.new()
	panel.setup(prop, EmberObjectInspectorModel.snapshot(prop))
	var actions := panel.find_child("InteractActions", true, false)
	if not actions is HFlowContainer:
		errors.append("Interact actions do not wrap in a narrow Inspector")
	var edit := _button_with_text(panel, "Настройки")
	if edit == null:
		errors.append("quest marker has no guided settings button")
	else:
		edit.pressed.emit()
		var quest := panel.find_child("Field_quest_id", true, false) as OptionButton
		var script := panel.find_child("Field_script_id", true, false) as OptionButton
		var summary := panel.find_child("InteractOutcomeSummary", true, false) as Label
		var help := panel.find_child("QuestBindingHint", true, false) as Label
		var fallback := panel.find_child("FieldRow_quest_status", true, false) as Control
		var custom_icon := panel.find_child("FieldRow_icon_id", true, false) as Control
		if quest == null or quest.get_item_text(quest.selected).find("Записка у ворот") < 0:
			errors.append("quest selector still shows only a technical ID")
		if script == null or script.get_item_text(script.selected).find("События задания") < 0:
			errors.append("action selector still shows only a technical ID")
		if summary == null or summary.text.find("роль и иконка") < 0:
			errors.append("quest marker form does not explain dynamic marker behavior")
		if help == null or not help.visible or help.text.find("События задания") < 0:
			errors.append("quest marker form has no plain-language event guidance")
		if fallback == null or custom_icon == null or fallback.visible or custom_icon.visible:
			errors.append("rare quest fallback fields are not collapsed by default")
		var advanced := panel.find_child("ToggleInteractAdvanced", true, false) as Button
		if advanced != null:
			advanced.pressed.emit()
			if not fallback.visible or not custom_icon.visible:
				errors.append("rare quest fallback fields do not expand")
	panel.free()
	sandbox.free()


func _on_chain_remove(_prop: EmberVoxelProp) -> void:
	_chain_remove_requests += 1


func _on_interact_save(_prop: EmberVoxelProp, values: Dictionary) -> void:
	_interact_save_requests += 1
	_last_interact_values = values


func _on_interact_remove(_prop: EmberVoxelProp) -> void:
	_interact_remove_requests += 1


func _first_lantern(root: Node) -> EmberVoxelProp:
	if root is EmberVoxelProp and root.get_node_or_null("Omni") != null:
		return root as EmberVoxelProp
	for child in root.get_children():
		var found := _first_lantern(child)
		if found != null:
			return found
	return null


func _button_with_text(root: Node, label: String) -> Button:
	if root is Button and (root as Button).text == label:
		return root as Button
	for child in root.get_children():
		var found := _button_with_text(child, label)
		if found != null:
			return found
	return null


func _select_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _selected_metadata(root: Node, node_name: String) -> String:
	var option := root.find_child(node_name, true, false) as OptionButton
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _has_metadata(option: OptionButton, value: String) -> bool:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			return true
	return false
