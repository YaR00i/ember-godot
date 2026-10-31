@tool
extends RefCounted
## Adapter for existing stamp sources. Workers build CPU buffers; only prepare() uploads meshes.
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Preset = preload("res://addons/ember_import/ember_voxel_stamp_preset.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Vox = preload("res://scripts/vox_mesher.gd")
const CONTRACT := "detail-part-stamp-v2"
static var _cache: Dictionary = {}
static var _jobs: Dictionary = {}
static var _validated: Dictionary = {}
static var builds := 0

static func validation_errors(preset: Resource) -> Array[String]:
	if not preset is Preset: return ["Выберите объёмный пресет."]
	var values := _validation_values(preset)
	var id := preset.get_instance_id()
	var saved: Dictionary = _validated.get(id,{})
	if not values.is_empty() and not saved.is_empty() and saved.source.get_ref() == preset and saved.values == values: return []
	var errors := _validate(preset)
	if errors.is_empty() and not values.is_empty():
		if _validated.size() >= 8: _validated.erase(_validated.keys()[0])
		_validated[id] = {"source":weakref(preset),"values":values.duplicate(true)}
	return errors

static func _validation_values(preset: Resource) -> Array:
	if preset.geometry == null: return []
	# File-backed surface validation can depend on more than stored values.
	if not preset.geometry.external_surface.is_empty() or not preset.geometry.tree_surface.is_empty(): return []
	var values: Array = [preset.kind, _stored_values(preset.geometry)]
	if preset.generator_recipe != null: values.append(_stored_values(preset.generator_recipe))
	return values

static func _stored_values(resource: Resource) -> Array:
	# Native equality compares packed channels; the saved deep dictionary/array
	# snapshot keeps their COW buffers. This also catches edits without changed.
	var values: Array = [resource.get_script()]
	for property: Dictionary in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values.append([property.name, resource.get(property.name)])
	return values

static func _validate(preset: Resource) -> Array[String]:
	var error := Stamp._preset_validation_error(preset)
	if not error.is_empty(): return [error]
	if preset.kind == Preset.KIND_VOLUME:
		if preset.geometry.solid_surface.is_empty(): return ["Для этого набора ещё не подключены три облика кисти."]
		var errors := Solid.validation_errors(preset.geometry.solid_surface,preset.geometry.merge_parts.size(),preset.geometry.palette.size())
		if not errors.is_empty(): return errors
	elif preset.kind == Preset.KIND_GENERATED_VOLUME and preset.generator_recipe.generator_id == "rock":
		var settings := Generator.normalized_parameters("rock", preset.generator_recipe.parameters)
		if int(settings.get("rock_type",0)) > 2: return ["Составные скалы и кристаллы требуют своего профиля обликов."]
	else: return ["Для этого набора ещё не подключены три облика кисти."]
	if preset.geometry.grid_size().y < 2: return ["Плоский след не является объёмным набором."]
	return []

static func choices(reload_saved := false, directory := Stamp.DIRECTORY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in Stamp.library(directory):
		if reload_saved:
			# Refresh data Resources only; deep replacement would also reload live editor scripts.
			var saved: Resource = ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			for resource: Resource in [saved.geometry,saved.generator_recipe]:
				if resource != null and not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
					ResourceLoader.load(resource.resource_path,"",ResourceLoader.CACHE_MODE_REPLACE)
		var preset: Resource = ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_REPLACE if reload_saved else ResourceLoader.CACHE_MODE_REUSE)
		if reload_saved: preset.emit_changed()
		var errors := validation_errors(preset)
		row["supported"] = errors.is_empty()
		row["reason"] = "" if errors.is_empty() else errors[0]
		result.append(row)
	return result

static func key(preset: Resource) -> String:
	if not validation_errors(preset).is_empty(): return ""
	var geometry: EmberVoxelModelResource = preset.geometry
	return "%s|%s|%s|%d|%s|%s|%s" % [CONTRACT, Generator.variant_cache_key(preset.generator_recipe,geometry), geometry.grid_size(),geometry.normalized_density(),geometry.model_id,hash([geometry.voxels,geometry.palette,geometry.material]),hash([geometry.voxel_part_ids,geometry.solid_surface])]

static func variant_count(preset: Resource) -> int:
	if preset.kind != Preset.KIND_GENERATED_VOLUME: return 1
	return int(Generator.normalized_parameters(preset.generator_recipe.generator_id,preset.generator_recipe.parameters).get("variant_count",1))

static func ready(preset: Resource) -> bool:
	return _cache.has(key(preset))

static func cached(preset: Resource) -> Dictionary:
	return _cache.get(key(preset), {})

static func prepare(preset: Resource, host: Node) -> Dictionary:
	var errors := validation_errors(preset)
	if not errors.is_empty(): return {"error": errors[0]}
	var signature := key(preset)
	if _cache.has(signature): return _cache[signature]
	if not _jobs.has(signature):
		var job := Job.new(); job.source = preset.duplicate(true)
		# External Resources can remain shared after duplicate(true).
		job.source.geometry = preset.geometry.duplicate_model()
		if preset.generator_recipe != null: job.source.generator_recipe = preset.generator_recipe.duplicate(true)
		job.builder = geometry_model
		var id := WorkerThreadPool.add_task(job.run, false, "Ember detail pattern")
		_jobs[signature] = {"job":job,"id":id}; builds += 1
	var pending: Dictionary = _jobs[signature]
	# Another waiter can publish and release the task before this coroutine resumes.
	while not _cache.has(signature) and not WorkerThreadPool.is_task_completed(pending.id):
		if not is_instance_valid(host) or not host.is_inside_tree(): return {"error":"Подготовка отменена."}
		await host.get_tree().process_frame
	# A different waiter may already have published the same completed job.
	if _cache.has(signature): return _cache[signature]
	WorkerThreadPool.wait_for_task_completion(pending.id)
	var data: Dictionary = pending.job.result
	_jobs.erase(signature)
	if data.has("error"): return data
	var variants: Array[Dictionary] = []
	for entry: Dictionary in data.variants:
		var meshes: Array[ArrayMesh] = []
		for arrays: Array in entry.arrays:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_name(0,"detail_pattern")
			meshes.append(mesh)
		variants.append({"meshes":meshes,"palette":entry.palette,"source_hash":entry.source_hash})
	var prepared := {"variants":variants,"key":signature,"cpu_ms":data.cpu_ms}
	if _cache.size() >= 8: _cache.erase(_cache.keys()[0])
	_cache[signature] = prepared
	return prepared

static func geometry_model(resource: EmberVoxelModelResource) -> Dictionary:
	# Add guides only to this private rendering snapshot. Original voxel/part data stay intact.
	var model: Dictionary = resource.to_definition(true).model
	if not resource.solid_surface.is_empty():
		# Support distances follow edited occupied cells; unowned additions use the exact voxel fallback.
		model.solidSurface.occupancy = Solid.occupancy_hash(resource.voxels)
		return model
	var ids := PackedInt32Array(); ids.resize(resource.voxels.size())
	for i in ids.size(): ids[i] = 1 if resource.voxels[i] > 0 else 0
	var directions := PackedVector3Array()
	for z in range(-1,2):
		for y in range(-1,2):
			for x in range(-1,2):
				if x != 0 or y != 0 or z != 0: directions.append(Vector3(x,y,z).normalized())
	var roles := PackedStringArray(); roles.resize(resource.palette.size())
	var material_ids := roles.duplicate()
	model.voxelPartIds = ids
	model.solidSurface = {"version":1,"parts":[directions],"occupancy":Solid.occupancy_hash(resource.voxels),"roles":roles,"material_ids":material_ids}
	return model

class Job extends RefCounted:
	var source: Resource
	var builder: Callable
	var result: Dictionary = {}
	func run() -> void:
		var started := Time.get_ticks_usec()
		var generated := Stamp.prepare_generated_variants(source)
		if generated.has("error"): result = generated; return
		var variants: Array[Dictionary] = []
		for resource: EmberVoxelModelResource in generated.variants:
			var model: Dictionary = builder.call(resource)
			var voxel := Solid.voxel_geometry(model)
			var geometries: Array[Array]
			if Solid.active(model):
				var worker := Solid.LivingFaces.new(); worker.prepare_field(model)
				var pulls := PackedFloat32Array(); pulls.resize(resource.palette.size()); pulls.fill(0.5 / resource.normalized_density() if source.kind == Preset.KIND_VOLUME else 2.0 / resource.normalized_density())
				var living := Solid.living_geometry(model, 1.0, pulls, worker)
				var hull := Solid.hull_geometry(model)
				if living.is_empty() or hull.is_empty(): result = {"error":"Не удалось подготовить объёмный набор."}; return
				geometries = [living.arrays,hull,voxel]
			else:
				geometries = [voxel.duplicate(true),voxel.duplicate(true),voxel]
			if voxel.is_empty(): result = {"error":"У пресета нет объёмной геометрии."}; return
			var vertices: PackedVector3Array = voxel[Mesh.ARRAY_VERTEX]
			var low := vertices[0]; var high := low
			for point in vertices: low = low.min(point); high = high.max(point)
			var pivot := Vector3((low.x+high.x)*0.5,low.y,(low.z+high.z)*0.5)
			for arrays: Array in geometries:
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in points.size(): points[i] -= pivot
				arrays[Mesh.ARRAY_VERTEX] = points
				for channel in range(Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM3+1): arrays[channel] = null
			variants.append({"arrays":geometries,"palette":resource.palette.duplicate(),"source_hash":resource.voxels.hex_encode().sha256_text()})
		result = {"variants":variants,"cpu_ms":(Time.get_ticks_usec()-started)/1000.0}
