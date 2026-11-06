@tool
extends Node3D
## Scene-owned single sphere. Prepared display instances are internal; authored
## props, terrain, collision and grass scatter keep their existing owners.
const Correspondence = preload("res://scripts/ember_anomaly_correspondence.gd")
const RuntimeShadowLod = preload("res://scripts/ember_runtime_shadow_lod.gd")
@export var enabled := true
@export_enum("Low poly:1", "Воксельный мир:2") var inner_look := 1:
	set(value): inner_look = clampi(value, 1, 2)
@export_range(0.1, 32.0, 0.1, "suffix:m") var radius_m := 4.5:
	set(value): radius_m = clampf(value, 0.1, 32.0) if is_finite(value) else 4.5
@export_range(0.1, 2.0, 0.05, "suffix:m") var feather_m := 0.45:
	set(value): feather_m = clampf(value, 0.1, 2.0) if is_finite(value) else 0.45
var preparation_state := "Ожидание поверхности"
var preparations := 0
var _bindings: Array[Dictionary] = []
var _completed_sources: Dictionary = {}
var _preparing := false
var _prepared := false
var _saving := false
var _field: Array = []
var _map: EmberMapLoader
var _projection: Node
var _preparation_revision := -1
var _scatter_cache:Dictionary={}
var _authoring := Engine.is_editor_hint()
var _preview_requested := false


func set_authoring_active(active: bool) -> void:
	_authoring = active
	_preview_requested = false
	if active:
		_display(false)
		preparation_state = "Редактирование земли · предпросмотр приостановлен"


func request_preview() -> void:
	_preview_requested = true


func stop_preview() -> void:
	set_authoring_active(true)


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not position.is_finite(): errors.append("Центр сферы должен быть конечной координатой")
	if not get_parent() is EmberMapLoader: errors.append("Сфера должна находиться непосредственно в Map")
	return errors


func _ready() -> void:
	_authoring = Engine.is_editor_hint()
	if _authoring: preparation_state = "Редактирование земли · предпросмотр приостановлен"
	_map = get_parent() as EmberMapLoader
	if _map == null:
		preparation_state = "Сфера должна быть дочерним узлом Map"
		set_process(false)
	else:
		_map.anomaly_materials_changed.connect(refresh_material_bindings)


func _process(_delta: float) -> void:
	if _saving or not is_instance_valid(_map): return
	if not enabled or (_authoring and not _preview_requested):
		_display(false)
		return
	_projection = _map.get_node_or_null("DerivedCompactWorldTerrain")
	if _map.world_look != 0 or _map.compact_ground_style != 1:
		_display(false)
		return
	if not is_instance_valid(_projection): return
	if _projection.pending_tile_count() > 0 or not _projection._look_pending.is_empty() or _projection._live_brush_active:
		_display(false)
		return
	if _preparing: return
	if _projection.pending_runtime_lod_count() > 0: return
	for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
		if _map.is_ancestor_of(patch) and (patch._dirty or patch._rebuilding or patch._revision != _projection.column_revision()): return
	_drop_stale_bindings()
	if not _prepared:
		_preparing = true
		_prepare.call_deferred()
		return
	_display(enabled)
	var unit := _map.imported_tile_size
	var next := [global_position, radius_m*unit, feather_m*unit, inner_look, enabled]
	if next != _field:
		_field = next
		for binding in _bindings:
			RuntimeShadowLod.forward_instance_parameter(binding.visual,"ember_anomaly_sphere", Vector4(global_position.x, global_position.y, global_position.z, radius_m*unit if enabled else 0.0))
			RuntimeShadowLod.forward_instance_parameter(binding.visual,"ember_anomaly_band_look", Vector2(feather_m*unit, inner_look))
	for binding in _bindings:
		if binding.overlay and binding.visual.material_overlay != binding.source.material_overlay:
			binding.visual.material_overlay = binding.source.material_overlay
		if binding.transform != binding.source.global_transform:
			binding.transform = binding.source.global_transform
			for material: ShaderMaterial in binding.materials:
				if binding.source.get_parent() is EmberVoxelProp:binding.source.get_parent().bind_pattern_size(material)
				if material.get_meta("ember_detailed_depth",false):
					material.set_shader_parameter("solid_depth_world_to_local",Projection(binding.source.global_transform.affine_inverse()))
				load("res://scripts/ember_solid_material_layers.gd").sync_scale(material,binding.source)


func _prepare() -> void:
	_scatter_cache.clear()
	_drop_stale_bindings(true)
	preparations += 1
	_preparation_revision = _projection.column_revision()
	preparation_state = "Подготовка обликов"
	for key: Vector2i in _projection._look_meshes.keys():
		if not is_inside_tree(): return
		var source: MeshInstance3D = _projection._tiles[key].get_node("Ground")
		if source.mesh.get_surface_count() == 0: continue
		if _bound(source): continue
		var meshes: Dictionary = await _projection.prepared_anomaly_meshes(key,self)
		if meshes.is_empty() or not anomaly_preparation_valid(): _cancel_preparation(); return
		await _add(source,meshes[1],meshes[2],{"aligned_low":true,"aligned_voxel":true,"base":meshes[0]})
		if not anomaly_preparation_valid(): _cancel_preparation(); return
		_completed_sources[source] = true
		# Cache hits must yield as well: a warm map used to publish all tiles
		# in one blocking frame. GPU objects stay on the main thread.
		await get_tree().process_frame
		if not anomaly_preparation_valid(): _cancel_preparation(); return
	for prop in _map.find_children("*", "Node3D", true, false):
		if not is_instance_valid(prop) or not prop is EmberVoxelProp: continue
		var source := prop.get_node_or_null("Mesh") as MeshInstance3D
		if source == null or not source.mesh is ArrayMesh: continue
		if _bound(source): continue
		var external: bool = prop._external_active
		if source.mesh.get_surface_count() == 0 or (not external and source.mesh.surface_get_name(0) not in ["solid_surface","tree_bark"]): continue
		# The existing owner prepares and caches both endpoints. This atomic
		# sequence happens before publication, never on sphere input.
		prop.set_world_look(1)
		var low: ArrayMesh = source.mesh
		prop.set_world_look(2)
		var voxel: ArrayMesh = source.mesh
		prop.set_world_look(0)
		external = prop._external_active
		if source.mesh.surface_get_name(0) == "solid_surface" or source.mesh.get_surface_count() == 1:
			var materials: Array = []
			if external:
				var adapter := load("res://scripts/ember_external_mesh_surface.gd").anomaly_material(source.get_active_material(0),voxel.surface_get_material(0)) as ShaderMaterial
				if adapter == null:continue
				materials.append(adapter)
			var carrier := await Correspondence.carrier(source.mesh,voxel,self,external)
			if carrier == null or not is_instance_valid(source): _cancel_preparation(); return
			await _add(source,low,voxel,{"aligned_voxel":true,"base":carrier,"materials":materials})
		else:
			var resource := load("res://content/voxel_models/%s.tres" % prop.model_id) as EmberVoxelModelResource
			var meshes: Dictionary = await load("res://scripts/ember_tree_look_bake.gd").anomaly_meshes(resource.to_definition(true).model,source.mesh,voxel,self)
			if meshes.is_empty() or not is_instance_valid(source): _cancel_preparation(); return
			await _add(source,low,meshes.target,{"aligned_voxel":true,"base":meshes.base,"shrink_surface":1})
			await _add(source,meshes.cells,meshes.cells,{"base":meshes.cells,"grow_cells":true,"materials":[meshes.cells.surface_get_material(0)]})
		if not anomaly_preparation_valid(): _cancel_preparation(); return
		_completed_sources[source] = true
		await get_tree().process_frame
		if not anomaly_preparation_valid(): _cancel_preparation(); return
	for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
		if not _map.is_ancestor_of(patch) or patch._visual == null: continue
		if _bound(patch._visual): continue
		if patch.detail_kind == 3:
			# Textured flower cover keeps its cards and artwork in all regions.
			await _add(patch._visual,patch.prepared_look_mesh(1),patch.prepared_look_mesh(2),{"aligned_low":true,"aligned_voxel":true})
			_completed_sources[patch._visual] = true
			await get_tree().process_frame
			if not anomaly_preparation_valid(): _cancel_preparation(); return
			continue
		await _add(patch._visual,patch.prepared_look_mesh(1),patch._visual.multimesh.mesh,{"aligned_voxel":patch.detail_kind == 0,"grass_form":1})
		# The existing root transition shrinks the small decoration into a voxel region.
		# No voxel duplicate is prepared for stones; large props keep their normal path.
		if patch.is_detail_stone():
			_completed_sources[patch._visual] = true
			continue
		var slot: int = _projection.document.palette_surface_roles.find("grass")
		var cells: ArrayMesh = patch.prepared_coloured_look_mesh(2,slot)
		# Keep the authored scatter intact. Only its expensive voxel display is
		# grouped for spatial culling; sphere motion never changes any instance.
		var groups: Dictionary = {}
		var original: MultiMesh = patch._visual.multimesh
		for i in original.instance_count:
			var root: Vector3 = patch._visual.to_global(original.get_instance_transform(i).origin)
			var key := Vector2i(floori(root.x/(_map.imported_tile_size*4.0)),floori(root.z/(_map.imported_tile_size*4.0)))
			if not groups.has(key): groups[key] = PackedInt32Array()
			groups[key].append(i)
		for indices: PackedInt32Array in groups.values():
			await _add(patch._visual,cells,cells,{"base":cells,"grass_form":2,"indices":indices})
			if not anomaly_preparation_valid(): _cancel_preparation(); return
			await get_tree().process_frame
		if not anomaly_preparation_valid(): _cancel_preparation(); return
		_completed_sources[patch._visual] = true
	if not is_inside_tree(): return
	_preparing = false
	_prepared = true
	preparation_state = "Готово"
	_field.clear()
	refresh_material_bindings()


func anomaly_preparation_valid() -> bool:
	return is_inside_tree() and enabled and (not _authoring or _preview_requested) and is_instance_valid(_projection) and not _projection._live_brush_active and _projection == _map.get_node_or_null("DerivedCompactWorldTerrain") and _projection.column_revision() == _preparation_revision and _map.world_look == 0


func _cancel_preparation() -> void:
	_display(false)
	_drop_stale_bindings()
	_prepared = false
	_preparing = false
	preparation_state = "Редактирование земли · предпросмотр приостановлен" if _authoring and not _preview_requested else "Поверхность изменена; повторная подготовка"


func _bound(source: GeometryInstance3D) -> bool:
	return _completed_sources.has(source)


func _drop_stale_bindings(include_incomplete := false) -> void:
	for i in range(_bindings.size()-1,-1,-1):
		var binding: Dictionary = _bindings[i]
		if is_instance_valid(binding.source) and _mesh_of(binding.source) == binding.mesh and (not binding.source is MultiMeshInstance3D or binding.source.multimesh == binding.scatter) and (not include_incomplete or _completed_sources.has(binding.source)): continue
		_completed_sources.erase(binding.source)
		if is_instance_valid(binding.source): binding.source.layers = binding.layers
		if is_instance_valid(binding.visual): binding.visual.queue_free()
		_bindings.remove_at(i)
		_prepared = false


func _mesh_of(source: GeometryInstance3D) -> Mesh:
	return source.mesh if source is MeshInstance3D else source.multimesh.mesh if source is MultiMeshInstance3D and source.multimesh != null else null


func _add(source: GeometryInstance3D, low: ArrayMesh, voxel: ArrayMesh, options: Dictionary = {}) -> void:
	var carrier: ArrayMesh = options.get("base")
	var aligned_low: bool = options.get("aligned_low",false)
	var aligned_voxel: bool = options.get("aligned_voxel",false)
	var grow_cells: bool = options.get("grow_cells",false)
	var grass_form: int = options.get("grass_form",0)
	var shrink_surface: int = options.get("shrink_surface",-1)
	var material_sources: Array = options.get("materials",[])
	var original_mesh := _mesh_of(source) as ArrayMesh
	var mesh := carrier if carrier != null else original_mesh
	if mesh == null or low.get_surface_count() == 0 or voxel.get_surface_count() == 0: return
	var targets: Array[Texture2D] = []
	var needs_targets := not grow_cells and grass_form != 2
	if needs_targets: targets = await Correspondence.prepare(mesh, low, voxel, self, aligned_low, aligned_voxel)
	if (targets.is_empty() and needs_targets) or not is_inside_tree() or not is_instance_valid(source): return
	var visual: GeometryInstance3D
	if source is MultiMeshInstance3D:
		var instanced := MultiMeshInstance3D.new()
		instanced.multimesh = await _grass_scatter(source.multimesh,source,mesh,options.get("indices",PackedInt32Array()))
		if instanced.multimesh == null: instanced.free(); return
		visual = instanced
	else:
		var single := MeshInstance3D.new()
		single.mesh = mesh
		visual = single
	visual.name = "DerivedAnomalyLook"
	visual.cast_shadow = source.cast_shadow
	visual.layers = source.layers
	visual.visible = false
	# Keep editor picking and transform ownership on the original prop/patch,
	# rather than making every displayed object a child of the sphere.
	source.add_child(visual, false, Node.INTERNAL_MODE_BACK)
	visual.global_transform = source.global_transform
	if visual is MultiMeshInstance3D:
		var extent := source.global_basis.inverse()*Vector3.UP*float(visual.multimesh.get_meta("anomaly_root_extent",0.0))
		var bounds: AABB = visual.get_aabb() if options.has("indices") else source.get_aabb().merge(visual.get_aabb())
		visual.custom_aabb = bounds.grow(extent.abs()[extent.abs().max_axis_index()])
	else:
		visual.custom_aabb = mesh.get_aabb().merge(low.get_aabb()).merge(voxel.get_aabb())
	var materials: Array[ShaderMaterial] = []
	var originals: Array[ShaderMaterial] = []
	for surface in mesh.get_surface_count():
		var original: ShaderMaterial = material_sources[surface] if not material_sources.is_empty() else source.material_override if source.material_override != null else source.get_active_material(surface)
		if original == null:
			visual.free(); return
		var material := original.duplicate() as ShaderMaterial
		material.set_shader_parameter("ember_anomaly_prepared", true)
		if needs_targets: material.set_shader_parameter("ember_anomaly_targets", targets[surface])
		material.set_shader_parameter("ember_anomaly_shrink_cards", surface == shrink_surface)
		material.set_shader_parameter("ember_anomaly_grow_cells", grow_cells)
		material.set_shader_parameter("ember_anomaly_grass_roots", source is MultiMeshInstance3D)
		material.set_shader_parameter("ember_anomaly_grass_form", grass_form)
		if visual is MeshInstance3D: visual.set_surface_override_material(surface, material)
		else: visual.material_override = material
		materials.append(material)
		originals.append(original)
	_bindings.append({"source": source, "visual": visual, "mesh": original_mesh, "scatter":source.multimesh if source is MultiMeshInstance3D else null, "transform":source.global_transform, "overlay":not grow_cells and grass_form != 2, "voxel_only":grow_cells or grass_form == 2, "layers": source.layers, "materials": materials, "originals":originals, "alternate":not material_sources.is_empty()})


func refresh_material_bindings() -> void:
	for binding in _bindings:
		if not is_instance_valid(binding.source) or not is_instance_valid(binding.visual): continue
		for surface in binding.materials.size():
			var original: ShaderMaterial = binding.originals[surface] if binding.alternate else binding.source.material_override if binding.source.material_override != null else binding.source.get_active_material(surface)
			if original == null: continue
			var material: ShaderMaterial = binding.materials[surface]
			material.shader = original.shader
			for property in original.get_property_list():
				var property_name := str(property.name)
				if not property_name.begins_with("shader_parameter/"): continue
				var key := property_name.trim_prefix("shader_parameter/")
				if key.begins_with("ember_anomaly_"): continue
				material.set_shader_parameter(key,original.get_shader_parameter(key))
			if binding.source.get_parent() is EmberVoxelProp:binding.source.get_parent().bind_pattern_size(material)
			var local_units := 1.0 if binding.source.get_parent() is EmberVoxelProp else _map.imported_tile_size
			_map.bind_voxel_light(material, -1, local_units, true)
			var depth_units: float = binding.source.get_parent().block_world_size / load("res://scripts/ember_voxel_solid_surface.gd").AUTHORED_BLOCK_M if binding.source.get_parent() is EmberVoxelProp else _map.imported_tile_size
			_map.bind_material_depth_distance(material, depth_units)


func _grass_scatter(original: MultiMesh, visual: MultiMeshInstance3D, mesh: ArrayMesh, indices := PackedInt32Array()) -> MultiMesh:
	var cache_key := [original.get_instance_id(),visual.global_transform,_projection.column_revision(),_map._solid_navigation_revision()]
	if not _preparing or _scatter_cache.get("key")!=cache_key:
		var input:=original.buffer
		var stride:=12+(4 if original.use_colors else 0)+(4 if original.use_custom_data else 0)
		var roots:=PackedVector3Array();roots.resize(original.instance_count)
		var local_roots:=PackedVector3Array();local_roots.resize(original.instance_count)
		var fixed:=PackedByteArray();fixed.resize(original.instance_count)
		var fields:Dictionary={};var started:=Time.get_ticks_usec()
		var bounds:=AABB()
		for i in original.instance_count:
			var root:=visual.to_global(Vector3(input[i*stride+3],input[i*stride+7],input[i*stride+11]))
			roots[i]=root
			bounds=AABB(root,Vector3.ZERO) if i==0 else bounds.expand(root)
		var candidates:=_map._solid_floor_candidates(bounds)
		for i in original.instance_count:
			if i%32==0 and Time.get_ticks_usec()-started>3000:
				await get_tree().process_frame
				if not is_instance_valid(visual) or visual.multimesh!=original or (_preparing and not anomaly_preparation_valid()):return null
				started=Time.get_ticks_usec()
			var root:=roots[i]
			if not candidates.is_empty():
				var support:=_map._solid_floor_sample(root,candidates)
				if support.has("object") and absf(support.position.y-root.y)<0.04*_map.imported_tile_size:fixed[i]=1;continue
			var local:Vector3=_projection.to_local(root);local_roots[i]=local
			var cell:=Vector2i(clampi(floori(local.x),0,_projection.document.width-1),clampi(floori(local.z),0,_projection.document.depth-1))
			var tile:=Vector2i(cell.x/64,cell.y/64)
			if not fields.has(tile):fields[tile]=_projection._smooth_field(tile)

		var job=load("res://scripts/prototypes/ember_terrain_look_bake.gd").AnomalyJob.new()
		job.work=Correspondence.scatter_values.bind(input,stride,roots,local_roots,fixed,fields,_projection.document.working_copy(),_projection.global_transform)
		var tree:=get_tree();var task:=WorkerThreadPool.add_task(job.run,false,"Ember anomaly vegetation")
		if task<0:return null
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
			if not is_instance_valid(visual) or visual.multimesh!=original or not is_inside_tree() or (_preparing and not anomaly_preparation_valid()):
				job.cancellation.set_cancelled(true);WorkerThreadPool.wait_for_task_completion(task);return null
		WorkerThreadPool.wait_for_task_completion(task)
		if job.result.is_empty():return null
		_scatter_cache={"key":cache_key,"buffer":job.result.buffer,"extent":job.result.extent}
	var scatter:=MultiMesh.new();scatter.transform_format=MultiMesh.TRANSFORM_3D;scatter.use_custom_data=true;scatter.mesh=mesh
	scatter.instance_count=original.instance_count if indices.is_empty() else indices.size()
	var values:PackedFloat32Array=_scatter_cache.buffer
	if not indices.is_empty():
		var subset:=PackedFloat32Array();subset.resize(indices.size()*16)
		for i in indices.size():
			for column in 16:subset[i*16+column]=values[indices[i]*16+column]
		values=subset
	scatter.buffer=values
	scatter.set_meta("anomaly_root_extent",_scatter_cache.extent)
	return scatter


func _display(active: bool) -> void:
	var intersecting: Dictionary = {}
	var visible_parts: Dictionary = {}
	if active:
		var reach := (radius_m+feather_m)*_map.imported_tile_size
		for binding in _bindings:
			if not is_instance_valid(binding.source) or not is_instance_valid(binding.visual): continue
			# Union all endpoints, including expanded grass roots. The original
			# owner can draw outside the field; don't shade collapsed geometry.
			if binding.voxel_only and inner_look != 2: continue
			var bounds: AABB = binding.source.global_transform*binding.visual.custom_aabb
			var closest := global_position.clamp(bounds.position,bounds.end)
			if closest.distance_squared_to(global_position) <= reach*reach:
				intersecting[binding.source] = true
				visible_parts[binding.visual] = true
	for binding in _bindings:
		if not is_instance_valid(binding.source) or not is_instance_valid(binding.visual): continue
		var affected: bool = active and intersecting.has(binding.source)
		var layers: int = 0 if affected else binding.layers
		if binding.source.layers != layers: binding.source.layers = layers
		binding.visual.visible = affected and binding.source.is_visible_in_tree() and (not binding.voxel_only or visible_parts.has(binding.visual))


func _clear() -> void:
	_scatter_cache.clear()
	_display(false)
	for binding in _bindings:
		if is_instance_valid(binding.visual): binding.visual.queue_free()
	_bindings.clear()
	_completed_sources.clear()
	_prepared = false
	_field.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saving = true
		_display(false)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_saving = false
	elif what == NOTIFICATION_EXIT_TREE:
		_clear()
