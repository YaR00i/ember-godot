class_name EmberInteractionContent
extends RefCounted
## Read-only content adapter; maps/regions are saved Godot scenes, other
## catalogs keep their existing native-first/legacy boundary.

const MAX_SCRIPT_DEPTH := 8
const ActionCatalog = preload("res://scripts/ember_action_catalog.gd")
const DialogueCatalog = preload("res://scripts/ember_dialogue_catalog.gd")
const ShopCatalog = preload("res://scripts/ember_shop_catalog.gd")
const ItemCatalog = preload("res://scripts/ember_item_catalog.gd")
const MAP_SCENE_DIRECTORY := "res://scenes"
static var _map_snapshots: Dictionary = {}


static func resolve_script_ref(ref_id: String) -> Dictionary:
	var clean_id := ref_id.strip_edges()
	if clean_id.is_empty():
		return {}
	var script := ActionCatalog.document(clean_id)
	if not script.is_empty():
		return {"kind": "script", "data": script}
	var scene := DialogueCatalog.document(clean_id)
	if not scene.is_empty():
		return {"kind": "scene", "data": scene}
	return {}


static func dialogue_for_id(ref_id: String) -> Dictionary:
	return _dialogue_for_id(ref_id, {}, 0)


static func shop_view(shop_id: String) -> Dictionary:
	var shop := shop_definition(shop_id)
	if shop.is_empty():
		return {}
	return {
		"id": str(shop.get("id", shop_id)),
		"nameRu": str(shop.get("nameRu", shop_id)),
		"listings": EmberEconomy.listing_views(
			shop,
			EmberEconomy.seed_shop_remaining(shop),
			item_definitions(),
		),
	}


static func shop_definition(shop_id: String) -> Dictionary:
	return ShopCatalog.definition(shop_id)


static func item_definitions() -> Dictionary:
	return ItemCatalog.definitions()


static func script_ref_ids() -> Array[String]:
	var ids := ActionCatalog.ids()
	for scene_id in DialogueCatalog.ids():
		if scene_id not in ids:
			ids.append(scene_id)
	ids.sort()
	return ids


static func action_script_ids() -> Array[String]:
	return ActionCatalog.ids()


static func dialogue_ids() -> Array[String]:
	return DialogueCatalog.ids()


static func item_ids() -> Array[String]:
	return ItemCatalog.ids()


static func shop_ids() -> Array[String]:
	return ShopCatalog.ids()


static func map_ids(scene_directory := MAP_SCENE_DIRECTORY) -> Array[String]:
	var result: Array[String] = []
	var sources := {}
	for filename in DirAccess.get_files_at(scene_directory):
		if filename.ends_with(".tscn.remap"):
			filename = filename.trim_suffix(".remap")
		if not filename.ends_with(".tscn"):
			continue
		var map_id := filename.get_basename()
		var path := scene_directory.path_join(filename)
		# Catalog discovery reads native dependencies, not every map's meshes and
		# terrain. Exact saved regions are read only for the selected destination.
		if map_id not in result and _has_map_source(path, sources, []):
			result.append(map_id)
	result.sort()
	return result


static func _has_map_source(path: String, sources: Dictionary, ancestry: Array[String]) -> bool:
	if sources.has(path): return sources[path]
	if path in ancestry: return false
	var next := ancestry.duplicate()
	next.append(path)
	var dependencies: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(path):
		var source: String = dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		dependencies.append(source)
		if source == "res://scripts/ember_map_loader.gd":
			sources[path] = true
			return true
	for source in dependencies:
		if source.get_extension() == "gd" and _script_extends(ResourceLoader.load(source, "Script"), "res://scripts/ember_map_loader.gd"):
			sources[path] = true
			return true
		if source.get_extension() in ["tscn", "scn"] and _has_map_source(source, sources, next):
			sources[path] = true
			return true
	sources[path] = false
	return false


static func region_ids(map_id: String, scene_directory := MAP_SCENE_DIRECTORY) -> Array[String]:
	var result: Array[String] = []
	for region in map_snapshot(map_id, scene_directory).get("regions", []):
		var region_id := str(region.get("id", ""))
		if not region_id.is_empty() and region_id not in result:
			result.append(region_id)
	result.sort()
	return result


static func region_definition(map_id: String, region_id: String, scene_directory := MAP_SCENE_DIRECTORY) -> Dictionary:
	var clean_region := region_id.strip_edges()
	if clean_region.is_empty():
		return {}
	for region in map_snapshot(map_id, scene_directory).get("regions", []):
		if str(region.get("id", "")) == clean_region:
			return region
	return {}


static func map_exists(map_id: String) -> bool:
	return not map_snapshot(map_id).is_empty()


static func map_snapshot(map_id: String, scene_directory := MAP_SCENE_DIRECTORY) -> Dictionary:
	var clean := map_id.strip_edges()
	if clean.is_empty(): return {}
	for index in clean.length():
		var character := clean.unicode_at(index)
		if not (character >= 48 and character <= 57 or character >= 65 and character <= 90
			or character >= 97 and character <= 122 or character in [45, 95]):
			return {}
	var path := scene_directory.path_join(clean + ".tscn")
	if not ResourceLoader.exists(path, "PackedScene"):
		_map_snapshots.erase(path)
		return {}
	var cached: Dictionary = _map_snapshots.get(path, {})
	if not cached.is_empty() and _snapshot_fresh(cached):
		return cached.data.duplicate(true)
	# Fresh scene state, reusable asset/script dependencies; do not replace live
	# editor Resources or reload every prefab/texture for a reference query.
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return {}
	var nodes := {}
	var signatures := {path: _scene_signature(path)}
	_saved_scene_nodes(packed.get_state(), ".", nodes, signatures, [])
	var map_path := ""
	for node_path in nodes:
		if _script_extends(nodes[node_path].get("script"), "res://scripts/ember_map_loader.gd"):
			map_path = node_path
			break
	if map_path.is_empty():
		_map_snapshots[path] = {"signatures": signatures, "data": {}}
		return {}
	var map_properties: Dictionary = nodes[map_path]
	var map_transform := _saved_transform(map_path, nodes)
	var regions: Array[Dictionary] = []
	var region_prefix := "Regions/" if map_path == "." else map_path + "/Regions/"
	for node_path in nodes:
		if not str(node_path).begins_with(region_prefix):
			continue
		var properties: Dictionary = nodes[node_path]
		if not _script_extends(properties.get("script"), "res://scripts/ember_region.gd"):
			continue
		var region_id := str(properties.get("region_id", "")).strip_edges()
		if region_id.is_empty(): continue
		var pose := map_transform.affine_inverse() * _saved_transform(node_path, nodes)
		var shape_properties: Dictionary = nodes.get(str(node_path) + "/Shape", {})
		var shape := shape_properties.get("shape") as BoxShape3D
		if shape != null and not shape.resource_path.is_empty():
			signatures[shape.resource_path] = _scene_signature(shape.resource_path)
			if not shape.resource_path.contains("::"):
				shape = ResourceLoader.load(shape.resource_path, "BoxShape3D", ResourceLoader.CACHE_MODE_IGNORE) as BoxShape3D
		regions.append({
			"id": region_id, "kind": str(properties.get("kind", "trigger")),
			"note": str(properties.get("note", "")), "position": pose.origin,
			"size": pose.basis.get_scale().abs() * shape.size if shape != null else Vector3.ZERO,
			"scriptId": str(properties.get("script_id", "")),
			"targetMapId": str(properties.get("target_map_id", "")),
			"targetRegionId": str(properties.get("target_region_id", "")),
			"repeatable": bool(properties.get("repeatable", false)),
		})
	var blocks: Vector2i = map_properties.get("authored_size_blocks", Vector2i.ZERO)
	if blocks == Vector2i.ZERO:
		var surface: Resource = map_properties.get("visual_surface")
		if surface != null:
			if not surface.resource_path.is_empty() and not surface.resource_path.contains("::"):
				signatures[surface.resource_path] = _scene_signature(surface.resource_path)
				surface = ResourceLoader.load(surface.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var size: Vector3i = surface.get("size_blocks")
			blocks = Vector2i(size.x, size.z)
	var origin: Vector3 = map_properties.get("surface_origin", Vector3.ZERO)
	var data := {"id": clean, "name": nodes.get(".", {}).get("_name", clean),
		"scenePath": path, "sizeBlocks": blocks,
		"bounds": Rect2(Vector2(origin.x, origin.z), Vector2(blocks) * 16.0), "regions": regions}
	_map_snapshots[path] = {"signatures": signatures, "data": data}
	return data.duplicate(true)


static func _scene_signature(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "packed"


static func _snapshot_fresh(snapshot: Dictionary) -> bool:
	for path in snapshot.signatures:
		if _scene_signature(path) != snapshot.signatures[path]: return false
	return true


static func _script_extends(raw: Variant, path: String) -> bool:
	var script := raw as Script
	while script != null:
		if script.resource_path == path: return true
		script = script.get_base_script()
	return false


static func _saved_scene_nodes(state: SceneState, prefix: String, nodes: Dictionary, signatures: Dictionary, ancestry: Array) -> void:
	if state == null: return
	var identity: Variant = state.get_path() if not state.get_path().is_empty() else state
	if identity in ancestry: return
	var next := ancestry.duplicate()
	next.append(identity)
	if not state.get_path().is_empty(): signatures[state.get_path()] = _scene_signature(state.get_path())
	var base := state.get_base_scene_state()
	if base != null and not base.get_path().is_empty():
		var saved_base := ResourceLoader.load(base.get_path(), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if saved_base != null: base = saved_base.get_state()
	_saved_scene_nodes(base, prefix, nodes, signatures, next)
	for index in state.get_node_count():
		var relative := str(state.get_node_path(index)).trim_prefix("./")
		var path := prefix if relative == "." else relative if prefix == "." else prefix + "/" + relative
		# Props/mesh branches are not needed for map/region metadata.
		if path.contains("/Props/") or path.ends_with("/Props") or path.contains("/Look/"): continue
		var instance := state.get_node_instance(index)
		if instance != null:
			if not instance.resource_path.is_empty():
				instance = ResourceLoader.load(instance.resource_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if instance != null: _saved_scene_nodes(instance.get_state(), path, nodes, signatures, next)
		var properties: Dictionary = nodes.get(path, {})
		properties["_name"] = str(state.get_node_name(index))
		for property_index in state.get_node_property_count(index):
			properties[str(state.get_node_property_name(index, property_index))] = state.get_node_property_value(index, property_index)
		nodes[path] = properties


static func _saved_transform(path: String, nodes: Dictionary) -> Transform3D:
	var properties: Dictionary = nodes.get(path, {})
	var local: Transform3D = properties.get("transform", Transform3D.IDENTITY)
	if properties.has("position"): local.origin = properties.position
	if properties.has("rotation"): local.basis = Basis.from_euler(properties.rotation).scaled_local(local.basis.get_scale())
	if properties.has("scale"): local.basis = local.basis.orthonormalized().scaled_local(properties.scale)
	if path == ".": return local
	var parent := path.get_base_dir()
	if parent.is_empty(): parent = "."
	return _saved_transform(parent, nodes) * local


static func _dialogue_for_id(ref_id: String, visited: Dictionary, depth: int) -> Dictionary:
	if depth >= MAX_SCRIPT_DEPTH or visited.has(ref_id):
		return {}
	visited[ref_id] = true
	var resolved := resolve_script_ref(ref_id)
	if resolved.is_empty():
		return {}
	var data: Dictionary = resolved.get("data", {})
	if str(resolved.get("kind", "")) == "scene":
		return data
	var steps: Variant = data.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return {}
	for raw_step in steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		match str(step.get("type", "")):
			"talk":
				var scene_id := str(step.get("dialogueId", ""))
				var nested := _dialogue_for_id(scene_id, visited, depth + 1)
				if not nested.is_empty():
					return nested
			"run_script":
				var nested_id := str(step.get("scriptId", ""))
				var nested := _dialogue_for_id(nested_id, visited, depth + 1)
				if not nested.is_empty():
					return nested
	return {}
