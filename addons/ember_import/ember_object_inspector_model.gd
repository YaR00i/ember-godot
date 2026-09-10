@tool
class_name EmberObjectInspectorModel
extends RefCounted
## Read-only projection for the Ember editor Inspector. It joins existing
## asset metadata, scene-owned nodes and generated prefab state without writes.


static func supports(object: Object) -> bool:
	return voxel_owner(object) != null or object is EmberInteract


static func voxel_owner(object: Object) -> EmberVoxelProp:
	var node := object as Node
	while node != null:
		if node is EmberVoxelProp:
			return node as EmberVoxelProp
		node = node.get_parent()
	return null


static func snapshot(object: Object) -> Dictionary:
	var prop := voxel_owner(object)
	if prop != null:
		return _voxel_snapshot(object, prop)
	if object is EmberInteract:
		return _standalone_interact_snapshot(object as EmberInteract)
	return {"supported": false}


static func _voxel_snapshot(selected: Object, prop: EmberVoxelProp) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var components: Array[Dictionary] = []
	var model_id := prop.model_id.strip_edges()
	var placement_id := prop.placement_id.strip_edges()
	var source_paths := EmberVoxelPrefab.source_paths(model_id) if not model_id.is_empty() else {"json": "", "vox": ""}
	var json_path := str(source_paths.get("json", ""))
	var vox_path := str(source_paths.get("vox", ""))
	var prefab := EmberVoxelPrefab.load_json(model_id) if not model_id.is_empty() else {}
	var model := EmberVoxelPrefab.model_of(prefab)
	var map := _map_owner(prop)

	if placement_id.is_empty():
		_diag(diagnostics, "error", "У экземпляра нет placement_id; safe duplicate/save не гарантированы.")
	if model_id.is_empty():
		_diag(diagnostics, "error", "У экземпляра нет model_id.")
	elif not FileAccess.file_exists(json_path):
		_diag(diagnostics, "error", "Metadata модели не найдены: %s" % json_path)

	var expected_signature := EmberVoxelPrefab.source_signature(model_id) if not model_id.is_empty() else ""
	var stored_signature := str(prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, ""))
	var prefab_state := "актуален"
	if expected_signature.is_empty():
		prefab_state = "нет source signature"
	elif stored_signature != expected_signature:
		prefab_state = "нужна пересборка"
		_diag(diagnostics, "warning", "Voxel source изменён после сборки prefab.")

	components.append(_renderer_component(prop, json_path, vox_path))
	components.append(_collider_component(prop, model, diagnostics))
	var light_component := _light_component(prop, model, map, diagnostics)
	if not light_component.is_empty():
		components.append(light_component)

	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact != null:
		components.append(_interact_component(interact, map, diagnostics))

	if selected != prop:
		var selected_node := selected as Node
		var selected_name := selected_node.name if selected_node else selected.get_class()
		_diag(
			diagnostics,
			"info",
			"Выбран generated/scene child «%s». Authoring owner — %s." % [selected_name, prop.name],
		)

	return {
		"supported": true,
		"kind": "Voxel Prop",
		"name": str(prop.name),
		"placementId": placement_id,
		"modelId": model_id,
		"mapId": map.map_id if map else "",
		"selectedIsOwner": selected == prop,
		"prefabState": prefab_state,
		"sources": {
			"json": json_path,
			"vox": vox_path,
			"prefab": EmberVoxelPrefab.prefab_path(model_id) if not model_id.is_empty() else "",
		},
		"components": components,
		"diagnostics": diagnostics,
	}


static func _standalone_interact_snapshot(interact: EmberInteract) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var map := _map_owner(interact)
	return {
		"supported": true,
		"kind": "Interact",
		"name": str(interact.name),
		"placementId": "",
		"modelId": "",
		"mapId": map.map_id if map else "",
		"selectedIsOwner": true,
		"prefabState": "scene-owned",
		"sources": {},
		"components": [
			_standalone_volume_component(interact, diagnostics),
			_interact_component(interact, map, diagnostics),
		],
		"diagnostics": diagnostics,
	}


static func _standalone_volume_component(
	interact: EmberInteract,
	diagnostics: Array[Dictionary],
) -> Dictionary:
	var shape_node := interact.get_node_or_null("Shape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		_diag(diagnostics, "error", "Самостоятельная зона должна иметь Shape с BoxShape3D.")
	var size := box.size if box != null else Vector3.ZERO
	return {
		"id": "trigger_volume",
		"title": "Trigger Volume",
		"source": "Scene",
		"rows": [
			{"label": "Shape", "value": "BoxShape3D" if box != null else "нет", "status": "ok" if box != null else "error"},
			{"label": "Bounds", "value": "%.1f × %.1f × %.1f" % [size.x, size.y, size.z]},
		],
	}


static func _renderer_component(prop: EmberVoxelProp, json_path: String, vox_path: String) -> Dictionary:
	var mesh_instance := prop.get_node_or_null("Mesh") as MeshInstance3D
	var mesh := mesh_instance.mesh if mesh_instance else null
	var surfaces: Array[String] = []
	if mesh != null:
		for index in mesh.get_surface_count():
			var surface_name: String = mesh.surface_get_name(index)
			surfaces.append(surface_name if not surface_name.is_empty() else "surface_%d" % index)
	var source_kind := ".vox + .json" if not vox_path.is_empty() else ".json"
	return {
		"id": "renderer",
		"title": "Voxel Renderer",
		"source": "Asset",
		"rows": [
			{"label": "Source", "value": source_kind},
			{"label": "Mesh", "value": "есть" if mesh != null else "нет"},
			{"label": "Surfaces", "value": ", ".join(surfaces) if not surfaces.is_empty() else "—"},
			{"label": "Metadata", "value": json_path.get_file() if not json_path.is_empty() else "—"},
		],
	}


static func _collider_component(
	prop: EmberVoxelProp,
	model: Dictionary,
	diagnostics: Array[Dictionary],
) -> Dictionary:
	var authored := bool(model.get("physical", false))
	var shape := prop.get_node_or_null("Collision/Shape") as CollisionShape3D
	var actual := shape != null and shape.shape != null
	var voxels: Variant = model.get("voxels", [])
	var empty: bool = voxels.size() > 0 and voxels.count(0) == voxels.size()
	if (authored and not empty) != actual:
		_diag(
			diagnostics,
			"error",
			"Collider расходится с metadata: physical=%s, generated=%s." % [authored, actual],
		)
	return {
		"id": "collider",
		"title": "Collider",
		"source": "Asset",
		"rows": [
			{"label": "Physical", "value": _yes_no(authored)},
			{"label": "Generated", "value": _yes_no(actual), "source": "Derived"},
			{
				"label": "Shape",
				"value": shape.shape.get_class() if actual else ("Пустая модель · коллизия появится после лепки" if empty else "—"),
				"source": "Derived",
			},
		],
	}


static func _light_component(
	prop: EmberVoxelProp,
	model: Dictionary,
	map: EmberMapLoader,
	diagnostics: Array[Dictionary],
) -> Dictionary:
	var casts := bool(model.get("emissiveCastsLight", false))
	var summary := EmberVoxelLight.summarize(model)
	var omni := prop.get_node_or_null("Omni") as OmniLight3D
	if not casts and summary.is_empty() and omni == null:
		return {}
	if casts != (omni != null):
		_diag(
			diagnostics,
			"error",
			"Emissive Light расходится с prefab: casts=%s, Omni=%s." % [casts, omni != null],
		)
	var requested_shadows := bool(model.get("emissiveLightShadows", false))
	var suppress_host := bool(model.get("emissiveSuppressHostShadow", false))
	var shadow_body := prop.get_node_or_null("ShadowBody") as MeshInstance3D
	if casts and not suppress_host and shadow_body == null:
		var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
		if visual == null or visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_diag(diagnostics, "warning", "Лампа не имеет ShadowBody/host shadow caster.")
	var centroid := "—"
	if not summary.is_empty():
		centroid = "%.1f, %.1f, %.1f" % [
			float(summary.get("cx", 0.0)),
			float(summary.get("cy", 0.0)),
			float(summary.get("cz", 0.0)),
		]
	var rows: Array[Dictionary] = [
		{"label": "Emissive voxels", "value": str(int(summary.get("count", 0)))},
		{"label": "Centroid", "value": centroid},
		{"label": "Casts light", "value": _yes_no(casts)},
		{"label": "Range", "value": "%.2f тайла" % float(model.get("emissiveLightRange", 2.0))},
		{"label": "Strength", "value": "%.2f" % float(model.get("emissiveStrength", 0.75))},
		{"label": "Shadow requested", "value": _yes_no(requested_shadows)},
		{"label": "Host shadow suppressed", "value": _yes_no(suppress_host)},
		{
			"label": "Flicker",
			"value": _flicker_label(model),
		},
		{
			"label": "Effective Omni range",
			"value": "%.2f Godot" % omni.omni_range if omni else "—",
			"source": "Derived",
		},
		{
			"label": "Effective energy",
			"value": "%.2f" % omni.light_energy if omni else "—",
			"source": "Derived",
		},
		{
			"label": "Shadow active in editor",
			"value": _yes_no(omni.shadow_enabled) if omni else "—",
			"source": "Derived",
		},
	]
	if map != null:
		rows.append({
			"label": "Map shadow budget",
			"value": "%d production slots" % map.omni_shadow_count,
			"source": "Derived",
		})
	return {
		"id": "light",
		"title": "Emissive Light",
		"source": "Asset",
		"rows": rows,
	}


static func _interact_component(
	interact: EmberInteract,
	map: EmberMapLoader,
	diagnostics: Array[Dictionary],
) -> Dictionary:
	var rows: Array[Dictionary] = [
		{"label": "Kind", "value": EmberSceneAuthoring.interact_kind_title(interact.kind)},
		{"label": "Activation", "value": interact.activation_title(), "source": "Scene"},
	]
	if interact.kind == "quest_marker":
		var authored_status := QuestState.resolve_status(interact.quest_status, "", {})
		var bound_quest_id := interact.effective_quest_id()
		var marker := interact.effective_quest_marker_projection({})
		if not bound_quest_id.is_empty():
			rows.append({"label": "Quest", "value": bound_quest_id, "source": "Scene"})
		rows.append({
			"label": "Роль маркера",
			"value": _quest_marker_role_label(marker),
			"source": "Derived",
		})
		rows.append({
			"label": "На свежем прохождении",
			"value": _quest_marker_state_label(marker),
			"source": "Derived",
		})
		rows.append({
			"label": "Current quest icon",
			"value": QuestState.resolve_icon_id(
				interact.icon_id, str(marker.get("status", authored_status))
			),
			"source": "Derived",
		})
		rows.append({"label": "Fallback status", "value": authored_status, "source": "Scene"})
		var status_flag_id := interact.effective_quest_status_flag_id()
		if not status_flag_id.is_empty():
			rows.append({"label": "Quest flag", "value": status_flag_id, "source": "Derived"})
		if (
			not bound_quest_id.is_empty()
			and not interact.resolved_action_script_id().is_empty()
			and not bool(marker.get("recognized", false))
		):
			_diag(
				diagnostics,
				"warning",
				"Цепочка не содержит события выбранного задания; маркер показывает общий статус.",
			)
	if not interact.trigger_id.is_empty():
		var trigger_ok := _region_exists(map.map_id if map else "", interact.trigger_id)
		rows.append(_reference_row("Trigger", interact.trigger_id, trigger_ok))
		if not trigger_ok:
			_diag(diagnostics, "error", "Trigger не найден: %s" % interact.trigger_id)
	var action_script_id := interact.resolved_action_script_id()
	if not action_script_id.is_empty():
		var script_ref := EmberInteractionContent.resolve_script_ref(action_script_id)
		var script_ok := not script_ref.is_empty()
		rows.append(_reference_row("Script", _script_summary(action_script_id, script_ref), script_ok))
		if not script_ok:
			_diag(diagnostics, "error", "Script/scene не найден: %s" % action_script_id)
	if not interact.shop_id.is_empty():
		var shop := EmberInteractionContent.shop_view(interact.shop_id)
		var shop_ok := not shop.is_empty()
		var listings: Array = shop.get("listings", [])
		var shop_label := "%s · %d позиций" % [
			str(shop.get("nameRu", interact.shop_id)),
			listings.size(),
		] if shop_ok else interact.shop_id
		rows.append(_reference_row("Shop", shop_label, shop_ok))
		if not shop_ok:
			_diag(diagnostics, "error", "Shop не найден: %s" % interact.shop_id)
	if not interact.target_map_id.is_empty():
		var map_ok := FileAccess.file_exists(EmberPack.map_path(interact.target_map_id))
		rows.append(_reference_row("Target map", interact.target_map_id, map_ok))
		if not map_ok:
			_diag(diagnostics, "error", "Target map не найдена: %s" % interact.target_map_id)
		if not interact.target_region_id.is_empty():
			var region_ok := map_ok and _region_exists(interact.target_map_id, interact.target_region_id)
			rows.append(_reference_row("Target region", interact.target_region_id, region_ok))
			if not region_ok:
				_diag(
					diagnostics,
					"error",
					"Region %s не найдена на карте %s." % [interact.target_region_id, interact.target_map_id],
				)
	if not interact.condition_flag_id.is_empty():
		var expected: Variant = (
			interact.condition_value
			if interact.condition_value != null
			else interact.condition_expected
		)
		rows.append({
			"label": "Condition",
			"value": "%s = %s" % [
				interact.condition_flag_id,
				_typed_value_text(expected),
			],
			"source": "Scene",
		})
		if not interact.fallback_script_id.is_empty():
			var fallback_ref := EmberInteractionContent.resolve_script_ref(interact.fallback_script_id)
			var fallback_ok := not fallback_ref.is_empty()
			rows.append(_reference_row(
				"Fallback script",
				_script_summary(interact.fallback_script_id, fallback_ref),
				fallback_ok,
			))
			if not fallback_ok:
				_diag(diagnostics, "error", "Запасная цепочка не найдена: %s" % interact.fallback_script_id)
	if interact.one_shot:
		rows.append({
			"label": "One shot",
			"value": "после успеха → %s = Да" % interact.completion_flag_id,
			"source": "Scene",
		})
	if not interact.note.is_empty():
		rows.append({"label": "Note", "value": interact.note})
	_validate_interact_required(interact, diagnostics)
	return {
		"id": "interact",
		"title": "Interact",
		"source": "Scene",
		"rows": rows,
	}


static func _typed_value_text(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "Да" if value else "Нет / отсутствует"
	return str(value)


static func _quest_marker_role_label(marker: Dictionary) -> String:
	match str(marker.get("role", "summary")):
		"start": return "Выдать задание"
		"objective":
			var text := str(marker.get("objectiveText", "")).strip_edges()
			var objective_id := str(marker.get("objectiveId", "")).strip_edges()
			return "Цель · %s" % (text if not text.is_empty() else objective_id)
		"complete": return "Завершить / сдать"
	return "Общий статус (нет события в цепочке)"


static func _quest_marker_state_label(marker: Dictionary) -> String:
	if bool(marker.get("visible", true)):
		match str(marker.get("status", "available")):
			"active": return "Виден · голубой компас"
			"done": return "Виден · мятная галочка"
		return "Виден · янтарный !"
	match str(marker.get("reason", "")):
		"quest_not_started": return "Скрыт · задание ещё не принято"
		"prerequisites": return "Скрыт · предыдущие цели не выполнены"
		"objectives_incomplete": return "Скрыт · задание ещё не готово к сдаче"
		"event_already_resolved": return "Скрыт · событие уже выполнено"
	return "Скрыт"


static func _validate_interact_required(interact: EmberInteract, diagnostics: Array[Dictionary]) -> void:
	for message in EmberSceneAuthoring.interact_validation_errors(EmberSceneAuthoring.interact_values(interact)):
		_diag(diagnostics, "error", message)


static func _script_summary(script_id: String, resolved: Dictionary) -> String:
	if resolved.is_empty():
		return script_id
	var data: Dictionary = resolved.get("data", {})
	var steps: Array = data.get("steps", [])
	var label := str(data.get("nameRu", script_id))
	var kind := str(resolved.get("kind", ""))
	if kind == "scene":
		return "%s · scene/%s · %d шагов" % [label, str(data.get("use", "cutscene")), steps.size()]
	return "%s · action list · %d шагов" % [label, steps.size()]


static func _reference_row(label: String, value: String, ok: bool) -> Dictionary:
	return {
		"label": label,
		"value": "%s · %s" % [value, "resolved" if ok else "MISSING"],
		"status": "ok" if ok else "error",
	}


static func _region_exists(map_id: String, region_id: String) -> bool:
	if map_id.is_empty() or region_id.is_empty():
		return false
	var parsed: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var regions: Variant = (parsed as Dictionary).get("regions", [])
	if typeof(regions) != TYPE_ARRAY:
		return false
	for raw_region in regions:
		if typeof(raw_region) == TYPE_DICTIONARY and str(raw_region.get("id", "")) == region_id:
			return true
	return false


static func _map_owner(node: Node) -> EmberMapLoader:
	var current := node
	var top := node
	while current != null:
		top = current
		if current is EmberMapLoader:
			return current as EmberMapLoader
		current = current.get_parent()
	return top.find_child("Map", true, false) as EmberMapLoader if top != null else null


static func _flicker_label(model: Dictionary) -> String:
	var kinds: Array[String] = []
	if bool(model.get("emissiveTorchFlicker", false)):
		kinds.append("torch")
	if bool(model.get("emissiveLanternFlicker", false)):
		kinds.append("lantern")
	return " + ".join(kinds) if not kinds.is_empty() else "нет"


static func _yes_no(value: bool) -> String:
	return "да" if value else "нет"


static func _diag(diagnostics: Array[Dictionary], severity: String, message: String) -> void:
	diagnostics.append({"severity": severity, "message": message})
const QuestState = preload("res://scripts/ember_quest_state.gd")
