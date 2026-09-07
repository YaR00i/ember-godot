class_name EmberSceneAuthoring
extends RefCounted
## Pure helpers for Godot-authored map edits. The .tscn scene owns these changes;
## JOI placement JSON is not written back from this bridge.

const QuestState = preload("res://scripts/ember_quest_state.gd")
const STANDALONE_TRIGGER_CONTAINER := "AuthoredTriggers"
const INTERACT_STRING_FIELDS := [
	"kind",
	"trigger_id",
	"target_map_id",
	"target_region_id",
	"shop_id",
	"script_id",
	"quest_id",
	"icon_id",
	"quest_status",
	"condition_flag_id",
	"fallback_script_id",
	"completion_flag_id",
	"activation_mode",
	"note",
]
const INTERACT_BOOL_FIELDS := ["condition_expected", "one_shot"]
const INTERACT_VARIANT_FIELDS := ["condition_value"]
const INTERACT_FIELDS := INTERACT_STRING_FIELDS + INTERACT_BOOL_FIELDS + INTERACT_VARIANT_FIELDS


static func interact_kind_title(kind: String) -> String:
	match kind:
		"door": return "Дверь / переход"
		"talk": return "Разговор"
		"shop": return "Магазин"
		"quest_marker": return "Событие задания"
		"trigger": return "Зона-событие"
		"chest": return "Сундук (из карты)"
		"custom": return "Другое действие"
	return kind


static func placement_ids(root: Node) -> Dictionary:
	var result := {}
	_collect_placement_ids(root, result)
	return result


static func next_duplicate_id(root: Node, source: EmberVoxelProp) -> String:
	var used := placement_ids(root)
	var base := source.placement_id.strip_edges()
	if base.is_empty():
		base = str(source.name).strip_edges()
	if base.is_empty():
		base = source.model_id if not source.model_id.is_empty() else "voxel_prop"
	var stem := base + "_copy"
	var candidate := stem
	var suffix := 2
	while used.has(candidate):
		candidate = "%s_%d" % [stem, suffix]
		suffix += 1
	return candidate


static func next_model_placement_id(root: Node, model_id: String) -> String:
	var used := placement_ids(root)
	var stem := "placed_" + _safe_id(model_id.trim_prefix("vox_"))
	if stem == "placed_":
		stem = "placed_voxel_prop"
	var candidate := stem
	var suffix := 2
	while used.has(candidate):
		candidate = "%s_%d" % [stem, suffix]
		suffix += 1
	return candidate


static func make_model_instance(
	root: Node,
	packed: PackedScene,
	model_id: String,
	local_position: Vector3,
) -> EmberVoxelProp:
	if root == null or packed == null or model_id.strip_edges().is_empty():
		return null
	var prop := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	if prop == null:
		return null
	var placement_id := next_model_placement_id(root, model_id)
	prop.name = placement_id
	prop.model_id = model_id
	prop.placement_id = placement_id
	prop.position = local_position
	return prop


static func attach_model_instance(root: Node, parent: Node, prop: EmberVoxelProp) -> void:
	if root == null or parent == null or prop == null:
		return
	if prop.get_parent() != parent:
		parent.add_child(prop)
	prop.owner = root


static func make_duplicate(
	root: Node,
	source: EmberVoxelProp,
	offset: Vector3,
) -> EmberVoxelProp:
	if root == null or source == null:
		return null
	var duplicate := source.duplicate() as EmberVoxelProp
	if duplicate == null:
		return null
	var new_id := next_duplicate_id(root, source)
	duplicate.name = new_id
	duplicate.placement_id = new_id
	duplicate.transform = source.transform
	duplicate.position += offset
	return duplicate


static func attach_duplicate(
	root: Node,
	source: EmberVoxelProp,
	parent: Node,
	duplicate: EmberVoxelProp,
) -> void:
	if duplicate.get_parent() != parent:
		parent.add_child(duplicate)
	duplicate.owner = root
	_copy_scene_owned_children(root, source, duplicate)


static func interact_values(interact: EmberInteract) -> Dictionary:
	if interact == null:
		return normalized_interact_values({})
	var result := {}
	for field in INTERACT_STRING_FIELDS:
		result[field] = str(interact.get(field))
	for field in INTERACT_BOOL_FIELDS:
		result[field] = bool(interact.get(field))
	for field in INTERACT_VARIANT_FIELDS:
		result[field] = interact.get(field)
	return result


static func normalized_interact_values(values: Dictionary) -> Dictionary:
	var kind := str(values.get("kind", "door")).strip_edges()
	if kind not in EmberInteract.KINDS:
		kind = "custom"
	var result := {"kind": kind}
	for field in INTERACT_STRING_FIELDS:
		if field != "kind":
			result[field] = str(values.get(field, "")).strip_edges()
	result.condition_expected = bool(values.get("condition_expected", true))
	result.condition_value = _normalized_flag_value(
		values.get("condition_value", result.condition_expected)
	)
	result.one_shot = bool(values.get("one_shot", false))
	if str(result.activation_mode) not in EmberInteract.ACTIVATION_MODES:
		result.activation_mode = "press"
	if str(result.quest_status) not in QuestState.STATUSES:
		result.quest_status = "available"
	match kind:
		"door":
			result.shop_id = ""
			result.script_id = ""
			result.quest_id = ""
			result.icon_id = ""
			result.quest_status = "available"
		"talk":
			result.trigger_id = ""
			result.target_map_id = ""
			result.target_region_id = ""
			result.shop_id = ""
			result.quest_id = ""
			result.icon_id = ""
			result.quest_status = "available"
		"shop":
			result.trigger_id = ""
			result.target_map_id = ""
			result.target_region_id = ""
			result.quest_id = ""
			result.icon_id = ""
			result.quest_status = "available"
		"quest_marker":
			result.target_map_id = ""
			result.target_region_id = ""
			result.shop_id = ""
			_clear_launch_rules(result)
		"chest":
			result.quest_id = ""
			_clear_launch_rules(result)
		_:
			result.target_map_id = ""
			result.target_region_id = ""
			result.shop_id = ""
			result.quest_id = ""
			result.icon_id = ""
			result.quest_status = "available"
	if result.one_shot and str(result.completion_flag_id).is_empty():
		# Kept invalid for the form to explain; never invent a key at runtime.
		pass
	return result


static func interact_validation_errors(values: Dictionary) -> Array[String]:
	var normalized := normalized_interact_values(values)
	var errors: Array[String] = []
	match str(normalized.kind):
		"door":
			if str(normalized.target_map_id).is_empty() and str(normalized.trigger_id).is_empty():
				errors.append("Для двери укажите карту назначения или триггер.")
		"talk":
			if str(normalized.script_id).is_empty():
				errors.append("Для разговора выберите сценарий.")
		"shop":
			if str(normalized.shop_id).is_empty():
				errors.append("Для лавки выберите магазин.")
		"trigger", "custom":
			if str(normalized.script_id).is_empty():
				errors.append("Для триггера выберите или создайте цепочку действий.")
	if not str(normalized.fallback_script_id).is_empty() and str(normalized.condition_flag_id).is_empty():
		errors.append("Запасная цепочка требует имя проверяемого флага.")
	if bool(normalized.one_shot) and str(normalized.completion_flag_id).is_empty():
		errors.append("Для одноразового запуска нужен флаг выполнения.")
	return errors


static func suggested_completion_flag(map_id: String, object_id: String) -> String:
	var raw := "%s_%s_used" % [map_id.strip_edges(), object_id.strip_edges()]
	var result := ""
	for character in raw.to_lower():
		var code := character.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "_":
			result += character
		elif not result.ends_with("_"):
			result += "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_")


static func make_interact(values: Dictionary, tile_size: float) -> EmberInteract:
	var interact := EmberInteract.new()
	interact.name = "Interact"
	apply_interact_values(interact, values)
	interact.collision_layer = 4
	interact.collision_mask = 0
	interact.monitoring = false
	interact.monitorable = true
	interact.add_to_group("ember_interact")
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(tile_size, 1.0) * 0.7
	shape.shape = sphere
	interact.add_child(shape)
	return interact


static func make_standalone_trigger(tile_size: float) -> EmberInteract:
	var interact := make_interact({
		"kind": "trigger",
		"note": "Godot standalone F-trigger",
	}, tile_size)
	var shape_node := interact.get_node_or_null("Shape") as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(tile_size, 1.0) * 1.5,
		8.0,
		maxf(tile_size, 1.0) * 1.5,
	)
	if shape_node != null:
		shape_node.shape = box
	return interact


static func next_standalone_trigger_name(root: Node) -> String:
	var container := root.get_node_or_null(STANDALONE_TRIGGER_CONTAINER) if root != null else null
	var index := 1
	while container != null and container.has_node("trigger_%d" % index):
		index += 1
	return "trigger_%d" % index


static func standalone_box_size(interact: EmberInteract) -> Vector3:
	var shape_node := interact.get_node_or_null("Shape") as CollisionShape3D if interact != null else null
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	return box.size if box != null else Vector3.ZERO


static func apply_interact_values(interact: EmberInteract, values: Dictionary) -> void:
	if interact == null:
		return
	var normalized := normalized_interact_values(values)
	for field in INTERACT_FIELDS:
		interact.set(field, normalized.get(field, ""))


static func _clear_launch_rules(values: Dictionary) -> void:
	values.condition_flag_id = ""
	values.condition_expected = true
	values.condition_value = true
	values.fallback_script_id = ""
	values.one_shot = false
	values.completion_flag_id = ""
	values.activation_mode = "press"


static func _normalized_flag_value(value: Variant) -> Variant:
	if typeof(value) in [TYPE_BOOL, TYPE_STRING, TYPE_INT]:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)):
		return value
	return true


static func attach_interact(root: Node, prop: EmberVoxelProp, interact: EmberInteract) -> void:
	if root == null or prop == null or interact == null:
		return
	if interact.get_parent() != prop:
		prop.add_child(interact)
	_own_subtree(root, interact)


static func detach_interact(prop: EmberVoxelProp, interact: EmberInteract) -> void:
	if prop != null and interact != null and interact.get_parent() == prop:
		_own_subtree(null, interact)
		prop.remove_child(interact)


static func _collect_placement_ids(node: Node, result: Dictionary) -> void:
	if node == null:
		return
	if node is EmberVoxelProp:
		var placement_id := (node as EmberVoxelProp).placement_id.strip_edges()
		if not placement_id.is_empty():
			result[placement_id] = true
	for child in node.get_children():
		_collect_placement_ids(child, result)


static func _copy_scene_owned_children(root: Node, source: Node, duplicate: Node) -> void:
	for source_child in source.get_children():
		var duplicate_child := duplicate.get_node_or_null(NodePath(str(source_child.name)))
		if duplicate_child == null:
			continue
		if source_child.owner == root:
			duplicate_child.owner = root
		_copy_scene_owned_children(root, source_child, duplicate_child)


static func _safe_id(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		var code := character.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "_":
			result += character
		elif not result.ends_with("_"):
			result += "_"
	return result.trim_prefix("_").trim_suffix("_")


static func _own_subtree(root: Node, node: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own_subtree(root, child)
