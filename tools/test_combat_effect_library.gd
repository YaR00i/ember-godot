extends SceneTree
## Stage 3.5 gate: reusable effect Resources, cell-targeted Earth/Wind rules,
## runtime projection and the native content library share one combat owner.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain := preload("res://scripts/prototypes/ember_combat_terrain.gd")
const EffectCatalog := preload("res://scripts/prototypes/ember_combat_effect_catalog.gd")
const ActionCatalog := preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const EffectPanel := preload("res://addons/ember_import/ember_combat_effect_inspector_panel.gd")
const ActionPanel := preload("res://addons/ember_import/ember_combat_action_inspector_panel.gd")
const ContentWorkspace := preload("res://addons/ember_import/ember_combat_content_library_workspace.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_resources(errors)
	_test_earth_wall(errors)
	_test_earth_raise(errors)
	_test_wind_spread(errors)
	_test_editor(errors)
	if not errors.is_empty():
		printerr("FAIL combat effect library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat effect library")
	print("  shared effect Resources compose canonical combat actions")
	print("  Earth changes the same battle cells used by movement, LOS and AI")
	print("  Wind deterministically spreads authored unit statuses and cell tags")
	print("  native library edits effect → action → unit without a second schema")
	return 0


func _test_resources(errors: Array[String]) -> void:
	var expected_effects := PackedStringArray([
		"activate_forge_focus", "apply_burning", "apply_frozen", "apply_overheated",
		"apply_wet", "earth_raise_ground", "earth_stone_wall", "forge_leap_move",
		"ice_barrier_cell", "push_medium", "restore_major_hp", "wind_spread_elements",
	])
	if EffectCatalog.ids() != expected_effects:
		errors.append("effect catalog does not expose the twelve reusable fixtures")
	for effect in EffectCatalog.resources():
		var validation: Array = effect.call("validation_errors")
		if not validation.is_empty():
			errors.append("effect %s is invalid: %s" % [
			str(effect.get("effect_id")), " | ".join(validation),
		])
	for action_id in ["earth_raise", "earth_wall", "wind_spread"]:
		var action := ActionCatalog.resource(action_id)
		if action == null:
			errors.append("action %s is absent from the catalog" % action_id)
			continue
		var validation := action.validation_errors()
		if not validation.is_empty():
			errors.append("action %s is invalid: %s" % [action_id, " | ".join(validation)])
		if action.target_id() != "cell" or action.effect_id() != "effect_chain":
			errors.append("action %s lost cell/effect-chain targeting" % action_id)
	var source := ActionCatalog.resource("earth_wall")
	var path := "user://combat_effect_action_roundtrip.tres"
	if source == null or ResourceSaver.save(source, path) != OK:
		errors.append("composed action could not be saved")
	else:
		var reopened := ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_REPLACE
		) as EmberCombatActionResource
		if reopened == null or reopened.content_signature() != source.content_signature():
			errors.append("composed action changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_earth_wall(errors: Array[String]) -> void:
	var state := _test_state("mira", "earth_wall")
	var target := Vector2i(1, 1)
	if target not in Combat.valid_target_cells(state, "earth_wall"):
		errors.append("Earth wall does not expose an empty in-range cell")
		return
	var preview := Combat.preview(state, "earth_wall", "", Combat.INVALID_CELL, target)
	var patch: Dictionary = (preview.get("cellChanges", {}) as Dictionary).get(
		Terrain.cell_key(target), {}
	)
	if not bool(preview.get("ok", false)) or not bool(patch.get("blocked", false)):
		errors.append("Earth wall preview did not lock the canonical cell patch")
		return
	var committed := Combat.commit(state, preview)
	if not Grid.is_blocked(committed, target):
		errors.append("Earth wall commit did not affect shared movement terrain")
	if target in Grid.reachable_cells(committed, "mira"):
		errors.append("pathfinding ignored the new Earth wall")
	if Grid.is_blocked(state, target):
		errors.append("Earth wall preview mutated the source battle state")


func _test_earth_raise(errors: Array[String]) -> void:
	var state := _test_state("mira", "earth_raise")
	var target := Vector2i(1, 1)
	var before := Terrain.elevation(state, target)
	var preview := Combat.preview(state, "earth_raise", "", Combat.INVALID_CELL, target)
	var patch: Dictionary = (preview.get("cellChanges", {}) as Dictionary).get(
		Terrain.cell_key(target), {}
	)
	if not bool(preview.get("ok", false)) or int(patch.get("elevation", -1)) != before + 1:
		errors.append("Earth raise preview did not change canonical elevation")
		return
	var committed := Combat.commit(state, preview)
	if Terrain.elevation(committed, target) != before + 1:
		errors.append("Earth raise commit did not reach shared height/LOS terrain")
	if Terrain.elevation(state, target) != before:
		errors.append("Earth raise preview mutated the source state")


func _test_wind_spread(errors: Array[String]) -> void:
	var state := _test_state("mira", "wind_spread")
	var units: Dictionary = state.get("units", {})
	var source: Dictionary = units["wisp"]
	source["cell"] = Vector2i(2, 1)
	source["statuses"] = {"burning": 2}
	source["hp"] = maxi(1, int(source.get("hp", 1)))
	units["wisp"] = source
	var neighbor: Dictionary = units["raider"]
	neighbor["cell"] = Vector2i(3, 1)
	neighbor["statuses"] = {}
	neighbor["hp"] = maxi(1, int(neighbor.get("hp", 1)))
	units["raider"] = neighbor
	state["units"] = units
	var source_cell := Vector2i(2, 1)
	var cells: Dictionary = (state.get("grid", {}) as Dictionary).get("cells", {})
	var wet_cell: Dictionary = (cells[Terrain.cell_key(source_cell)] as Dictionary).duplicate(true)
	wet_cell["tags"] = ["wet"]
	cells[Terrain.cell_key(source_cell)] = wet_cell
	(state["grid"] as Dictionary)["cells"] = cells
	if source_cell not in Combat.valid_target_cells(state, "wind_spread"):
		errors.append("Wind spread does not recognize authored Wet/Burning source")
		return
	var preview := Combat.preview(
		state, "wind_spread", "", Combat.INVALID_CELL, source_cell
	)
	var raider_statuses: Dictionary = (preview.get("setStatuses", {}) as Dictionary).get(
		"raider", {}
	)
	var wet_neighbor: Dictionary = (preview.get("cellChanges", {}) as Dictionary).get(
		Terrain.cell_key(Vector2i(1, 1)), {}
	)
	if not bool(preview.get("ok", false)) or int(raider_statuses.get("burning", 0)) <= 0:
		errors.append("Wind did not spread Burning to an adjacent combatant")
	if "wet" not in wet_neighbor.get("tags", []):
		errors.append("Wind did not spread Wet to adjacent canonical terrain")
	var committed := Combat.commit(state, preview)
	if not Combat.unit_definition(committed, "raider").get("statuses", {}).has("burning"):
		errors.append("Wind status spread was not committed")
	if "wet" not in Grid.cell_definition(committed, Vector2i(1, 1)).get("tags", []):
		errors.append("Wind terrain spread was not committed")


func _test_editor(errors: Array[String]) -> void:
	var effect := EffectCatalog.resource("earth_stone_wall")
	var effect_panel := EffectPanel.new() as VBoxContainer
	effect_panel.call("setup", effect)
	if (
		effect_panel.find_child("CombatEffectSummary", true, false) == null
		or effect_panel.find_child("CombatEffectValidation", true, false) == null
	):
		errors.append("effect Inspector lost its explanation or validation")
	effect_panel.free()
	var action := ActionCatalog.resource("earth_wall")
	var undo := UndoRedo.new()
	var action_panel := ActionPanel.new() as EmberCombatActionInspectorPanel
	action_panel.setup(action, null, undo)
	if action_panel.find_child("CombatActionEffectEditor", true, false) == null:
		errors.append("action Inspector has no reusable effect editor")
	else:
		var original := action.effect_steps.duplicate()
		action_panel.call("_remove_effect", 0)
		if not action.effect_steps.is_empty():
			errors.append("effect removal did not change the action Resource")
		undo.undo()
		if action.effect_steps != original:
			errors.append("Undo did not restore the exact effect chain")
	action_panel.free()
	var workspace := ContentWorkspace.new() as VBoxContainer
	workspace.call("setup", null, undo)
	var content_list := workspace.find_child("CombatContentList", true, false) as Tree
	if (
		workspace.find_child("CombatContentKinds", true, false) == null
		or content_list == null
		or workspace.find_child("CombatContentCreate", true, false) == null
		or workspace.find_child("CombatContentOpenInspector", true, false) == null
		or workspace.find_child("CombatContentSave", true, false) == null
		or workspace.find_child("CombatContentDuplicate", true, false) == null
		or workspace.find_child("CombatContentDetailHeader", true, false) == null
		or workspace.find_child("CombatContentRelations", true, false) == null
	):
		errors.append("central combat library lost effects/actions/units navigation")
	elif (
		content_list.columns != 3
		or content_list.get_column_title(0) != "НАЗВАНИЕ"
		or content_list.get_column_title(1) != "ID"
		or content_list.get_column_title(2) != "СВЯЗИ"
	):
		errors.append("central combat catalog is not a readable name/ID/relations table")
	workspace.call("_open_related", "action", "earth_wall")
	if str(workspace.get("_selected_id")) != "earth_wall" or str(workspace.get("_kind")) != "action":
		errors.append("relation navigation did not open the linked canonical Resource")
	if workspace.get_combined_minimum_size().x > 1280.0:
		errors.append("combat content library no longer fits the accepted 1280px editor width")
	workspace.free()
	undo.clear_history(false)
	undo.free()


func _test_state(actor_id: String, action_id: String) -> Dictionary:
	var state := Combat.initial_state(31415)
	var cells := {}
	for y in 3:
		for x in 5:
			var cell := Vector2i(x, y)
			cells[Terrain.cell_key(cell)] = {
				"cell": cell,
				"terrain": 0,
				"elevation": 0,
				"blocked": false,
				"group": "",
				"tags": [],
			}
	state["grid"] = {
		"width": 5,
		"height": 3,
		"cells": cells,
		"focus": {"cell": Vector2i(4, 2), "effect": "", "bonus": 0},
	}
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[unit_id]
		unit["nextAt"] = 0.0 if unit_id == actor_id else 100.0
		unit["hp"] = int(unit.get("maxHp", 1)) if unit_id in [actor_id, "wisp", "raider"] else 0
		unit["cell"] = {
			actor_id: Vector2i(0, 1),
			"wisp": Vector2i(3, 0),
			"raider": Vector2i(4, 0),
		}.get(unit_id, Vector2i(4, 2))
		if unit_id == actor_id:
			var actions: Array = unit.get("actions", []).duplicate()
			if action_id not in actions:
				actions.append(action_id)
			unit["actions"] = actions
			unit["mp"] = int(unit.get("maxMp", 99))
		units[unit_id] = unit
	state["units"] = units
	return state
