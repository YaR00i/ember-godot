@tool
extends RefCounted
## Editor-only candidate lifecycle. Prepared source/mesh/recipe are the exact
## objects published by Creation; temporary geometry is never a gameplay owner.
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const PREVIEW_META := "ember_generation_preview"
const STUDIO_PATH := "res://addons/ember_import/editor/Генерация.tscn"

var candidates: Array[Dictionary] = []
var template: Resource
var title := "Большое лиственное дерево"
var next_seed := 1
var requested := 4
var running := false
var error := ""
var _remaining := 0
var _family_id := ""
var _family_title := ""
var _serial := 0
var _candidate_serial := 0
var batch_number := 0
var preview_ids: Array[String] = []
var _batch_recipe: Resource
var _batch_title := ""
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var recipe_directory := "res://content/editor/voxel_generators"


static func preset_recipe(recipe: Resource, name := "") -> Resource:
	var result := recipe.duplicate(true)
	result.parameters = Generator.normalized_parameters(result.generator_id, result.parameters)
	result.structure = {}
	result.family_id = ""
	result.family_title = ""
	result.variation_name = "Основной"
	result.resource_name = name
	result.resource_path = ""
	return result


func begin(recipe: Resource, batch_title: String, count: int, seed: int) -> bool:
	error = ""
	var errors := Generator.validation_errors(recipe)
	if not errors.is_empty():
		error = errors[0]
		return false
	if running:
		error = "Генерация уже выполняется."
		return false
	# All recipes remain in session history. Favorites are independent of the
	# bounded working set of source/mesh previews.
	clear_previews()
	batch_number += 1
	template = preset_recipe(recipe)
	title = batch_title.strip_edges().left(160)
	if title.is_empty(): title = "Сгенерированный объект"
	_batch_recipe = template.duplicate(true)
	_batch_title = title
	next_seed = maxi(0, seed)
	requested = clampi(count, 1, Generator.candidate_limit(template))
	_remaining = requested
	running = _remaining > 0
	return running


## Called once per editor frame; cancel takes effect between complete candidates.
func step() -> Dictionary:
	if not running: return {}
	var creation := Creation.new()
	creation.source_directory = source_directory
	creation.prefab_directory = prefab_directory
	creation.recipe_directory = recipe_directory
	var recipe := _batch_recipe.duplicate(true)
	recipe.seed = next_seed
	next_seed = (next_seed + 104729) % 2147483647
	if not creation.prepare_recipe(recipe, _batch_title):
		error = creation.error
		running = false
		return {}
	if _family_id.is_empty() or _family_title != _batch_title:
		_family_id = creation.source.model_id
		_family_title = _batch_title
		_serial = 0
	creation.recipe.family_id = _family_id
	creation.recipe.family_title = _family_title
	_serial += 1
	creation.recipe.variation_name = "Вариант %d" % _serial
	_candidate_serial += 1
	var candidate := {"creation": creation, "chosen": false, "saved": false, "publication_locked": false, "node": null,
		"number": _candidate_serial, "batch": batch_number, "seed": int(recipe.seed), "name": str(creation.recipe.variation_name)}
	candidates.append(candidate)
	_remaining -= 1
	running = _remaining > 0
	return candidate


func cancel() -> void:
	running = false
	_remaining = 0


func clear() -> void:
	cancel()
	clear_previews()
	candidates.clear()
	_family_id = ""
	_family_title = ""
	_serial = 0
	_candidate_serial = 0
	batch_number = 0
	preview_ids.clear()


func preview_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in preview_ids:
		var candidate := find_candidate(id)
		if not candidate.is_empty(): result.append(candidate)
	return result


func unload_candidate(candidate: Dictionary) -> void:
	if is_instance_valid(candidate.node): candidate.node.free()
	candidate.node = null
	preview_ids.erase(str(candidate.creation.source.model_id))
	candidate.creation.unload_prepared_geometry()


func clear_previews() -> void:
	for candidate in candidates: unload_candidate(candidate)
	preview_ids.clear()


func compare_limit(candidate: Dictionary) -> int:
	var limit := Generator.candidate_limit(candidate.creation.recipe)
	for current in preview_candidates(): limit = mini(limit, Generator.candidate_limit(current.creation.recipe))
	return limit


func ensure_loaded(candidate: Dictionary) -> bool:
	if candidate.creation.packed != null: return true
	var creation: RefCounted = candidate.creation
	# Published source is canonical, including later Canvas edits. File-history
	# guards remain attached to the original Creation object, not this loader.
	if candidate.saved:
		var path: String = creation.source_directory.path_join(creation.source.model_id + ".tres")
		var prefab: String = creation.prefab_directory.path_join(creation.source.model_id + ".tscn")
		if FileAccess.file_exists(path) and FileAccess.file_exists(prefab):
			var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
			var packed := ResourceLoader.load(prefab, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
			if source != null and packed != null:
				creation.source = source
				creation.packed = packed
				creation.report["grid"] = Vector3i(source.size_blocks.x * source.normalized_density(), source.height_voxels, source.size_blocks.z * source.normalized_density())
				return true
	var prepared := Creation.new()
	prepared.source_directory = source_directory
	prepared.prefab_directory = prefab_directory
	prepared.recipe_directory = recipe_directory
	if not prepared.prepare_recipe(creation.recipe, creation.source.display_name, "", creation.source.model_id):
		error = prepared.error
		return false
	creation.source = prepared.source
	creation.packed = prepared.packed
	creation.report = prepared.report
	creation.recipe = prepared.recipe
	return true


func find_candidate(model_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.creation.source.model_id) == model_id: return candidate
	return {}


## Prepare one revision off-screen. History retains recipes, not old meshes.
func prepare_revision(candidate: Dictionary, next_recipe: Resource) -> RefCounted:
	error = ""
	if running or candidate.is_empty() or candidate.saved or bool(candidate.get("publication_locked", false)):
		error = "Настройка доступна для несохранённого варианта после окончания генерации."
		return null
	var creation := Creation.new()
	creation.source_directory = source_directory
	creation.prefab_directory = prefab_directory
	creation.recipe_directory = recipe_directory
	if not creation.prepare_recipe(next_recipe, str(candidate.creation.source.display_name), "", str(candidate.creation.source.model_id)):
		error = creation.error
		return null
	return creation


func make_preview(candidate: Dictionary, parent: Node3D, position: Vector3, world_size: float) -> Node3D:
	if not ensure_loaded(candidate): return null
	var id := str(candidate.creation.source.model_id)
	if not preview_ids.has(id): preview_ids.append(id)
	var prop := candidate.creation.packed.instantiate() as EmberVoxelProp
	prop.configure_voxel_scale(candidate.creation.source.normalized_density(), world_size)
	var preview := Node3D.new()
	preview.name = "Вариант_%d" % int(candidate.get("number", 0))
	preview.set_meta("ember_generation_candidate", str(candidate.creation.source.model_id))
	preview.position = position
	# Mesh only: no collision, script, gameplay processing, or scene ownership.
	var queue: Array[Dictionary] = [{"node": prop, "transform": prop.transform}]
	while not queue.is_empty():
		var item: Dictionary = queue.pop_back()
		var node: Node = item.node
		if node is MeshInstance3D:
			var mesh := MeshInstance3D.new()
			mesh.name = node.name
			mesh.mesh = node.mesh
			mesh.material_override = node.material_override
			mesh.cast_shadow = node.cast_shadow
			mesh.layers = node.layers
			mesh.transform = item.transform
			preview.add_child(mesh)
		for child in node.get_children():
			queue.append({"node": child, "transform": item.transform * child.transform if child is Node3D else item.transform})
	prop.free()
	# Native F centers node pivots, not the mesh bounds, and does not auto-zoom.
	# Center the temporary pivot while leaving all visible geometry in place.
	var bounds := AABB()
	var first := true
	for child in preview.get_children():
		var child_bounds: AABB = child.transform * child.get_aabb()
		bounds = child_bounds if first else bounds.merge(child_bounds)
		first = false
	var pivot := bounds.get_center()
	for child in preview.get_children(): child.position -= pivot
	preview.position += pivot
	preview.set_meta("_edit_lock_", true)
	var label := Label3D.new()
	label.name = "CandidateNumber"
	label.text = "№ %d" % int(candidate.get("number", 0))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.pixel_size = 0.006 * world_size
	label.position = Vector3(0, bounds.size.y * 0.5 + world_size * 0.4, 0)
	preview.add_child(label)
	candidate["pivot"] = pivot
	parent.add_child(preview)
	candidate.node = preview
	return preview
