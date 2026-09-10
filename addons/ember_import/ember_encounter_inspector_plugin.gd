@tool
class_name EmberEncounterInspectorPlugin
extends EditorInspectorPlugin

const EncounterPanel := preload("res://addons/ember_import/ember_encounter_inspector_panel.gd")
const UnitPanel := preload("res://addons/ember_import/ember_combat_unit_inspector_panel.gd")
const ActionPanel := preload("res://addons/ember_import/ember_combat_action_inspector_panel.gd")
const EffectPanel := preload("res://addons/ember_import/ember_combat_effect_inspector_panel.gd")
const StatusPanel := preload("res://addons/ember_import/ember_combat_status_inspector_panel.gd")
const AiProfilePanel := preload("res://addons/ember_import/ember_combat_ai_profile_inspector_panel.gd")
const LootTablePanel := preload("res://addons/ember_import/ember_combat_loot_table_inspector_panel.gd")

var _editor_interface: EditorInterface
var _undo_redo: Object


func configure(editor_interface: EditorInterface, undo_redo: Object = null) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo


func _can_handle(object: Object) -> bool:
	return (
		object is EmberEncounterResource
		or object is EmberCombatUnitResource
		or object is EmberCombatActionResource
		or _is_combat_status(object)
		or _is_combat_effect(object)
		or object is EmberCombatAiProfileResource
		or object is EmberCombatLootTableResource
	)


func _parse_begin(object: Object) -> void:
	if _is_combat_status(object):
		var status_panel := StatusPanel.new() as VBoxContainer
		status_panel.call("setup", object as Resource)
		add_custom_control(status_panel)
		return
	if object is EmberCombatLootTableResource:
		var loot_panel := LootTablePanel.new() as EmberCombatLootTableInspectorPanel
		loot_panel.setup(object as EmberCombatLootTableResource, _editor_interface, _undo_redo)
		add_custom_control(loot_panel)
		return
	if object is EmberCombatAiProfileResource:
		var ai_panel := AiProfilePanel.new() as EmberCombatAiProfileInspectorPanel
		ai_panel.setup(object as EmberCombatAiProfileResource)
		add_custom_control(ai_panel)
		return
	if object is EmberCombatActionResource:
		var action_panel := ActionPanel.new() as EmberCombatActionInspectorPanel
		action_panel.setup(object as EmberCombatActionResource, _editor_interface, _undo_redo)
		add_custom_control(action_panel)
		return
	if _is_combat_effect(object):
		var effect_panel := EffectPanel.new() as VBoxContainer
		effect_panel.call("setup", object as Resource)
		add_custom_control(effect_panel)
		return
	if object is EmberCombatUnitResource:
		var unit_panel := UnitPanel.new() as EmberCombatUnitInspectorPanel
		unit_panel.setup(object as EmberCombatUnitResource, _editor_interface, _undo_redo)
		add_custom_control(unit_panel)
		return
	var encounter := object as EmberEncounterResource
	if encounter == null:
		return
	var panel := EncounterPanel.new() as EmberEncounterInspectorPanel
	panel.setup(encounter, _editor_interface, _undo_redo)
	add_custom_control(panel)


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool,
) -> bool:
	# The visual list above owns these references atomically and keeps the enemy
	# AI choice valid when an action is removed. Raw string arrays would bypass it.
	return (
		(object is EmberCombatActionResource and name == "effect_steps")
		or (object is EmberCombatUnitResource and name in ["action_ids", "ai_profile_id", "loot_table"])
		or (object is EmberCombatLootTableResource and name == "entries")
	)


func _is_combat_effect(object: Object) -> bool:
	return (
		object is Resource
		and object.get_script() != null
		and str((object.get_script() as Script).resource_path) == "res://scripts/prototypes/ember_combat_effect_resource.gd"
	)


func _is_combat_status(object: Object) -> bool:
	return (
		object is Resource
		and object.get_script() != null
		and str((object.get_script() as Script).resource_path) == "res://scripts/prototypes/ember_combat_status_resource.gd"
	)
