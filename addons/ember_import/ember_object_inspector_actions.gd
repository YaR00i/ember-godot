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
const VoxelModelStore = preload("res://addons/ember_import/ember_voxel_model_store.gd")

signal scene_binding_changed
signal voxel_model_changed(model_id: String)

var _undo_redo: Object


func configure(undo_redo: Object) -> void:
	_undo_redo = undo_redo


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


func migrate_dialogue(dialogue_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or DialogueStore.owner(dialogue_id) != "legacy":
		return false
	var previous_snapshot := DialogueStore.snapshot(dialogue_id)
	_create_action("Перенести Ember диалог в Godot Resource", root)
	_add_do_method("_migrate_dialogue", [dialogue_id])
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


func migrate_action_script(script_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or ActionScriptStore.owner(script_id) != "legacy":
		return false
	var previous_snapshot := ActionScriptStore.snapshot(script_id)
	_create_action("Перенести Ember цепочку в Godot Resource", root)
	_add_do_method("_migrate_action_script", [script_id])
	_add_undo_method("_restore_chain", [previous_snapshot])
	_commit_action()
	return true


func save_shop(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not ShopStore.validation_errors(document).is_empty():
		return false
	var shop_id := str(document.get("id", ""))
	if ShopStore.owner(shop_id) == "legacy":
		return false
	var previous_snapshot := ShopStore.snapshot(shop_id)
	_create_action("Сохранить Ember магазин", root)
	_add_do_method("_write_shop", [document.duplicate(true)])
	_add_undo_method("_restore_shop", [previous_snapshot])
	_commit_action()
	return true


func migrate_shop(shop_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or ShopStore.owner(shop_id) != "legacy":
		return false
	var previous_snapshot := ShopStore.snapshot(shop_id)
	_create_action("Перенести Ember магазин в Godot Resource", root)
	_add_do_method("_migrate_shop", [shop_id])
	_add_undo_method("_restore_shop", [previous_snapshot])
	_commit_action()
	return true


func save_item(document: Dictionary, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or not ItemStore.validation_errors(document).is_empty():
		return false
	var item_id := str(document.get("id", ""))
	if ItemStore.owner(item_id) == "legacy":
		return false
	var previous_snapshot := ItemStore.snapshot(item_id)
	_create_action("Сохранить Ember предмет", root)
	_add_do_method("_write_item", [document.duplicate(true)])
	_add_undo_method("_restore_item", [previous_snapshot])
	_commit_action()
	return true


func migrate_item(item_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or ItemStore.owner(item_id) != "legacy":
		return false
	var previous_snapshot := ItemStore.snapshot(item_id)
	_create_action("Перенести Ember предмет в Godot Resource", root)
	_add_do_method("_migrate_item", [item_id])
	_add_undo_method("_restore_item", [previous_snapshot])
	_commit_action()
	return true


func migrate_voxel_model(model_id: String, root_override: Node = null) -> bool:
	var root := root_override if root_override != null else EditorInterface.get_edited_scene_root()
	if root == null or _undo_redo == null or VoxelModelStore.owner(model_id) != "legacy_import":
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
		if VoxelModelStore.owner(model_id) != "legacy_import":
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


func _migrate_action_script(script_id: String) -> void:
	var error := ActionScriptStore.migrate_to_native(script_id)
	if error != OK:
		push_error("Ember Inspector: action-chain migration failed (%s)." % error)
		return
	_refresh_filesystem()


func _write_shop(document: Dictionary) -> void:
	var error := ShopStore.write_document(document)
	if error != OK:
		push_error("Ember Inspector: shop write failed (%s)." % error)
		return
	_refresh_filesystem()


func _migrate_shop(shop_id: String) -> void:
	var error := ShopStore.migrate_to_native(shop_id)
	if error != OK:
		push_error("Ember Inspector: shop migration failed (%s)." % error)
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


func _migrate_item(item_id: String) -> void:
	var error := ItemStore.migrate_to_native(item_id)
	if error != OK:
		push_error("Ember Inspector: item migration failed (%s)." % error)
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


func _migrate_dialogue(dialogue_id: String) -> void:
	var error := DialogueStore.migrate_to_native(dialogue_id)
	if error != OK:
		push_error("Ember Inspector: dialogue migration failed (%s)." % error)
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
		EditorInterface.get_resource_filesystem().scan_sources()


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
