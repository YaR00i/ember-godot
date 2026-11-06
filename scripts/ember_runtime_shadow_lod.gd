extends RefCounted
## Native shadow geometry only: identical mesh/materials, independent LOD bias.
## No shadow cache, replacement hull, caster layers or per-object process callback.
const FAR_METRES := 48.0
const RETURN_METRES := 42.0
const SHADOW_LOD_BIAS := 0.35
const DERIVED_PROXY_META := &"ember_runtime_shadow_proxy"
const SOURCE_BINDING_META := &"ember_runtime_shadow_binding"
static var _lod_meshes: Dictionary = {}
var proxy: MeshInstance3D
var _source: MeshInstance3D
var _cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
var _resources: Array[Resource] = []
var _parameter_materials: Array[Material] = []
var _parameter_names: Dictionary = {}
var _instance_values: Dictionary = {}
var _parameter_defaults: Dictionary = {}
var _parameters_dirty := true
var _parameter_rebuilds := 0
var _explicitness_scans := 0
var _parameter_getters := 0
var _default_getters := 0
var _receiver_bounds := AABB()
var _receiver_transform := Transform3D.IDENTITY
var _receiver_layers := 0


static func forward_instance_parameter(visual: GeometryInstance3D, name: StringName, value: Variant) -> void:
	if not is_instance_valid(visual): return
	# The existing source owner remains authoritative, including without a proxy.
	visual.set_instance_shader_parameter(name, value)
	if not visual.has_meta(SOURCE_BINDING_META): return
	var reference: WeakRef = visual.get_meta(SOURCE_BINDING_META)
	var binding = reference.get_ref() if reference != null else null
	if binding != null and binding._source == visual: binding._forward_parameter(name, value)


static func invalidate_instance_parameters(visual: GeometryInstance3D) -> void:
	if not is_instance_valid(visual): return
	if not visual.has_meta(SOURCE_BINDING_META): return
	var reference: WeakRef = visual.get_meta(SOURCE_BINDING_META)
	var binding = reference.get_ref() if reference != null else null
	# External raw setters explicitly restore the original caster. The next
	# ordinary admission takes one fresh snapshot, without an invisible poll.
	if binding != null and binding._source == visual: binding.restore()


static func _forget_mesh(id: int) -> void:
	_lod_meshes.erase(id)


static func has_lods(mesh: ArrayMesh) -> bool:
	var id := mesh.get_instance_id()
	if not _lod_meshes.has(id):
		var found := false
		for surface: Dictionary in mesh.get("_surfaces"):
			if not surface.get("lods", {}).is_empty(): found = true
		_lod_meshes[id] = found
		var invalidate := _forget_mesh.bind(id)
		if not mesh.changed.is_connected(invalidate): mesh.changed.connect(invalidate)
	return _lod_meshes[id]


static func receiver_area(bounds: AABB) -> Rect2:
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))


static func shadow_area(bounds: AABB, direction: Vector3, floor_y: float) -> Rect2:
	var area := receiver_area(bounds)
	var travel := maxf(0.0, bounds.end.y - floor_y) / -direction.y
	return area.merge(Rect2(area.position + Vector2(direction.x, direction.z) * travel, area.size))


static func context(map: Node3D, camera: Camera3D, lights: Array, anchors: Array[Vector3]) -> Dictionary:
	if Engine.is_editor_hint() or not is_instance_valid(camera) or camera.get_world_3d() != map.get_world_3d(): return {}
	var terrain: Resource = map.get("compact_terrain")
	if terrain == null or map.global_basis.y.normalized().dot(Vector3.UP) < 0.999: return {}
	var unit: float = map.call("_physics_activity_unit")
	var cell: float = map.get("imported_tile_size") / 16.0
	# All legal terrain heights are non-negative. Include a two-cell form margin.
	var floor_y := (map.global_transform * Vector3(0, (terrain.get("origin_y") - 2) * cell, 0)).y
	var sun: DirectionalLight3D
	var local_lights: Array = []
	var signature: Array = [floor_y, unit, map.get_world_3d().get_instance_id()]
	for light: Light3D in lights:
		if not is_instance_valid(light) or not light.is_inside_tree() or light.get_world_3d() != map.get_world_3d(): continue
		if not light.is_visible_in_tree() or not light.shadow_enabled or light.light_energy <= 0.0: continue
		signature.append([light.get_instance_id(), light.global_transform, light.shadow_caster_mask, light.light_cull_mask])
		if light is DirectionalLight3D:
			if sun != null: return {} # Multiple directional shadow owners: native full.
			sun = light
		else:
			var radius: float = light.omni_range if light is OmniLight3D else light.spot_range if light is SpotLight3D else INF
			local_lights.append([light.global_position, radius, light.shadow_caster_mask])
			signature.append(radius)
	if sun == null: return {}
	var direction := -sun.global_basis.z.normalized()
	if direction.y > -0.25: return {} # Low/unknown sun: long shadows retain full geometry.
	var forward := -camera.global_basis.z.normalized()
	if forward.y >= -0.05 or camera.global_position.y <= floor_y: return {}
	var ground := camera.global_position + forward * ((floor_y - camera.global_position.y) / forward.y)
	var start := Vector2(camera.global_position.x, camera.global_position.z)
	var finish := Vector2(ground.x, ground.z)
	var areas: Array[Rect2] = [Rect2(start.min(finish), (finish - start).abs())]
	for point in anchors: areas.append(Rect2(Vector2(point.x, point.z), Vector2.ZERO))
	# Quantized bounds keep small camera motion cheap; margin protects the true 20m area.
	var receivers: Array[Rect2] = []
	var grid := 4.0 * unit
	for area in areas:
		area = area.grow(24.0 * unit)
		var begin := (area.position / grid).floor() * grid
		var end := (area.end / grid).ceil() * grid
		receivers.append(Rect2(begin, end - begin))
	return {"signature": signature, "receivers": receivers, "direction": direction,
		"floor_y": floor_y, "unit": unit, "camera": camera.global_position,
		"locals": local_lights, "sun_mask": sun.shadow_caster_mask}


func restore() -> void:
	# Publish the original caster first. Never leave a shadowless handover frame.
	if is_instance_valid(_source):
		var reference: WeakRef = _source.get_meta(SOURCE_BINDING_META) if _source.has_meta(SOURCE_BINDING_META) else null
		if reference != null and reference.get_ref() == self: _source.remove_meta(SOURCE_BINDING_META)
		if _source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: _source.cast_shadow = _cast
		if _source.visibility_changed.is_connected(_visibility_changed): _source.visibility_changed.disconnect(_visibility_changed)
		if _source.tree_exiting.is_connected(restore): _source.tree_exiting.disconnect(restore)
		if _source.property_list_changed.is_connected(_parameters_changed): _source.property_list_changed.disconnect(_parameters_changed)
	for resource in _resources:
		if is_instance_valid(resource) and resource.changed.is_connected(restore): resource.changed.disconnect(restore)
	_resources.clear()
	_parameter_materials.clear()
	_parameter_names.clear()
	_instance_values.clear()
	_parameter_defaults.clear()
	_parameters_dirty = true
	if is_instance_valid(proxy):
		proxy.hide()
		proxy.queue_free()
	proxy = null
	_source = null


func _visibility_changed() -> void:
	if is_instance_valid(proxy) and is_instance_valid(_source): proxy.visible = _source.visible


func _watch(resource: Resource) -> void:
	if resource == null or resource in _resources: return
	_resources.append(resource)
	resource.changed.connect(restore)
	if resource is ShaderMaterial: _watch(resource.shader)
	if resource is Material: _watch(resource.next_pass)


func _parameters_changed() -> void:
	# Source notification only; never rebuild recursively inside a native getter.
	_parameters_dirty = true


func _scan_explicit(source: MeshInstance3D) -> Array[Dictionary]:
	_explicitness_scans += 1
	return source.get_property_list()


func _rebuild_parameters(source: MeshInstance3D, materials: Array[Material]) -> void:
	_parameter_rebuilds += 1
	_parameter_materials = materials
	_parameter_names.clear()
	_parameter_defaults.clear()
	var snapshot: Dictionary = {}
	var properties := _scan_explicit(source)
	for property: Dictionary in properties:
		var path := str(property.name)
		if not path.begins_with("instance_shader_parameters/"): continue
		var name := StringName(path.trim_prefix("instance_shader_parameters/"))
		_parameter_names[property.name] = name
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0:
			_parameter_getters += 1
			snapshot[name] = source.get_instance_shader_parameter(name)
		for root_material in materials:
			var material := root_material
			while material != null:
				if material is ShaderMaterial and material.shader != null:
					_default_getters += 1
					var value: Variant = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), name)
					if value != null:
						if int(property.type) == TYPE_COLOR and value is Vector4: value = Color(value.x, value.y, value.z, value.w)
						_parameter_defaults[name] = value
						break
				material = material.next_pass
			if _parameter_defaults.has(name): break
	# A getter's incidental notification must not cause another stable-poll scan.
	_parameters_dirty = false
	for name in _instance_values.keys():
		if not snapshot.has(name):
			proxy.set_instance_shader_parameter(name, null)
			_instance_values.erase(name)
	for name in snapshot: _forward_parameter(name, snapshot[name])


func _sync_instance_parameters(source: MeshInstance3D, materials: Array[Material]) -> void:
	if _parameters_dirty or materials != _parameter_materials: _rebuild_parameters(source, materials)
	# Stable sweeps do not query RenderingServer values or property lists.


func _forward_parameter(name: StringName, value: Variant) -> void:
	if not is_instance_valid(proxy) or _parameters_dirty: return
	if not _parameter_names.has(StringName("instance_shader_parameters/" + str(name))): return
	if value == null or (_parameter_defaults.has(name) and value == _parameter_defaults[name]):
		if _instance_values.has(name):
			proxy.set_instance_shader_parameter(name, null)
			_instance_values.erase(name)
	elif not _instance_values.has(name) or _instance_values[name] != value:
		proxy.set_instance_shader_parameter(name, value)
		_instance_values[name] = value


static func _full_caster_required(bounds: AABB, layers: int, state: Dictionary, metres: float) -> bool:
	if state.is_empty() or not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_volume(): return true
	var nearest: Vector3 = (state.camera as Vector3).clamp(bounds.position, bounds.end)
	if nearest.distance_to(state.camera) < metres * float(state.unit): return true
	if (layers & int(state.sun_mask)) == 0: return true
	var footprint := shadow_area(bounds, state.direction, state.floor_y)
	for area: Rect2 in state.receivers:
		if footprint.intersects(area, true): return true
	for light: Array in state.locals:
		if (layers & int(light[2])) != 0 and (light[0] as Vector3).distance_to((light[0] as Vector3).clamp(bounds.position, bounds.end)) <= float(light[1]): return true
	return false


func recheck_receivers(state: Dictionary) -> bool:
	# Camera changes only reconsider already-published shadow geometry. Resource
	# changes restore through the existing signals; full binding/eligibility checks
	# remain in the bounded object poll. Never admit or rebuild a proxy here.
	if not is_instance_valid(proxy) or not is_instance_valid(_source):
		restore(); return false
	if _source.mesh != proxy.mesh or _source.global_transform != _receiver_transform or _source.layers != _receiver_layers:
		restore(); return false
	if _source.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or _source.skin != null or _source.get_script() != null or _source.lod_bias <= SHADOW_LOD_BIAS:
		restore(); return false
	if _source.custom_aabb != proxy.custom_aabb or not is_equal_approx(_source.extra_cull_margin, proxy.extra_cull_margin):
		restore(); return false
	if _parameters_dirty or _source.material_override != proxy.material_override or _source.material_overlay != proxy.material_overlay:
		restore(); return false
	for surface in _source.get_surface_override_material_count():
		if _source.get_surface_override_material(surface) != proxy.get_surface_override_material(surface):
			restore(); return false
	if _full_caster_required(_receiver_bounds, _receiver_layers, state, RETURN_METRES):
		restore(); return false
	return true


func update(prop: Node3D, state: Dictionary) -> bool:
	var source := prop.get_node_or_null("Mesh") as MeshInstance3D
	if state.is_empty() or source == null or not source.mesh is ArrayMesh or source.skin != null:
		restore(); return false
	if source.get_script() != null or prop.get_script() != load("res://scripts/ember_voxel_prop.gd"):
		restore(); return false
	if prop.get("authoring_source") != null or prop.get("_world_look") != 0 or prop.get_meta("ember_external_source", false):
		restore(); return false
	var preview: WeakRef = prop.get("authoring_preview")
	if preview != null and is_instance_valid(preview.get_ref()): restore(); return false
	if not prop.call("object_detail_safe") or not has_lods(source.mesh): restore(); return false
	# Only the existing object's published native-LOD carrier is eligible.
	# Unknown authored replacements never become a new shadow source implicitly.
	if source.mesh != prop.get("_distance_mesh") or prop.get("_distance_source") == null:
		restore(); return false
	if source.lod_bias <= SHADOW_LOD_BIAS: restore(); return false
	if is_instance_valid(proxy) and (_source != source or proxy.mesh != source.mesh or proxy.material_override != source.material_override): restore()
	var casting: int = _cast if is_instance_valid(proxy) else source.cast_shadow
	# DOUBLE_SIDED cannot be combined with SHADOWS_ONLY without changing materials.
	if casting != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: restore(); return false
	var local_bounds := source.custom_aabb if source.custom_aabb.has_volume() else source.get_aabb()
	var bounds: AABB = source.global_transform * local_bounds.grow(source.extra_cull_margin)
	var threshold := RETURN_METRES if is_instance_valid(proxy) else FAR_METRES
	if _full_caster_required(bounds, source.layers, state, threshold): restore(); return false
	if not is_instance_valid(proxy):
		_source = source
		_cast = source.cast_shadow
		proxy = MeshInstance3D.new()
		proxy.name = "RuntimeShadowLod"
		# The source owner supplies exact uniforms. General styling must skip us.
		proxy.set_meta(DERIVED_PROXY_META, true)
		prop.add_child(proxy, false, Node.INTERNAL_MODE_BACK)
		proxy.mesh = source.mesh
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_watch(source.mesh)
		_source.visibility_changed.connect(_visibility_changed)
		_source.tree_exiting.connect(restore)
		_source.property_list_changed.connect(_parameters_changed)
		_source.set_meta(SOURCE_BINDING_META, weakref(self))
	# Keep alpha cutout, vertex animation, next passes and every authored override.
	for property in ["transform", "layers", "material_override", "material_overlay", "custom_aabb",
		"extra_cull_margin", "ignore_occlusion_culling", "transparency", "visibility_parent",
		"visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin",
		"visibility_range_end_margin", "visibility_range_fade_mode", "visible"]:
		var value:Variant=source.get(property)
		if proxy.get(property)!=value:proxy.set(property,value)
	var bias:=minf(source.lod_bias,SHADOW_LOD_BIAS)
	if not is_equal_approx(proxy.lod_bias,bias):proxy.lod_bias=bias
	_watch(source.material_override)
	_watch(source.material_overlay)
	var bindings: Array[Material] = [source.material_override, source.material_overlay]
	for surface in source.mesh.get_surface_count():
		var material := source.get_surface_override_material(surface)
		# Native same-value material/caster setters still queue dependency rebuilds.
		if proxy.get_surface_override_material(surface)!=material:
			proxy.set_surface_override_material(surface,material)
		bindings.append(source.get_active_material(surface))
		_watch(material)
		_watch(source.mesh.surface_get_material(surface))
	_sync_instance_parameters(source, bindings)
	_receiver_bounds = bounds
	_receiver_transform = source.global_transform
	_receiver_layers = source.layers
	# The complete native proxy is ready before the source stops casting.
	if source.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true
