@tool
class_name EmberObjectInspectorActions
extends RefCounted
## The single mutation path for scene-owned EmberInteract nodes. Editor actions
## use EditorUndoRedoManager; headless tests exercise the same methods with UndoRedo.

const ActionScriptStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const ShopStore = preload("res://addons/ember_import/ember_shop_store.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const StoryAuthoring = preload("res://addons/ember_import/ember_story_authoring.gd")
const VoxelModelStore = preload("res://addons/ember_import/ember_voxel_model_store.gd")

signal scene_binding_changed
signal voxel_model_changed(model_id: String)

var _undo_redo: Object


func configure(undo_redo: Object) -> void:
	_undo_redo = undo_redo


func create_story_scene(root: Node3D, values: Dictionary) -> Dictionary:
	if _undo_redo == null:
		return {"ok": false, "error": "История редактора не подключена"}
	var built := StoryAuthoring.build(root, values)
	if not built.ok:
		return built
	var assembly: Node = built.node
	# Capture only authored nodes before ready() builds transient dialogue controls.
	var authored: Array[Node] = [assembly]
	authored.append_array(assembly.find_children("*", "Node", true, false))
	_create_action("Создать сценку «%s»" % str(values.get("title", "")), root)
	_add_do_method("_attach_story_scene", [root, assembly, authored])
	_add_do_reference(assembly)
	_add_undo_method("_detach_story_scene", [assembly])
	_commit_action()
	return built


func _attach_story_scene(root: Node, assembly: Node, authored: Array[Node]) -> void:
	root.add_child(assembly)
	for node in authored:
		node.owner = root
	scene_binding_changed.emit()


func _detach_story_scene(assembly: Node) -> void:
	if assembly.get_parent() != null:
		assembly.get_parent().remove_child(assembly)
	scene_binding_changed.emit()


func save(prop: EmberVoxelProp, values: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_target(root, prop) or _undo_redo == null:
		return false
	var normalized := EmberSceneAuthoring.normalized_interact_values(values)
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null:
		return _add(root, prop, normalized)
	return _edit(root, prop, interact, normalized)


func remove(prop: EmberVoxelProp, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_target(root, prop) or _undo_redo == null:
		return false
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null:
		return false
	_create_action("Удалить Ember Interact", root)
	_add_do_method("_detach", [prop, interact])
	_add_undo_method("_attach", [root, prop, interact])
	_add_undo_reference(interact)
	_commit_action()
	return true


func save_chain(
	prop: EmberVoxelProp,
	document: Dictionary,
	root_override: Node = null,
	quest_document: Dictionary = {},
) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_target(root, prop) or _undo_redo == null:
		return false
	var requested_quest_id := str(document.get("_editorQuestId", "")).strip_edges()
	var quest_to_write: Dictionary = {}
	var previous_quest_snapshot: Dictionary = {}
	if not quest_document.is_empty():
		quest_to_write = QuestStore.normalized_document(quest_document)
		if (
			not QuestStore.validation_errors(quest_to_write).is_empty()
			or str(quest_to_write.get("id", "")) != requested_quest_id
		):
			return false
		previous_quest_snapshot = QuestStore.snapshot(requested_quest_id)
	var persisted_document := document.duplicate(true)
	persisted_document.erase("_editorQuestId")
	var normalized_document := ActionScriptStore.normalized_document(persisted_document)
	if not ActionScriptStore.validation_errors(normalized_document).is_empty():
		return false
	var script_id := str(normalized_document.get("id", ""))
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null:
		var map := _map_owner(prop)
		var tile_size := map.imported_tile_size if map != null and map.imported_tile_size > 0.0 else 16.0
		interact = EmberSceneAuthoring.make_interact({
			"kind": "quest_marker" if not requested_quest_id.is_empty() else "trigger",
			"script_id": script_id,
			"quest_id": requested_quest_id,
			"note": "Godot action-chain trigger",
		}, tile_size)
		_create_action("Создать Ember триггер с цепочкой", root)
		_add_optional_quest_do(quest_to_write)
		_add_do_method("_write_chain", [normalized_document])
		_add_do_method("_attach", [root, prop, interact])
		_add_do_reference(interact)
		_add_undo_method("_detach", [prop, interact])
		_add_undo_method("_restore_chain", [previous_snapshot])
		_add_optional_quest_undo(previous_quest_snapshot)
		_add_undo_reference(interact)
		_commit_action()
		return true
	if interact.kind not in ["talk", "shop", "trigger", "custom", "quest_marker"]:
		return false
	var previous_values := EmberSceneAuthoring.interact_values(interact)
	var next_values := previous_values.duplicate(true)
	if interact.kind == "quest_marker":
		if not requested_quest_id.is_empty() and not QuestStore.document(requested_quest_id).is_empty():
			next_values["quest_id"] = requested_quest_id
		elif str(next_values.get("quest_id", "")).is_empty():
			var legacy_quest := QuestStore.document_for_status_flag(interact.script_id)
			if not legacy_quest.is_empty():
				next_values["quest_id"] = str(legacy_quest.get("id", ""))
	next_values["script_id"] = script_id
	next_values = EmberSceneAuthoring.normalized_interact_values(next_values)
	_create_action("Сохранить Ember цепочку", root)
	_add_optional_quest_do(quest_to_write)
	_add_do_method("_write_chain", [normalized_document])
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_do_property(interact, field, next_values.get(field, ""))
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_undo_property(interact, field, previous_values.get(field, ""))
	_add_undo_method("_restore_chain", [previous_snapshot])
	_add_optional_quest_undo(previous_quest_snapshot)
	_add_do_method("_refresh", [prop])
	_add_undo_method("_refresh", [prop])
	_commit_action()
	return true


func bind_quest_event(
	target: Node,
	event_token: String,
	root_override: Node = null,
	quest_document: Dictionary = {},
) -> bool:
	## Guided Quest Flow binding. The editor-only event token is compiled into
	## the existing set_flag runtime action, then saved through save_chain() or
	## save_standalone_chain() so scene fields + Resource share one Undo action.
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not is_instance_valid(target):
		return false
	if EmberObjectInspectorModel.quest_conversation_target(target) != null:
		return false
	var quest_id := QuestStore.quest_id_for_event(event_token)
	var event_step := (
		QuestStore.action_for_event_in_document(event_token, quest_document)
		if not quest_document.is_empty()
		else QuestStore.action_for_event(event_token)
	)
	if event_step.is_empty() or quest_id.is_empty():
		return false
	if (
		not quest_document.is_empty()
		and not QuestStore.validation_errors(quest_document).is_empty()
	):
		return false
	var prop := target as EmberVoxelProp
	var interact := target as EmberInteract
	if prop == null and interact != null:
		prop = EmberObjectInspectorModel.voxel_owner(interact)
	if prop != null:
		if not _valid_target(root, prop):
			return false
		interact = prop.get_node_or_null("Interact") as EmberInteract
	elif not _valid_standalone(root, interact):
		return false
	var existing_id := interact.resolved_action_script_id().strip_edges() if interact != null else ""
	var document := ActionScriptStore.document(existing_id)
	if document.is_empty():
		var source_id := _quest_binding_source_id(prop if prop != null else interact)
		var script_id := _available_action_id(ActionScriptStore.suggested_id(source_id))
		document = {
			"id": script_id,
			"nameRu": "События задания · %s" % _quest_binding_label(prop if prop != null else interact),
			"steps": [],
		}
	else:
		document = ActionScriptStore.normalized_document(document)
	var steps: Array = document.get("steps", []).duplicate(true)
	if not _contains_action_step(steps, event_step):
		var insert_at := steps.size()
		if not steps.is_empty() and str((steps[-1] as Dictionary).get("type", "")) == "change_map":
			insert_at -= 1
		steps.insert(insert_at, event_step.duplicate(true))
	document["steps"] = steps
	document["_editorQuestId"] = quest_id
	return (
		save_chain(prop, document, root, quest_document)
		if prop != null
		else save_standalone_chain(interact, document, root, quest_document)
	)


func bind_quest_conversation(
	target: Node, event_token: String, dialogue_id: String,
	root_override: Node = null, quest_document: Dictionary = {},
	created_npc: Node3D = null, created_position: Vector3 = Vector3.ZERO,
	handover_costs: Dictionary = {},
	choice_outcome: Dictionary = {},
	conversation_options: Dictionary = {},
) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not is_instance_valid(target):
		return false
	var interact := EmberObjectInspectorModel.quest_conversation_target(target)
	var creating := created_npc != null and created_npc == target and created_npc.get_parent() == null
	if interact == null or (not creating and not root.is_ancestor_of(interact)):
		return false
	var quest_id := QuestStore.quest_id_for_event(event_token)
	var quest := quest_document if not quest_document.is_empty() else QuestStore.document(quest_id)
	if not QuestStore.validation_errors(quest).is_empty() or str(quest.get("id", "")) != quest_id:
		return false
	if not interact.quest_id.is_empty() and interact.quest_id != quest_id:
		return false
	var objective_id := ""
	var objective_text := ""
	for objective in quest.get("objectives", []):
		if QuestStore.event_token(quest_id, "objective", str(objective.id)) == event_token:
			if str(objective.get("progressMode", "flag")) not in ["flag", "handover"]:
				return false
			objective_id = str(objective.id)
			objective_text = str(objective.get("textRu", objective_id))
	var inline_reply := conversation_options.has("text")
	var after_completion := bool(conversation_options.get("after_completion", false))
	if objective_id.is_empty() or (not inline_reply and not DialogueStore.exists(dialogue_id)):
		return false
	var private_dialogue: Dictionary = {}
	var previous_dialogue: Dictionary = {}
	if inline_reply:
		var text := str(conversation_options.text).strip_edges()
		if text.is_empty() or not choice_outcome.is_empty():
			return false
		var base := DialogueStore.suggested_id("%s_%s_%s_line" % [quest_id, "complete" if after_completion else objective_id, _quest_binding_source_id(target)])
		var source := DialogueStore.document(dialogue_id)
		# Reapplying an unchanged generated line does not create extra Resources.
		if not dialogue_id.begins_with(base) or DialogueStore.GraphModel.short_reply_text(source) != text:
			var copy_id := base
			var serial := 2
			while DialogueStore.exists(copy_id):
				copy_id = "%s_%d" % [base, serial]
				serial += 1
			var title := "После задания · %s" % str(interact.get("display_name")) if after_completion else "Реплика · %s · %s" % [quest.get("titleRu", quest_id), objective_text]
			private_dialogue = DialogueStore.GraphModel.short_reply_document(copy_id, title, text)
			if not DialogueStore.graph_validation_errors(private_dialogue).is_empty():
				return false
			previous_dialogue = DialogueStore.snapshot(copy_id)
			dialogue_id = copy_id
	var event_step := QuestStore.action_for_event_in_document(event_token, quest)
	var steps := [{"type": "talk", "dialogueId": dialogue_id}, event_step]
	var goal_handover := str(event_step.get("type", "")) == "handover_quest_items"
	var reminder := bool(conversation_options.get("reminder", false))
	var rewards: Dictionary = conversation_options.get("rewards", {})
	if (reminder or after_completion) and (not rewards.is_empty() or not handover_costs.is_empty() or not choice_outcome.is_empty()):
		return false
	if reminder or after_completion:
		var quest_flags := [str(quest.get("statusFlagId", ""))]
		for objective in quest.get("objectives", []):
			quest_flags.append(str(objective.get("flagId", "")))
		# A reminder must not accidentally complete the goal from inside Dialogue.
		var passive_dialogue := private_dialogue if not private_dialogue.is_empty() else DialogueStore.document(dialogue_id)
		for step in passive_dialogue.get("steps", []):
			if str(step.get("type", "")) == "grant_cinders":
				return false
			if str(step.get("type", "")) == "set_flag" and str(step.get("flag", step.get("flagId", ""))) in quest_flags:
				return false
			for option in step.get("options", []):
				for flag in option.get("setFlags", {}):
					if str(flag) in quest_flags:
						return false
		steps = [{"type": "talk", "dialogueId": dialogue_id}]
	if not choice_outcome.is_empty():
		if goal_handover or not handover_costs.is_empty() or not rewards.is_empty():
			return false
		var source := DialogueStore.document(dialogue_id)
		private_dialogue = DialogueStore.GraphModel.with_quest_choice_outcome(source, choice_outcome, str(event_step.get("flag", "")))
		if private_dialogue.is_empty() or not DialogueStore.GraphModel.validation_errors(private_dialogue).is_empty():
			return false
		if private_dialogue == source:
			private_dialogue = {}
		else:
			var base := DialogueStore.suggested_id("%s_%s_reply" % [_quest_binding_source_id(target), objective_id])
			var copy_id := base
			var serial := 2
			while DialogueStore.exists(copy_id):
				copy_id = "%s_%d" % [base, serial]
				serial += 1
			private_dialogue["id"] = copy_id
			private_dialogue["nameRu"] = "Ответ · %s" % str(interact.get("display_name"))
			previous_dialogue = DialogueStore.snapshot(copy_id)
		steps = [{"type": "talk", "dialogueId": dialogue_id}]
		if not private_dialogue.is_empty():
			steps[0]["dialogueId"] = str(private_dialogue.id)
	if goal_handover and not reminder and not after_completion:
		event_step["rewards"] = rewards.duplicate()
	elif not handover_costs.is_empty() or not rewards.is_empty():
		steps.insert(1, {"type": "exchange_items", "costs": handover_costs.duplicate(), "rewards": rewards.duplicate()})
	var old_routes: Dictionary = interact.get("objective_scripts").duplicate(true)
	var existing := ActionScriptStore.document(str(interact.get("completed_script_id")) if after_completion else str(old_routes.get(objective_id, "")))
	# Reuse an identical route; changed conversations get a private chain so other
	# scene consumers and authored exchange/reward actions are never overwritten.
	var script_id := str(existing.get("id", "")) if existing.get("steps", []) == steps else ""
	if script_id.is_empty():
		script_id = _available_action_id(ActionScriptStore.suggested_id(
			"%s_%s" % [_quest_binding_source_id(target), objective_id]
		))
	var document := ActionScriptStore.normalized_document({
		"id": script_id, "nameRu": "Разговор · %s" % _quest_binding_label(target), "steps": steps,
	})
	var pending_dialogues: Array[String] = []
	if not private_dialogue.is_empty():
		pending_dialogues.append(str(private_dialogue.id))
	if not ActionScriptStore.validation_errors(document, pending_dialogues, quest).is_empty():
		return false
	var next_routes := old_routes.duplicate(true)
	next_routes[objective_id] = script_id
	var previous_chain := ActionScriptStore.snapshot(script_id)
	var previous_quest := QuestStore.snapshot(quest_id)
	_create_action("Создать собеседника цели" if creating else "Назначить разговор цели задания", root)
	if creating:
		_add_do_method("_attach_quest_npc", [root, created_npc, created_position])
		_add_do_reference(created_npc)
	_add_do_method("_write_quest", [QuestStore.normalized_document(quest)])
	if not private_dialogue.is_empty():
		_add_do_method("_write_dialogue_graph", [private_dialogue])
	_add_do_method("_write_chain", [document])
	_add_do_property(interact, "quest_id", quest_id)
	if after_completion:
		_add_do_property(interact, "completed_script_id", script_id)
		_add_undo_property(interact, "completed_script_id", interact.get("completed_script_id"))
	else:
		_add_do_property(interact, "objective_scripts", next_routes)
		_add_undo_property(interact, "objective_scripts", old_routes)
	_add_undo_property(interact, "quest_id", interact.quest_id)
	_add_undo_method("_restore_chain", [previous_chain])
	if not previous_dialogue.is_empty():
		_add_undo_method("_restore_dialogue", [previous_dialogue])
	_add_undo_method("_restore_quest", [previous_quest])
	_add_do_method("_refresh_quest_interact", [interact])
	_add_undo_method("_refresh_quest_interact", [interact])
	if creating:
		_add_undo_method("_detach_quest_npc", [created_npc])
	_commit_action()
	return true


func create_quest_conversation(
	root: Node, world_position: Vector3, display_name: String,
	event_token: String, dialogue_id: String, quest_document: Dictionary,
	handover_costs: Dictionary = {},
	choice_outcome: Dictionary = {},
	conversation_options: Dictionary = {},
) -> Node3D:
	if root == null or _undo_redo == null or display_name.strip_edges().is_empty():
		return null
	var packed := load("res://prefabs/items/shore_keeper.tscn") as PackedScene
	if packed == null:
		return null
	# A local copy of the existing placeholder. No fields on the original keeper
	# or his accepted mission are changed; new routes belong to this scene node.
	var npc := packed.instantiate() as Node3D
	var giver := EmberObjectInspectorModel.quest_conversation_target(npc)
	if giver == null:
		npc.free()
		return null
	var serial := 1
	while root.has_node("QuestNPC_%d" % serial):
		serial += 1
	npc.name = "QuestNPC_%d" % serial
	npc.scene_file_path = ""
	giver.quest_id = ""
	giver.script_id = ""
	giver.set("objective_scripts", {})
	giver.set("completed_script_id", "")
	giver.set("display_name", display_name.strip_edges())
	var map := root as EmberMapLoader
	if map == null:
		map = root.get_node_or_null("Map") as EmberMapLoader
	if map == null:
		var ancestor := root.get_parent()
		while ancestor != null and map == null:
			map = ancestor as EmberMapLoader
			ancestor = ancestor.get_parent()
	if "model_preset" in giver:
		var model := map.default_npc_model if map != null else null
		if model == null:
			model = EmberMapLoader.WorldPresets.default_npc_model
		giver.set("model_preset", model)
	if not bind_quest_conversation(npc, event_token, dialogue_id, root, quest_document, npc, world_position, handover_costs, choice_outcome, conversation_options):
		npc.free()
		return null
	return npc


func _attach_quest_npc(root: Node, npc: Node3D, world_position: Vector3) -> void:
	root.add_child(npc)
	if npc.is_inside_tree():
		npc.global_position = world_position
	else:
		npc.position = (root as Node3D).transform.affine_inverse() * world_position if root is Node3D else world_position
	# Preserve nested visual PackedScene ownership; only authored nodes are local.
	for child in npc.get_children():
		_own_quest_npc_branch(root, child)
	npc.owner = root

func create_quest_reach_zone(root: Node, world_position: Vector3, objective_id: String, quest_document: Dictionary) -> EmberInteract:
	if root == null or _undo_redo == null or not QuestStore.validation_errors(quest_document).is_empty():
		return null
	var quest := QuestStore.normalized_document(quest_document)
	var objective: Dictionary = {}
	for candidate in quest.objectives:
		if str(candidate.id) == objective_id and str(candidate.get("progressMode", "flag")) == "flag":
			objective = candidate
	if objective.is_empty() or EmberObjectInspectorModel.quest_reach_zone(root, str(objective.flagId)) != null:
		return null
	if str(objective.textRu) in ["Выполнить цель", "Новая цель"]:
		objective.textRu = "Дойти до отмеченного места"
	var script_id := _available_action_id(ActionScriptStore.suggested_id("%s_%s_reach" % [quest.id, objective_id]))
	var steps: Array = []
	if (objective.get("requiresObjectiveIds", []) as Array).is_empty():
		steps.append(QuestStore.action_for_event_in_document(QuestStore.event_token(str(quest.id), "start"), quest))
	steps.append(QuestStore.action_for_event_in_document(QuestStore.event_token(str(quest.id), "objective", objective_id), quest))
	var chain := {"id": script_id, "nameRu": "Место · %s" % objective.textRu, "steps": steps}
	if not ActionScriptStore.validation_errors(chain).is_empty():
		return null
	var map := root as EmberMapLoader if root is EmberMapLoader else root.find_child("Map", true, false) as EmberMapLoader
	var tile_size := map.imported_tile_size if map != null and map.imported_tile_size > 0.0 else 16.0
	var parent := root.get_node_or_null(EmberSceneAuthoring.STANDALONE_TRIGGER_CONTAINER) as Node3D
	var created_parent := parent == null
	if parent == null:
		parent = Node3D.new()
		parent.name = EmberSceneAuthoring.STANDALONE_TRIGGER_CONTAINER
	var zone := EmberSceneAuthoring.make_standalone_trigger(tile_size)
	zone.name = EmberSceneAuthoring.next_standalone_trigger_name(root)
	zone.activation_mode = "enter"
	zone.script_id = script_id
	zone.condition_flag_id = str(objective.flagId)
	zone.condition_value = false
	zone.condition_expected = false
	zone.note = "Дойти до места · %s" % objective.textRu
	_create_action("Создать место цели квеста", root)
	_add_do_method("_write_quest", [quest])
	_add_do_method("_write_chain", [chain])
	_add_do_method("_attach_standalone", [root, parent, zone, world_position])
	if created_parent:
		_add_do_reference(parent)
	_add_do_reference(zone)
	_add_undo_method("_detach_standalone", [root, parent, zone, created_parent])
	_add_undo_method("_restore_chain", [ActionScriptStore.snapshot(script_id)])
	_add_undo_method("_restore_quest", [QuestStore.snapshot(str(quest.id))])
	_commit_action()
	return zone


func assign_mechanism_role(scene: Node3D, target: Node3D, kind: String, circuit: Node3D = null) -> Dictionary:
	var failure := {"ok": false, "error": "Выдели один объект открытой сцены.", "circuit": null, "id": ""}
	if _undo_redo == null or not is_instance_valid(scene) or not is_instance_valid(target) or target == scene or not scene.is_ancestor_of(target): return failure
	if kind not in ["lever", "lamp", "door", "plate"]: return failure
	var geometry := preload("res://scripts/ember_mechanism_role_geometry.gd")
	if kind in ["door", "plate"]:
		if target.owner == null:
			failure.error = "Выбери исходный сохраняемый объект сцены, а не автоматически построенную часть."; return failure
		var ancestor := target.get_parent()
		while ancestor != null and ancestor != scene:
			if ancestor is PhysicsBody3D or ancestor.has_meta("mechanism_role_id"):
				failure.error = "Выбери исходный объект целиком, вне чужого физического тела или служебной зоны."; return failure
			ancestor = ancestor.get_parent()
		var box: AABB = geometry.bounds(target)
		if box.size.x < 0.1 or box.size.y < 0.1 or box.size.z < 0.1:
			failure.error = "У объекта нет объёмной mesh-геометрии для расчёта зон."; return failure
		var bodies: Array[Node] = [target]; bodies.append_array(target.find_children("*", "PhysicsBody3D", true, false))
		for body in bodies:
			if body is RigidBody3D or body is CharacterBody3D or body is AnimatableBody3D:
				failure.error = "Выбери обычный неподвижный объект; подвижным телом уже управляет другая физика."; return failure
	if kind == "lamp" and not (target is MeshInstance3D or target is Light3D):
		failure.error = "Для лампы выдели MeshInstance3D или источник света."; return failure
	if target.has_method("toggle_lever"):
		failure.error = "Выбери сам предмет, а не корень механизма."; return failure
	if circuit != null and (not scene.is_ancestor_of(circuit) or circuit.binding_scene() != scene): return failure
	for other in scene.find_children("*", "Node3D", true, false):
		if not other.has_method("toggle_lever") or not other.has_method("snapshot"): continue
		for row in other.snapshot().nodes:
			if str(row.get("target", "")).is_empty(): continue
			if geometry.object_for(other.get_node_or_null(NodePath(str(row.target))) as Node3D) == target:
				if other != circuit:
					failure.error = "Объект уже назначен другому механизму. Выбери его в списке."; return failure
				failure.error = "У объекта уже есть роль. Изменить или снять её можно в свойствах компонента."; return failure
	var script := preload("res://scripts/ember_mechanism_circuit.gd")
	var created := circuit == null
	if created:
		circuit = script.new()
		var serial := 1
		while scene.has_node("Mechanism_%d" % serial): serial += 1
		circuit.name = "Mechanism_%d" % serial
		circuit.circuit_id = "circuit_" + Crypto.new().generate_random_bytes(8).hex_encode()
		# A new controller references the existing sibling; it never adopts the object.
	var path := "../" + str(scene.get_path_to(target)) if created else str(circuit.get_path_to(target))
	var id := "node_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var document: Dictionary = circuit.snapshot()
	var row := {"id": id, "kind": kind, "label": str(target.name), "target": path, "crate": "", "clearance": "", "position": Vector2(40 + document.nodes.size() * 310, 40), "offset": Vector3(0, 40, 0), "seconds": 0.6, "settle": 0.35}
	document.nodes.append(row)
	if kind in ["door", "plate"]:
		var parent := target.get_parent()
		while parent != null and parent != scene:
			if parent.has_method("toggle_lever") and parent != circuit:
				if created: circuit.free()
				failure.error = "Предмет находится внутри другого механизма."; return failure
			parent = parent.get_parent()
		if not created and not circuit.document_errors(circuit.snapshot()).is_empty():
			failure.error = "Сначала исправь ошибки существующей схемы."; return failure
		var helper: Node3D = geometry.build(target, kind, id)
		if kind == "plate": row.target = path + "/" + str(helper.name) + "/PlateZone"
		else:
			row.clearance = path + "/" + str(helper.name) + "/Clearance"
			row.offset = Vector3(0, geometry.bounds(target).size.y + 4, 0)
		document.nodes[document.nodes.size() - 1] = row
		var child: Node = script.make_component(row)
		child.authored_helper = helper; child.authored_parent = target
		var before: Array = circuit.components(); var after := before.duplicate(); after.append(child)
		_create_action("Назначить роль с автоматическими зонами", scene if created else circuit)
		_add_do_method("_assign_generated_role", [scene, circuit, created, after, document.links, str(circuit.circuit_id)])
		_add_do_reference(child); _add_do_reference(helper)
		if created: _add_do_reference(circuit)
		_add_undo_method("_unassign_generated_role", [circuit, created, before, circuit.links.duplicate(true), str(circuit.circuit_id)])
		_commit_action()
		return {"ok": true, "error": "", "circuit": circuit, "id": id}
	if created:
		# Structural/type/scope checks above happen before the first scene mutation.
		var parent := target.get_parent()
		while parent != null and parent != scene:
			if parent.has_method("toggle_lever"):
				circuit.free(); failure.error = "Предмет находится внутри другого набора механизма."; return failure
			parent = parent.get_parent()
		circuit.add_child(script.make_component(row))
		_create_action("Назначить роль и создать механизм", scene)
		_add_do_method("_attach_quest_placement", [scene, circuit, Vector3.ZERO])
		_add_do_reference(circuit)
		_add_undo_method("_detach_quest_npc", [circuit])
		_commit_action()
	else:
		var answer := apply_mechanism_document(circuit, document)
		if not answer.ok: failure.error = answer.error; return failure
	return {"ok": true, "error": "", "circuit": circuit, "id": id}

func _assign_generated_role(scene: Node3D, circuit: Node3D, created: bool, children: Array, links_value: Array, id: String) -> void:
	if created: _attach_quest_placement(scene, circuit, Vector3.ZERO)
	_replace_mechanism(circuit, circuit.get_script(), children, links_value, id, {})

func _unassign_generated_role(circuit: Node3D, created: bool, children: Array, links_value: Array, id: String) -> void:
	_replace_mechanism(circuit, circuit.get_script(), children, links_value, id, {})
	if created: _detach_quest_npc(circuit)

func apply_mechanism_document(circuit: Node3D, document: Dictionary) -> Dictionary:
	var errors: Array[String] = circuit.document_errors(document)
	if not errors.is_empty(): return {"ok": false, "error": errors[0]}
	var old_document: Dictionary = circuit.snapshot()
	var previous_logic := old_document.duplicate(true)
	var next_logic := document.duplicate(true)
	var old_positions := {}; var next_positions := {}
	var old_world := {}; var next_world := {}
	for row in previous_logic.nodes:
		old_positions[str(row.id)] = row.get("position", Vector2.ZERO)
		row.erase("position")
		if row.has("world_position"): old_world[str(row.id)] = row.world_position; row.erase("world_position")
	for row in next_logic.nodes:
		next_positions[str(row.id)] = row.get("position", Vector2.ZERO)
		row.erase("position")
		if row.has("world_position"): next_world[str(row.id)] = row.world_position; row.erase("world_position")
	if previous_logic == next_logic and not circuit.has_method("_legacy_document"):
		_create_action("Расположить карточки механизма", circuit)
		_add_do_method("_set_mechanism_positions", [circuit, next_positions, next_world])
		_add_undo_method("_set_mechanism_positions", [circuit, old_positions, old_world])
		_commit_action()
		return {"ok": true, "error": ""}
	var script := preload("res://scripts/ember_mechanism_circuit.gd")
	var before: Array[Node] = circuit.components()
	var after: Array[Node] = []
	for row in document.nodes: after.append(script.make_component(row))
	var legacy := {}
	if circuit.has_method("_legacy_document"):
		for key in ["crate_path", "plate_path", "gate_path", "clearance_path", "open_offset", "settle_seconds", "move_seconds"]: legacy[key] = circuit.get(key)
	var old_script := circuit.get_script()
	var old_links: Array = circuit.links.duplicate(true)
	var circuit_id := str(circuit.circuit_id)
	if circuit_id.is_empty(): circuit_id = "circuit_" + Crypto.new().generate_random_bytes(8).hex_encode()
	_create_action("Изменить схему механизма", circuit)
	_add_do_method("_replace_mechanism", [circuit, script, after, document.links.duplicate(true), circuit_id, {}])
	for child in after: _add_do_reference(child)
	_add_undo_method("_replace_mechanism", [circuit, old_script, before, old_links, str(circuit.circuit_id), legacy])
	for child in before: _undo_redo.add_undo_reference(child)
	for child in before:
		var helper: Node3D = preload("res://scripts/ember_mechanism_role_geometry.gd").helper_for(child.binding(child.target_path), str(child.component_id))
		if helper != null: _undo_redo.add_undo_reference(helper)
	_commit_action()
	return {"ok": true, "error": ""}

func _set_mechanism_positions(circuit: Node3D, positions: Dictionary, world_positions: Dictionary = {}) -> void:
	for child in circuit.components():
		child.set_meta("graph_position", positions.get(child.component_id, Vector2.ZERO))
		if world_positions.has(child.component_id): child.set_meta("mechanism_world_position", world_positions[child.component_id])
		elif child.has_meta("mechanism_world_position"): child.remove_meta("mechanism_world_position")
	_notify_scene_binding_changed()

func _replace_mechanism(circuit: Node3D, script: Script, children: Array, links_value: Array, id: String, legacy: Dictionary) -> void:
	var state: EmberExploreState = circuit.progress_state
	for previous in circuit.components():
		for next in children:
			if next.component_id == previous.component_id and next.kind == previous.kind and next.target_path == previous.target_path:
				next._disabled_shapes = previous._disabled_shapes.duplicate()
	if not Engine.is_editor_hint(): circuit.release_runtime()
	for previous in circuit.components():
		var helper: Node3D = preload("res://scripts/ember_mechanism_role_geometry.gd").helper_for(previous.binding(previous.target_path), str(previous.component_id))
		if helper == null: continue
		previous.authored_helper = helper; previous.authored_parent = helper.get_parent()
		var retained := false
		for next in children:
			if next.component_id == previous.component_id and next.kind == previous.kind and next.target_path == previous.target_path:
				next.authored_helper = helper; next.authored_parent = helper.get_parent(); retained = true
		if not retained: helper.get_parent().remove_child(helper)
	for child in circuit.components(): circuit.remove_child(child)
	if circuit.get_script() != script: circuit.set_script(script)
	circuit.progress_state = state
	circuit.circuit_id = id
	circuit.links.assign(links_value)
	for key in legacy: circuit.set(key, legacy[key])
	var owner := circuit.owner if circuit.owner != null else circuit
	for child in children:
		if is_instance_valid(child.authored_helper) and child.authored_helper.get_parent() == null and is_instance_valid(child.authored_parent):
			child.authored_parent.add_child(child.authored_helper)
			child.authored_helper.owner = owner
			for node in child.authored_helper.find_children("*", "Node", true, false): node.owner = owner
		circuit.add_child(child)
		child.owner = owner
	if not Engine.is_editor_hint(): circuit.rebuild()
	_notify_scene_binding_changed()

func create_pressure_gate(root: Node3D, at: Vector3, workshop := false) -> Node3D:
	if root == null or _undo_redo == null: return null
	var map := root as EmberMapLoader if root is EmberMapLoader else root.find_child("Map", true, false) as EmberMapLoader
	var builder := preload("res://addons/ember_import/ember_pressure_gate_builder.gd")
	var map_id := map.map_id if map != null else "landscape_compact"
	var kit := builder.build_workshop(map_id) if workshop else builder.build(map_id)
	var serial := 1
	while root.has_node("PressureGate_%d" % serial): serial += 1
	kit.name = "PressureGate_%d" % serial
	_create_action("Создать ящик, плиту и проход", root)
	_add_do_method("_attach_quest_placement", [root, kit, at])
	_add_do_reference(kit)
	_add_undo_method("_detach_quest_npc", [kit])
	_commit_action()
	return kit


func create_quest_object_placement(root: Node, crate_at: Vector3, zone_at: Vector3, objective_id: String, quest_document: Dictionary) -> Node3D:
	if root == null or _undo_redo == null or not QuestStore.validation_errors(quest_document).is_empty():
		return null
	var quest := QuestStore.normalized_document(quest_document)
	var quest_id := str(quest.id)
	if EmberObjectInspectorModel.quest_object_zone(root, quest_id, objective_id) != null:
		return null
	var found := false
	var first_goal := false
	for objective in quest.objectives:
		if str(objective.id) == objective_id and str(objective.get("progressMode", "flag")) == "flag":
			found = true
			first_goal = (objective.get("requiresObjectiveIds", []) as Array).is_empty()
			if str(objective.get("textRu", "")) in ["Выполнить цель", "Новая цель"]:
				objective["textRu"] = "Поставить ящик в отмеченную зону"
	if not found:
		return null
	var compound := Node3D.new()
	var serial := 1
	while root.has_node("QuestPlacement_%d" % serial):
		serial += 1
	compound.name = "QuestPlacement_%d" % serial
	var crate := load("res://scripts/ember_world_item_3d.gd").new() as RigidBody3D
	crate.name = "Crate"
	crate.set("pickup_id", "%s_%s_%s" % [quest_id, objective_id, Crypto.new().generate_random_bytes(6).hex_encode()])
	crate.set("item_id", "quest_crate")
	crate.set("carryable", true)
	crate.set("pushable", true)
	crate.set("return_radius", 320.0)
	crate.set("start_quest_id", quest_id if first_goal else "")
	var map := root as EmberMapLoader if root is EmberMapLoader else root.find_child("Map", true, false) as EmberMapLoader
	crate.set("map_id", map.map_id if map != null else "landscape_compact")
	var visual := (load("res://prefabs/items/quest_crate.tscn") as PackedScene).instantiate() as Node3D
	visual.name = "ItemVisual"
	visual.scale = Vector3.ONE * 16.0
	crate.add_child(visual)
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyShape"
	body_shape.shape = BoxShape3D.new()
	(body_shape.shape as BoxShape3D).size = Vector3(16, 16, 16)
	body_shape.position.y = 8.0
	crate.add_child(body_shape)
	compound.add_child(crate)
	var zone := load("res://scripts/ember_quest_object_zone.gd").new() as Area3D
	zone.name = "TargetZone"
	zone.set("quest_id", quest_id)
	zone.set("objective_id", objective_id)
	zone.set("target_pickup_id", crate.get("pickup_id"))
	zone.position = zone_at - crate_at
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40, 28, 40)
	shape.position.y = 14.0
	zone.add_child(shape)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.78, 0.24)
	for side in 4:
		var bar := MeshInstance3D.new()
		bar.name = "Edge%d" % side
		bar.mesh = BoxMesh.new()
		(bar.mesh as BoxMesh).size = Vector3(40, 0.2, 0.5) if side < 2 else Vector3(0.5, 0.2, 40)
		bar.position = Vector3(0, 0.2, -20 if side == 0 else 20) if side < 2 else Vector3(-20 if side == 2 else 20, 0.2, 0)
		bar.material_override = material
		zone.add_child(bar)
	compound.add_child(zone)
	var previous := QuestStore.snapshot(quest_id)
	_create_action("Создать ящик и зону цели", root)
	_add_do_method("_write_quest", [quest])
	_add_do_method("_attach_quest_placement", [root, compound, crate_at])
	_add_do_reference(compound)
	_add_undo_method("_detach_quest_npc", [compound])
	_add_undo_method("_restore_quest", [previous])
	_commit_action()
	return compound

func _attach_quest_placement(root: Node, compound: Node3D, position: Vector3) -> void:
	var authored: Array[Node] = [compound]
	for node in compound.find_children("*", "Node", true, false):
		var path := compound.get_path_to(node)
		if path.get_name_count() > 1 and path.get_name(0) in ["Crate", "Find"] and path.get_name(1) == "Pickup":
			continue
		if node.owner == null or node.owner == compound:
			authored.append(node)
	compound.transform = root.global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, position) if root is Node3D and root.is_inside_tree() else Transform3D(Basis.IDENTITY, position)
	root.add_child(compound)
	for node in authored:
		node.owner = root


func _own_quest_npc_branch(root: Node, node: Node) -> void:
	node.owner = root
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_own_quest_npc_branch(root, child)


func _detach_quest_npc(npc: Node3D) -> void:
	if npc.get_parent() != null:
		npc.get_parent().remove_child(npc)


func unbind_quest_event(
	target: Node,
	event_entry: Dictionary,
	root_override: Node = null,
) -> Dictionary:
	## Removes one projected quest writer from the selected scene object's
	## action chain. Shared chains use copy-on-write so other scene objects keep
	## their behavior. Dialogue writers are intentionally edited in Dialogue
	## Graph because changing one branch could affect many callers.
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not is_instance_valid(target):
		return _unbind_result(false, "Объект сцены больше недоступен.")
	if str(event_entry.get("documentKind", "")) != "action":
		return _unbind_result(
			false,
			"Событие записано внутри диалога. Откройте его фиолетовую ноду и измените ветку в Dialogue Graph.",
		)
	var conversation := EmberObjectInspectorModel.quest_conversation_target(target)
	if conversation != null:
		if not root.is_ancestor_of(conversation):
			return _unbind_result(false, "Собеседник не принадлежит открытой сцене.")
		var objective_id := str(event_entry.get("targetId", ""))
		var routes: Dictionary = conversation.get("objective_scripts").duplicate(true)
		if not routes.has(objective_id) or str(routes[objective_id]) != str(event_entry.get("documentId", "")):
			return _unbind_result(false, "Этот разговор больше не назначен цели.")
		var remaining := routes.duplicate(true)
		remaining.erase(objective_id)
		_create_action("Отвязать разговор цели", root)
		_add_do_property(conversation, "objective_scripts", remaining)
		_add_undo_property(conversation, "objective_scripts", routes)
		_add_do_method("_refresh_quest_interact", [conversation])
		_add_undo_method("_refresh_quest_interact", [conversation])
		_commit_action()
		return _unbind_result(true, "Разговор цели отвязан; сама цепочка сохранена.")
	var prop := target as EmberVoxelProp
	var interact := target as EmberInteract
	if prop == null and interact != null:
		prop = EmberObjectInspectorModel.voxel_owner(interact)
	if prop != null:
		if not _valid_target(root, prop):
			return _unbind_result(false, "Выбранный объект не принадлежит открытой сцене.")
		interact = prop.get_node_or_null("Interact") as EmberInteract
	elif not _valid_standalone(root, interact):
		return _unbind_result(false, "Выберите объект или самостоятельную зону открытой сцены.")
	if interact == null:
		return _unbind_result(false, "У выбранного объекта нет Ember Interact.")
	var script_id := interact.resolved_action_script_id().strip_edges()
	if script_id.is_empty() or script_id != str(event_entry.get("documentId", "")).strip_edges():
		return _unbind_result(false, "Выбранный объект больше не запускает эту цепочку.")
	var document := ActionScriptStore.document(script_id)
	if document.is_empty():
		return _unbind_result(false, "Цепочка %s не найдена." % script_id)
	document = ActionScriptStore.normalized_document(document)
	var steps: Array = document.get("steps", []).duplicate(true)
	var remove_index := _event_step_index(steps, event_entry)
	if remove_index < 0:
		return _unbind_result(false, "Шаг события уже отсутствует в цепочке %s." % script_id)
	steps.remove_at(remove_index)
	var previous_values := EmberSceneAuthoring.interact_values(interact)
	var next_values := previous_values.duplicate(true)
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	var reference_count := _action_scene_reference_count(root, script_id)
	var shared := reference_count > 1
	var next_document := document.duplicate(true)
	next_document["steps"] = steps
	var next_id := script_id
	var next_snapshot: Dictionary = {}
	if steps.is_empty():
		next_values["script_id"] = ""
	elif shared:
		next_id = _available_action_id(ActionScriptStore.suggested_id(
			_quest_binding_source_id(prop if prop != null else interact)
		))
		next_snapshot = ActionScriptStore.snapshot(next_id)
		next_document["id"] = next_id
		next_document["nameRu"] = "%s · %s" % [
			str(document.get("nameRu", script_id)),
			_quest_binding_label(prop if prop != null else interact),
		]
		next_values["script_id"] = next_id
	if not steps.is_empty() and not ActionScriptStore.validation_errors(next_document).is_empty():
		return _unbind_result(false, "После отвязки цепочка стала некорректной.")
	next_values = EmberSceneAuthoring.normalized_interact_values(next_values)
	_create_action("Отвязать событие задания", root)
	if steps.is_empty():
		if not shared:
			_add_do_method("_restore_chain", [{"id": script_id, "native": {}, "legacy": {}}])
	elif shared:
		_add_do_method("_write_chain", [next_document])
	else:
		_add_do_method("_write_chain", [next_document])
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_do_property(interact, field, next_values.get(field, ""))
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_undo_property(interact, field, previous_values.get(field, ""))
	if shared:
		if not steps.is_empty():
			_add_undo_method("_restore_chain", [next_snapshot])
	else:
		_add_undo_method("_restore_chain", [previous_snapshot])
	_add_do_method("_refresh_quest_interact", [interact])
	_add_undo_method("_refresh_quest_interact", [interact])
	_commit_action()
	var detail := "Событие отвязано от %s" % _quest_binding_label(prop if prop != null else interact)
	if shared and not steps.is_empty():
		detail += " · общая цепочка сохранена, создана %s" % next_id
	elif shared:
		detail += " · общая цепочка сохранена"
	return _unbind_result(true, detail)


func remove_unbound_quest_event(
	event_entry: Dictionary,
	root_override: Node = null,
) -> Dictionary:
	## Removes one orphaned quest writer directly from its canonical action
	## document. This is deliberately unavailable while the open scene still
	## references that document: an author must then select the object and use
	## unbind_quest_event(), which protects shared chains through copy-on-write.
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if _undo_redo == null:
		return _unbind_result(false, "История Undo/Redo редактора недоступна.")
	if str(event_entry.get("documentKind", "")) != "action":
		return _unbind_result(
			false,
			"Событие находится в диалоге. Откройте его ноду и удалите запись в Dialogue Graph.",
		)
	var script_id := str(event_entry.get("documentId", "")).strip_edges()
	if script_id.is_empty():
		return _unbind_result(false, "У события нет исходной цепочки.")
	if root != null and _action_scene_reference_count(root, script_id) > 0:
		return _unbind_result(
			false,
			"Цепочка %s всё ещё назначена объекту открытой сцены. Выберите объект и отвяжите событие." % script_id,
		)
	var document := ActionScriptStore.document(script_id)
	if document.is_empty():
		return _unbind_result(false, "Цепочка %s уже удалена." % script_id)
	document = ActionScriptStore.normalized_document(document)
	var steps: Array = document.get("steps", []).duplicate(true)
	var remove_index := _event_step_index(steps, event_entry)
	if remove_index < 0:
		return _unbind_result(false, "Событие уже отсутствует в цепочке %s." % script_id)
	steps.remove_at(remove_index)
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	var next_document := document.duplicate(true)
	next_document["steps"] = steps
	if not steps.is_empty() and not ActionScriptStore.validation_errors(next_document).is_empty():
		return _unbind_result(false, "После удаления цепочка стала некорректной.")
	_create_action("Удалить лишнее событие задания", root if root != null else self)
	if steps.is_empty():
		_add_do_method("_restore_chain", [{"id": script_id, "native": {}, "legacy": {}}])
	else:
		_add_do_method("_write_chain", [next_document])
	_add_do_method("_notify_scene_binding_changed", [])
	_add_undo_method("_restore_chain", [previous_snapshot])
	_add_undo_method("_notify_scene_binding_changed", [])
	_commit_action()
	return _unbind_result(
		true,
		(
			"Лишняя цепочка %s удалена" % script_id
			if steps.is_empty()
			else "Событие удалено из цепочки %s" % script_id
		),
	)


func remove_chain(prop: EmberVoxelProp, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_target(root, prop) or _undo_redo == null:
		return false
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null:
		return false
	var script_id := interact.resolved_action_script_id().strip_edges()
	if interact.kind == "quest_marker" and interact.quest_id.is_empty():
		# Legacy quest markers store the status flag in script_id. It is not an
		# action-chain owner and must never be deleted from this button.
		return false
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	if ActionScriptStore.document(script_id).is_empty():
		return false
	_create_action("Удалить Ember цепочку", root)
	_add_do_property(interact, "script_id", "")
	_add_do_method("_restore_chain", [{"id": script_id, "native": {}, "legacy": {}}])
	_add_do_method("_refresh", [prop])
	_add_undo_method("_restore_chain", [previous_snapshot])
	_add_undo_property(interact, "script_id", script_id)
	_add_undo_method("_refresh", [prop])
	_commit_action()
	return true


func save_dialogue(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null:
		return false
	if not DialogueStore.validation_errors(document).is_empty():
		return false
	var dialogue_id := str(document.get("id", ""))
	var previous_snapshot := DialogueStore.snapshot(dialogue_id)
	_create_action("Сохранить Ember диалог", root)
	_add_do_method("_write_dialogue", [document.duplicate(true)])
	_add_undo_method("_restore_dialogue", [previous_snapshot])
	_commit_action()
	return true


func save_quest_document(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not QuestStore.validation_errors(document).is_empty():
		return false
	var normalized := QuestStore.normalized_document(document)
	var quest_id := str(normalized.get("id", ""))
	var previous_snapshot := QuestStore.snapshot(quest_id)
	_create_action("Сохранить Ember задание", root)
	_add_do_method("_write_quest", [normalized])
	_add_undo_method("_restore_quest", [previous_snapshot])
	_commit_action()
	return true


func save_dialogue_graph(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null:
		return false
	if not DialogueStore.graph_validation_errors(document).is_empty():
		return false
	var dialogue_id := str(document.get("id", ""))
	var previous_snapshot := DialogueStore.snapshot(dialogue_id)
	_create_action("Сохранить Ember dialogue graph", root)
	_add_do_method("_write_dialogue_graph", [document.duplicate(true)])
	_add_undo_method("_restore_dialogue", [previous_snapshot])
	_commit_action()
	return true


func save_action_script(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null:
		return false
	var persisted_document := document.duplicate(true)
	persisted_document.erase("_editorQuestId")
	var normalized_document := ActionScriptStore.normalized_document(persisted_document)
	if not ActionScriptStore.validation_errors(normalized_document).is_empty():
		return false
	var script_id := str(normalized_document.get("id", ""))
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	_create_action("Сохранить Ember цепочку", root)
	_add_do_method("_write_chain", [normalized_document])
	_add_undo_method("_restore_chain", [previous_snapshot])
	_commit_action()
	return true


func save_shop(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not ShopStore.validation_errors(document).is_empty():
		return false
	var shop_id := str(document.get("id", ""))
	var previous_snapshot := ShopStore.snapshot(shop_id)
	_create_action("Сохранить Ember магазин", root)
	_add_do_method("_write_shop", [document.duplicate(true)])
	_add_undo_method("_restore_shop", [previous_snapshot])
	_commit_action()
	return true


func save_item(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not ItemStore.validation_errors(document).is_empty():
		return false
	var item_id := str(document.get("id", ""))
	var previous_snapshot := ItemStore.snapshot(item_id)
	_create_action("Сохранить Ember предмет", root)
	_add_do_method("_write_item", [document.duplicate(true)])
	_add_undo_method("_restore_item", [previous_snapshot])
	_commit_action()
	return true


func migrate_voxel_model(model_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not VoxelModelStore.can_import_legacy(model_id):
		return false
	var previous_snapshot := VoxelModelStore.snapshot(model_id)
	_create_action("Перенести Ember voxel-модель в Godot Resource", root)
	_add_do_method("_migrate_voxel_model", [model_id])
	_add_undo_method("_restore_voxel_model", [previous_snapshot])
	_commit_action()
	return true


func migrate_voxel_models(model_ids: Array[String], root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or model_ids.is_empty():
		return false
	var snapshots: Array[Dictionary] = []
	for model_id in model_ids:
		if not VoxelModelStore.can_import_legacy(model_id):
			return false
		snapshots.append(VoxelModelStore.snapshot(model_id))
	_create_action("Перенести %d Ember voxel-моделей в Godot Resources" % model_ids.size(), root)
	_add_do_method("_migrate_voxel_models", [model_ids.duplicate()])
	_add_undo_method("_restore_voxel_models", [snapshots])
	_commit_action()
	return true


func save_quest_for_interact(
	interact: EmberInteract,
	document: Dictionary,
	root_override: Node = null,
) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if (
		root == null
		or _undo_redo == null
		or not is_instance_valid(interact)
		or not root.is_ancestor_of(interact)
		or interact.kind != "quest_marker"
		or not QuestStore.validation_errors(document).is_empty()
	):
		return false
	var normalized := QuestStore.normalized_document(document)
	var quest_id := str(normalized.get("id", ""))
	var previous_snapshot := QuestStore.snapshot(quest_id)
	var previous_quest_id := interact.quest_id
	var previous_script_id := interact.script_id
	var next_script_id := previous_script_id
	if not QuestStore.document_for_progress_flag(previous_script_id).is_empty():
		next_script_id = ""
	_create_action("Сохранить Ember задание", root)
	_add_do_method("_write_quest", [normalized])
	_add_do_property(interact, "quest_id", quest_id)
	_add_do_property(interact, "script_id", next_script_id)
	_add_do_method("_refresh_quest_interact", [interact])
	_add_undo_method("_restore_quest", [previous_snapshot])
	_add_undo_property(interact, "quest_id", previous_quest_id)
	_add_undo_property(interact, "script_id", previous_script_id)
	_add_undo_method("_refresh_quest_interact", [interact])
	_commit_action()
	return true


func create_standalone_trigger(root: Node, world_position: Vector3) -> EmberInteract:
	if root == null or _undo_redo == null:
		return null
	var map := root.find_child("Map", true, false) as EmberMapLoader
	var tile_size := map.imported_tile_size if map != null and map.imported_tile_size > 0.0 else 16.0
	var parent := root.get_node_or_null(EmberSceneAuthoring.STANDALONE_TRIGGER_CONTAINER) as Node3D
	var created_parent := parent == null
	if parent == null:
		parent = Node3D.new()
		parent.name = EmberSceneAuthoring.STANDALONE_TRIGGER_CONTAINER
	var interact := EmberSceneAuthoring.make_standalone_trigger(tile_size)
	interact.name = EmberSceneAuthoring.next_standalone_trigger_name(root)
	_create_action("Создать самостоятельную Ember зону", root)
	_add_do_method("_attach_standalone", [root, parent, interact, world_position])
	_add_do_reference(parent)
	_add_do_reference(interact)
	_add_undo_method("_detach_standalone", [root, parent, interact, created_parent])
	_add_undo_reference(parent)
	_add_undo_reference(interact)
	_commit_action()
	return interact


func save_standalone(interact: EmberInteract, values: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_standalone(root, interact) or _undo_redo == null:
		return false
	var normalized := EmberSceneAuthoring.normalized_interact_values(values)
	var previous := EmberSceneAuthoring.interact_values(interact)
	if previous == normalized:
		_refresh_standalone(interact)
		return true
	_create_action("Изменить самостоятельный Ember Interact", root)
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_do_property(interact, field, normalized.get(field, ""))
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_undo_property(interact, field, previous.get(field, ""))
	_add_do_method("_refresh_standalone", [interact])
	_add_undo_method("_refresh_standalone", [interact])
	_commit_action()
	return true


func save_standalone_chain(
	interact: EmberInteract,
	document: Dictionary,
	root_override: Node = null,
	quest_document: Dictionary = {},
) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_standalone(root, interact) or _undo_redo == null:
		return false
	var requested_quest_id := str(document.get("_editorQuestId", "")).strip_edges()
	var quest_to_write: Dictionary = {}
	var previous_quest_snapshot: Dictionary = {}
	if not quest_document.is_empty():
		quest_to_write = QuestStore.normalized_document(quest_document)
		if (
			not QuestStore.validation_errors(quest_to_write).is_empty()
			or str(quest_to_write.get("id", "")) != requested_quest_id
		):
			return false
		previous_quest_snapshot = QuestStore.snapshot(requested_quest_id)
	var persisted_document := document.duplicate(true)
	persisted_document.erase("_editorQuestId")
	var normalized_document := ActionScriptStore.normalized_document(persisted_document)
	if not ActionScriptStore.validation_errors(normalized_document).is_empty():
		return false
	var script_id := str(normalized_document.get("id", ""))
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	var previous_values := EmberSceneAuthoring.interact_values(interact)
	var next_values := previous_values.duplicate(true)
	if interact.kind == "quest_marker" and not requested_quest_id.is_empty():
		next_values["quest_id"] = requested_quest_id
	next_values["script_id"] = script_id
	next_values = EmberSceneAuthoring.normalized_interact_values(next_values)
	_create_action("Сохранить цепочку самостоятельной зоны", root)
	_add_optional_quest_do(quest_to_write)
	_add_do_method("_write_chain", [normalized_document])
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_do_property(interact, field, next_values.get(field, ""))
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_undo_property(interact, field, previous_values.get(field, ""))
	_add_undo_method("_restore_chain", [previous_snapshot])
	_add_optional_quest_undo(previous_quest_snapshot)
	_add_do_method("_refresh_standalone", [interact])
	_add_undo_method("_refresh_standalone", [interact])
	_commit_action()
	return true


func remove_standalone_chain(interact: EmberInteract, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_standalone(root, interact) or _undo_redo == null:
		return false
	var script_id := interact.script_id.strip_edges()
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	if ActionScriptStore.document(script_id).is_empty():
		return false
	_create_action("Удалить цепочку самостоятельной зоны", root)
	_add_do_property(interact, "script_id", "")
	_add_do_method("_restore_chain", [{"id": script_id, "native": {}, "legacy": {}}])
	_add_do_method("_refresh_standalone", [interact])
	_add_undo_method("_restore_chain", [previous_snapshot])
	_add_undo_property(interact, "script_id", script_id)
	_add_undo_method("_refresh_standalone", [interact])
	_commit_action()
	return true


func save_standalone_bounds(
	interact: EmberInteract,
	size: Vector3,
	root_override: Node = null,
) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_standalone(root, interact) or _undo_redo == null:
		return false
	var shape_node := interact.get_node_or_null("Shape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		return false
	var next := Vector3(maxf(1.0, size.x), maxf(1.0, size.y), maxf(1.0, size.z))
	if box.size.is_equal_approx(next):
		return true
	_create_action("Изменить размер Ember зоны", root)
	_add_do_property(box, "size", next)
	_add_undo_property(box, "size", box.size)
	_add_do_method("_refresh_standalone", [interact])
	_add_undo_method("_refresh_standalone", [interact])
	_commit_action()
	return true


func remove_standalone(interact: EmberInteract, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if not _valid_standalone(root, interact) or _undo_redo == null:
		return false
	var parent := interact.get_parent()
	var local_transform := interact.transform
	_create_action("Удалить самостоятельную Ember зону", root)
	_add_do_method("_detach_standalone", [root, parent, interact, false])
	_add_undo_method("_reattach_standalone", [root, parent, interact, local_transform])
	_add_undo_reference(interact)
	_commit_action()
	return true


func _add(root: Node, prop: EmberVoxelProp, values: Dictionary) -> bool:
	var map := _map_owner(prop)
	var tile_size := map.imported_tile_size if map != null and map.imported_tile_size > 0.0 else 16.0
	var interact := EmberSceneAuthoring.make_interact(values, tile_size)
	_create_action("Добавить Ember Interact", root)
	_add_do_method("_attach", [root, prop, interact])
	_add_do_reference(interact)
	_add_undo_method("_detach", [prop, interact])
	_commit_action()
	return true


func _edit(root: Node, prop: EmberVoxelProp, interact: EmberInteract, values: Dictionary) -> bool:
	var previous := EmberSceneAuthoring.interact_values(interact)
	if previous == values:
		_refresh(prop)
		return true
	_create_action("Изменить Ember Interact", root)
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_do_property(interact, field, values.get(field, ""))
	for field in EmberSceneAuthoring.INTERACT_FIELDS:
		_add_undo_property(interact, field, previous.get(field, ""))
	_add_do_method("_refresh", [prop])
	_add_undo_method("_refresh", [prop])
	_commit_action()
	return true


func _attach(root: Node, prop: EmberVoxelProp, interact: EmberInteract) -> void:
	EmberSceneAuthoring.attach_interact(root, prop, interact)
	_refresh(prop)


func _detach(prop: EmberVoxelProp, interact: EmberInteract) -> void:
	EmberSceneAuthoring.detach_interact(prop, interact)
	_refresh(prop)


func _attach_standalone(root: Node, parent: Node3D, interact: EmberInteract, world_position: Vector3) -> void:
	if parent.get_parent() != root:
		root.add_child(parent)
	parent.owner = root
	if interact.get_parent() != parent:
		parent.add_child(interact)
	# Editor scenes are normally inside the SceneTree, but the same authoring
	# contract is exercised on detached GEN_EDIT_STATE instances in tests.
	# AuthoredTriggers itself deliberately has an identity transform.
	if parent.is_inside_tree():
		interact.global_position = world_position
	else:
		interact.position = world_position
	_own_subtree(root, interact)
	_refresh_standalone(interact)


func _reattach_standalone(root: Node, parent: Node, interact: EmberInteract, local_transform: Transform3D) -> void:
	if parent.get_parent() != root:
		root.add_child(parent)
	parent.owner = root
	if interact.get_parent() != parent:
		parent.add_child(interact)
	interact.transform = local_transform
	_own_subtree(root, interact)
	_refresh_standalone(interact)


func _detach_standalone(root: Node, parent: Node, interact: EmberInteract, remove_empty_parent: bool) -> void:
	if interact.get_parent() == parent:
		_own_subtree(null, interact)
		parent.remove_child(interact)
	if remove_empty_parent and parent.get_parent() == root and parent.get_child_count() == 0:
		parent.owner = null
		root.remove_child(parent)


func _write_chain(document: Dictionary) -> void:
	var error := ActionScriptStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: action-chain write failed (%s)." % error)
		return
	_refresh_filesystem()


func _restore_chain(previous_snapshot: Dictionary) -> void:
	var error := ActionScriptStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: action-chain undo failed (%s)." % error)
		return
	_refresh_filesystem()


func _write_shop(document: Dictionary) -> void:
	var error := ShopStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: shop write failed (%s)." % error)
		return
	_refresh_filesystem()


func _restore_shop(previous_snapshot: Dictionary) -> void:
	var error := ShopStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: shop undo failed (%s)." % error)
		return
	_refresh_filesystem()


func _write_item(document: Dictionary) -> void:
	var error := ItemStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: item write failed (%s)." % error)
		return
	_refresh_filesystem()


func _restore_item(previous_snapshot: Dictionary) -> void:
	var error := ItemStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: item undo failed (%s)." % error)
		return
	_refresh_filesystem()


func _migrate_voxel_model(model_id: String) -> void:
	var error := VoxelModelStore.migrate_to_native(model_id)
	if error != OK:
		push_error("Ember Inspector: voxel migration failed (%s)." % error)
		return
	_refresh_filesystem()
	voxel_model_changed.emit(model_id)


func _migrate_voxel_models(model_ids: Array[String]) -> void:
	var error := VoxelModelStore.migrate_batch_to_native(model_ids)
	if error != OK:
		push_error("Ember Inspector: voxel batch migration failed (%s)." % error)
		return
	_refresh_filesystem()
	for model_id in model_ids:
		voxel_model_changed.emit(model_id)


func _restore_voxel_model(previous_snapshot: Dictionary) -> void:
	var error := VoxelModelStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: voxel migration undo failed (%s)." % error)
		return
	_refresh_filesystem()
	voxel_model_changed.emit(str(previous_snapshot.get("modelId", "")))


func _restore_voxel_models(previous_snapshots: Array[Dictionary]) -> void:
	var error := VoxelModelStore.restore_snapshots(previous_snapshots)
	if error != OK:
		push_error("Ember Inspector: voxel batch migration undo failed (%s)." % error)
		return
	_refresh_filesystem()
	for snapshot_value in previous_snapshots:
		voxel_model_changed.emit(str(snapshot_value.get("modelId", "")))


func _write_quest(document: Dictionary) -> void:
	var error := QuestStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: quest write failed (%s)." % error)
		return
	_refresh_filesystem()


func _restore_quest(previous_snapshot: Dictionary) -> void:
	var error := QuestStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: quest undo failed (%s)." % error)
		return
	_refresh_filesystem()


func _write_dialogue(document: Dictionary) -> void:
	var error := DialogueStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: dialogue write failed (%s)." % error)
		return
	_refresh_filesystem()


func _write_dialogue_graph(document: Dictionary) -> void:
	var error := DialogueStore.write_graph_document(document)
	if error != OK:
		push_error("Ember Inspector: dialogue graph write failed (%s)." % error)
		return
	_refresh_filesystem()


func _restore_dialogue(previous_snapshot: Dictionary) -> void:
	var error := DialogueStore.restore_snapshot(previous_snapshot)
	if error != OK:
		push_error("Ember Inspector: dialogue undo failed (%s)." % error)
		return
	_refresh_filesystem()


func _refresh_filesystem() -> void:
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request(null, true)


func _refresh(prop: EmberVoxelProp) -> void:
	if not is_instance_valid(prop):
		return
	prop.notify_property_list_changed()
	scene_binding_changed.emit()
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_inspector", prop)


func _refresh_standalone(interact: EmberInteract) -> void:
	if not is_instance_valid(interact):
		return
	interact.refresh_runtime_binding()
	interact.notify_property_list_changed()
	interact.update_gizmos()
	scene_binding_changed.emit()
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_standalone", interact)


func _refresh_quest_interact(interact: EmberInteract) -> void:
	if not is_instance_valid(interact):
		return
	var prop := EmberObjectInspectorModel.voxel_owner(interact)
	if prop != null:
		_refresh(prop)
	else:
		_refresh_standalone(interact)


func _notify_scene_binding_changed() -> void:
	scene_binding_changed.emit()


func _refresh_editor_standalone(interact: EmberInteract) -> void:
	if is_instance_valid(interact) and EditorInterface.get_inspector().get_edited_object() == interact:
		EditorInterface.inspect_object(interact)


func _refresh_editor_inspector(prop: EmberVoxelProp) -> void:
	if not is_instance_valid(prop):
		return
	var edited := EditorInterface.get_inspector().get_edited_object()
	var node := edited as Node
	while node != null:
		if node == prop:
			EditorInterface.inspect_object(prop)
			return
		node = node.get_parent()


func _valid_target(root: Node, prop: EmberVoxelProp) -> bool:
	return root != null and is_instance_valid(prop) and (prop == root or root.is_ancestor_of(prop))


func _valid_standalone(root: Node, interact: EmberInteract) -> bool:
	return (
		root != null
		and is_instance_valid(interact)
		and root.is_ancestor_of(interact)
		and EmberObjectInspectorModel.voxel_owner(interact) == null
	)


func _quest_binding_source_id(target: Node) -> String:
	if target is EmberVoxelProp:
		var prop := target as EmberVoxelProp
		if not prop.placement_id.strip_edges().is_empty():
			return prop.placement_id
	return str(target.name) if target != null else "quest_object"


func _quest_binding_label(target: Node) -> String:
	var source := _quest_binding_source_id(target).strip_edges()
	return source if not source.is_empty() else "объект"


func _available_action_id(suggested: String) -> String:
	var base := suggested if ActionScriptStore.valid_id(suggested) else "quest_object_actions"
	var candidate := base
	var suffix := 2
	while ActionScriptStore.exists(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _contains_action_step(steps: Array, expected: Dictionary) -> bool:
	for raw_step in steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if (
			str(step.get("type", "")) == str(expected.get("type", ""))
			and str(step.get("flag", "")) == str(expected.get("flag", ""))
			and step.get("value", true) == expected.get("value", true)
		):
			return true
	return false


func _event_step_index(steps: Array, event_entry: Dictionary) -> int:
	var writer_index := int(event_entry.get("writerIndex", -1))
	if writer_index >= 0 and writer_index < steps.size():
		var indexed: Variant = steps[writer_index]
		if typeof(indexed) == TYPE_DICTIONARY and _event_step_matches(indexed, event_entry):
			return writer_index
	for index in steps.size():
		var raw_step: Variant = steps[index]
		if typeof(raw_step) == TYPE_DICTIONARY and _event_step_matches(raw_step, event_entry):
			return index
	return -1


func _event_step_matches(step: Dictionary, event_entry: Dictionary) -> bool:
	return (
		str(step.get("type", "")) == "set_flag"
		and str(step.get("flag", "")) == str(event_entry.get("flag", ""))
		and step.get("value", true) == event_entry.get("value", true)
	)


func _action_scene_reference_count(root: Node, script_id: String) -> int:
	if root == null or script_id.is_empty():
		return 0
	var count := 0
	if root is EmberInteract and (root as EmberInteract).resolved_action_script_id() == script_id:
		count += 1
	if root is EmberInteract and EmberObjectInspectorModel.quest_conversation_target(root) != null:
		for routed_id in (root.get("objective_scripts") as Dictionary).values():
			if str(routed_id) == script_id:
				count += 1
		if str(root.get("completed_script_id")) == script_id:
			count += 1
	for child in root.get_children():
		count += _action_scene_reference_count(child, script_id)
	return count


func _unbind_result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}


func _add_optional_quest_do(quest_document: Dictionary) -> void:
	if not quest_document.is_empty():
		_add_do_method("_write_quest", [quest_document])


func _add_optional_quest_undo(previous_snapshot: Dictionary) -> void:
	if not previous_snapshot.is_empty():
		_add_undo_method("_restore_quest", [previous_snapshot])


func _own_subtree(root: Node, node: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own_subtree(root, child)


func _map_owner(node: Node) -> EmberMapLoader:
	var current := node
	while current != null:
		if current is EmberMapLoader:
			return current as EmberMapLoader
		current = current.get_parent()
	return null


func _create_action(title: String, context: Object) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, context)
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)


func _add_do_method(method: StringName, arguments: Array) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_do_method").callv([self, method] + arguments)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(self, method).bindv(arguments))


func _add_undo_method(method: StringName, arguments: Array) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_undo_method").callv([self, method] + arguments)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(self, method).bindv(arguments))


func _add_do_property(object: Object, property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_property(object, property, value)
	else:
		(_undo_redo as UndoRedo).add_do_property(object, property, value)


func _add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_property(object, property, value)
	else:
		(_undo_redo as UndoRedo).add_undo_property(object, property, value)


func _add_do_reference(object: Object) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_reference(object)
	else:
		(_undo_redo as UndoRedo).add_do_reference(object)


func _add_undo_reference(object: Object) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_reference(object)
	else:
		(_undo_redo as UndoRedo).add_undo_reference(object)


func _commit_action() -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).commit_action()
