@tool
extends RefCounted
## Canonical normalization and operations for Resource-owned authoring groups.

const DEFAULT_COLORS := [
	Color("ff8a3d"),
	Color("4dc9ff"),
	Color("a9e85b"),
	Color("d18cff"),
	Color("ffd45c"),
	Color("58dfbd"),
]

static func normalized(groups: Array[Dictionary], voxel_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used := {}
	for raw in groups:
		var id := str(raw.get("id", "")).strip_edges().validate_filename().to_lower()
		if id.is_empty() or used.has(id):
			continue
		used[id] = true
		var unique := {}
		for index in raw.get("indices", PackedInt32Array()):
			if index >= 0 and index < voxel_count:
				unique[int(index)] = true
		var indices := PackedInt32Array(unique.keys())
		indices.sort()
		if indices.is_empty():
			continue
		result.append({
			"id": id,
			"name": str(raw.get("name", id)).strip_edges().substr(0, 64),
			"indices": indices,
			"locked": bool(raw.get("locked", false)),
			"color": _safe_color(raw.get("color", default_color(result.size()))),
		})
	return result


static func apply(groups: Array[Dictionary], operation: Dictionary, voxel_count: int) -> Dictionary:
	var before := normalized(groups, voxel_count)
	var after := before.duplicate(true)
	var kind := str(operation.get("kind", ""))
	var id := str(operation.get("id", ""))
	var position := _find(after, id)
	if kind == "create":
		var name := _safe_name(operation.get("name", "Группа"))
		var requested_id := str(operation.get("id", "")).strip_edges()
		var next_id := _unique_id(after, requested_id if not requested_id.is_empty() else name)
		var indices := _indices(operation.get("indices", PackedInt32Array()), voxel_count)
		if indices.is_empty():
			return {"error": "Сначала выделите занятые воксели"}
		after.append({
			"id": next_id,
			"name": name,
			"indices": indices,
			"locked": false,
			"color": _safe_color(operation.get("color", default_color(after.size()))),
		})
		return {"groups": after, "selected": next_id, "label": "Создать группу"}
	if position < 0:
		return {"error": "Группа больше не существует"}
	var group: Dictionary = after[position]
	if kind == "rename":
		group["name"] = _safe_name(operation.get("name", group["name"]))
	elif kind == "replace":
		var indices := _indices(operation.get("indices", PackedInt32Array()), voxel_count)
		if indices.is_empty():
			return {"error": "Нельзя заменить группу пустым выделением"}
		group["indices"] = indices
	elif kind == "lock":
		group["locked"] = bool(operation.get("locked", false))
	elif kind == "color":
		group["color"] = _safe_color(operation.get("color", group.get("color", default_color(position))))
	elif kind == "delete":
		after.remove_at(position)
		return {"groups": after, "selected": "", "label": "Удалить группу"}
	else:
		return {"error": "Неизвестная операция группы"}
	after[position] = group
	if after == before:
		return {"error": "Группа уже имеет эти значения"}
	return {"groups": after, "selected": id, "label": "Изменить группу"}


static func locked_indices(groups: Array[Dictionary]) -> Dictionary:
	var result := {}
	for group in groups:
		if bool(group.get("locked", false)):
			for index in group.get("indices", PackedInt32Array()):
				result[int(index)] = true
	return result


static func group(groups: Array[Dictionary], id: String) -> Dictionary:
	var position := _find(groups, id)
	return groups[position] if position >= 0 else {}


static func default_color(index: int) -> Color:
	return DEFAULT_COLORS[posmod(index, DEFAULT_COLORS.size())]


static func _find(groups: Array[Dictionary], id: String) -> int:
	for index in groups.size():
		if str(groups[index].get("id", "")) == id:
			return index
	return -1


static func _safe_name(value: Variant) -> String:
	var name := str(value).strip_edges().substr(0, 64)
	return name if not name.is_empty() else "Группа"


static func _unique_id(groups: Array[Dictionary], value: String) -> String:
	var base := value.strip_edges().validate_filename().to_lower().replace(" ", "_")
	if base.is_empty():
		base = "group"
	var result := base
	var suffix := 2
	while _find(groups, result) >= 0:
		result = "%s_%d" % [base, suffix]
		suffix += 1
	return result


static func _indices(value: Variant, voxel_count: int) -> PackedInt32Array:
	var unique := {}
	for index in value:
		if index >= 0 and index < voxel_count:
			unique[int(index)] = true
	var result := PackedInt32Array(unique.keys())
	result.sort()
	return result


static func _safe_color(value: Variant) -> Color:
	var color := value as Color if value is Color else DEFAULT_COLORS[0]
	color.a = 1.0
	return color
