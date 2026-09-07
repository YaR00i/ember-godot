extends SceneTree
## Pure smoke for the editor-only reverse index used by Quest Flow.

const UsageIndex = preload("res://addons/ember_import/ember_quest_usage_index.gd")


func _init() -> void:
	var quest := {
		"id": "quest_demo",
		"statusFlagId": "quest_demo_status",
		"titleRu": "Проверка связей",
		"objectives": [
			{"id": "find", "textRu": "Найти", "flagId": "quest_demo_find"},
			{"id": "return", "textRu": "Вернуться", "flagId": "quest_demo_return"},
		],
	}
	var actions: Array[Dictionary] = [{
		"id": "demo_action",
		"nameRu": "Сценарий предмета",
		"steps": [
			{"type": "set_flag", "flag": "quest_demo_status", "value": "active"},
			{"type": "set_flag", "flag": "unrelated", "value": true},
			{"type": "set_flag", "flag": "quest_demo_find", "value": true},
		],
	}]
	var dialogues: Array[Dictionary] = [{
		"id": "demo_dialogue",
		"nameRu": "Разговор",
		"steps": [
			{
				"id": "choice",
				"type": "choice",
				"options": [{
					"labelRu": "Отдать находку",
					"setFlags": {"quest_demo_return": true},
				}],
			},
			{
				"id": "finish",
				"type": "set_flag",
				"flag": "quest_demo_status",
				"value": "done",
			},
		],
	}]
	var entries := UsageIndex.entries_for_documents(quest, actions, dialogues)
	var errors: Array[String] = []
	if entries.size() != 4:
		errors.append("reverse index should include four matching writers and ignore unrelated flags")
	_assert_entry(errors, entries, "quest_start", "quest_root", "action", "demo_action")
	_assert_entry(errors, entries, "quest_complete", "quest_root", "dialogue", "demo_dialogue")
	_assert_entry(errors, entries, "objective_complete", "find", "action", "demo_action")
	_assert_entry(errors, entries, "objective_complete", "return", "dialogue", "demo_dialogue")
	for entry in entries:
		if str(entry.get("documentKind", "")) == "action" and str(entry.get("targetId", "")) == "find":
			if int(entry.get("writerIndex", -1)) != 2:
				errors.append("action usage lost the exact writer index needed for safe unbind")
	var scene_root := Node3D.new()
	scene_root.name = "FixtureScene"
	var prop := EmberVoxelProp.new()
	prop.name = "QuestProp"
	scene_root.add_child(prop)
	var interact := EmberInteract.new()
	interact.name = "Interact"
	interact.kind = "quest_marker"
	interact.quest_id = "quest_demo"
	interact.script_id = "demo_action"
	prop.add_child(interact)
	var scene_entries := UsageIndex.scene_entries(scene_root, quest, entries)
	if scene_entries.size() != 1:
		errors.append("open-scene backlink did not find the Interact launching a quest action")
	else:
		var backlink: Dictionary = scene_entries[0]
		if (
			str(backlink.get("ownerName", "")) != "QuestProp"
			or str(backlink.get("nodePath", "")) != "QuestProp/Interact"
			or (backlink.get("eventIds", []) as Array).size() != 2
		):
			errors.append("scene backlink lost authoring owner, NodePath, or matching event writers")
	scene_root.free()
	if not errors.is_empty():
		printerr("FAIL quest usage index")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS quest usage index")
	print("  action/dialogue flag writers project to quest and objective targets without serialization")
	quit(0)


func _assert_entry(
	errors: Array[String],
	entries: Array[Dictionary],
	operation: String,
	target_id: String,
	document_kind: String,
	document_id: String,
) -> void:
	for entry in entries:
		if (
			str(entry.get("operation", "")) == operation
			and str(entry.get("targetId", "")) == target_id
			and str(entry.get("documentKind", "")) == document_kind
			and str(entry.get("documentId", "")) == document_id
		):
			return
	errors.append("missing %s writer %s:%s -> %s" % [operation, document_kind, document_id, target_id])
