@tool
class_name EmberMapLoader
extends Node3D
## Native authored-map runtime and explicit editor import boundary.
## Legacy load_map is never called by exploration startup. Geometry lives in
## the saved Look / Terrain / Props / Regions nodes and native ground source.

const SurfaceProjection := preload("res://scripts/ember_voxel_surface_projection.gd")
const TerrainResource := preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection := preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const SolidLayers = preload("res://scripts/ember_solid_material_layers.gd")
const ObjectLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const RuntimeShadowLod = preload("res://scripts/ember_runtime_shadow_lod.gd")
const PACKED_OBJECT_INDEX := "res://ember-prepared/objects/map.json"
signal anomaly_materials_changed
signal quality_changed
signal surface_object_changed(bounds: AABB)
signal detail_scatter_changed(patch: Node) # Derived publication/release;no authored state.

# Derived editor presentation only. Scene nodes, authored bindings and physical
# surfaces remain owned by the same props; no second population or save format.
var _object_details:Dictionary={}
var _object_detail_pending:Dictionary={}
var _object_detail_order:Array=[]
var _object_detail_poll:=0.0
var _object_detail_scan:Array=[]
var _object_detail_scan_cursor:=0
var _object_detail_distances:Dictionary={}
var _packed_object_index: Dictionary
var _packed_index_checked := false
var _packed_mesh_loading := ""
var _packed_mesh_host: WeakRef
var _packed_mesh_failures := {}
var _object_lod_cache:Dictionary={}
var _object_depth_task := -1
var _object_depth_job: EmberVoxelSurfaceMaterials.DepthPreparationJob
var _object_depth_sources: Array[Texture2D] = []
var _object_depth_host: WeakRef
var _object_depth_mesh_id := 0
var _object_depth_keys: Array = []
var _object_far_task := -1
var _object_far_job: SolidLayers.PreparationJob
var _object_far_source: WeakRef
var _object_far_resource: EmberVoxelModelResource
var _object_far_loading := ""
var _object_far_load_failed := {}
var _object_lod_task := -1
var _object_lod_job: ObjectLOD.ObjectJob
var _object_lod_source: WeakRef
var _object_lod_waiting:Dictionary={}
var _object_lod_attach:Array[WeakRef]=[]
var _object_detail_profile:Dictionary={"released":0,"restored":0,"lod_builds":0,"lod_levels":0,"lod_us":0,"worst_step_us":0}
var _physics_activity_source:WeakRef
var _physics_activity_stamp:Array=[]
var _physics_activity_suspended:Dictionary={}
var _physics_activity_scan:Array=[]
var _physics_activity_cursor:=0
var _physics_activity_enabled:=true
var _runtime_shadow_context:Dictionary={}
var _runtime_shadow_props:Dictionary={}
var _runtime_shadow_lights:Array=[]
var _runtime_shadow_lights_dirty:=true
var _runtime_shadow_enabled:=true

func set_runtime_shadow_lod_enabled(enabled:bool)->void:
	# Runtime QA control only; source data, other LOD and editor state are unchanged.
	_runtime_shadow_enabled=enabled
	if not enabled:_restore_runtime_shadows()
	_runtime_shadow_context.clear();_object_detail_poll=0.0

func _restore_runtime_shadows()->void:
	for reference:WeakRef in _runtime_shadow_props.values():
		var prop:=reference.get_ref() as EmberVoxelProp
		if is_instance_valid(prop):prop.restore_runtime_shadow_lod()
	_runtime_shadow_props.clear()

func _update_runtime_shadow_context()->void:
	if not _runtime_shadow_enabled or Engine.is_editor_hint() or not editor_object_detail_enabled():
		if not _runtime_shadow_props.is_empty():_restore_runtime_shadows()
		_runtime_shadow_context.clear();return
	for light in _runtime_shadow_lights:
		if not is_instance_valid(light) or not light.is_inside_tree():_runtime_shadow_lights_dirty=true;break
	if _runtime_shadow_lights_dirty:
		var scope:Node=get_tree().current_scene
		if scope==null or (scope!=self and not scope.is_ancestor_of(self)):scope=get_parent()
		_runtime_shadow_lights=scope.find_children("*","Light3D",true,false) if scope!=null else []
		_runtime_shadow_lights_dirty=false
	var anchors:Array[Vector3]=[]
	var camera:=get_viewport().get_camera_3d()
	# Shadow quality follows the viewer/party; distant crates still pin physics,
	# but their unseen receivers must not force full shadow geometry everywhere.
	if camera!=null and camera.get_parent() is EmberFollowCamera:
		var target:Node3D=camera.get_parent().target
		if is_instance_valid(target):anchors.append(target.global_position)
		if target is EmberPlayer and is_instance_valid(target.party_followers):
			for follower in target.party_followers._followers:
				if is_instance_valid(follower):anchors.append(follower.global_position)
	var next:=RuntimeShadowLod.context(self,camera,_runtime_shadow_lights,anchors)
	if next.get("signature",[])!=_runtime_shadow_context.get("signature",[]):
		# Sun preset/rotation, local light or terrain changes restore before rendering.
		_restore_runtime_shadows()
	elif next.get("receivers",[])!=_runtime_shadow_context.get("receivers",[]):
		# Camera/actor return is immediate; only admission remains staggered.
		for id in _runtime_shadow_props.keys():
			var prop:=(_runtime_shadow_props[id] as WeakRef).get_ref() as EmberVoxelProp
			if not is_instance_valid(prop) or not prop.recheck_runtime_shadow_receivers(next):_runtime_shadow_props.erase(id)
	_runtime_shadow_context=next

func _update_prop_shadow(prop:EmberVoxelProp,protected:bool=false)->void:
	if protected or Engine.is_editor_hint() or _runtime_shadow_context.is_empty():
		prop.restore_runtime_shadow_lod();_runtime_shadow_props.erase(prop.get_instance_id());return
	if prop.update_runtime_shadow_lod(_runtime_shadow_context):_runtime_shadow_props[prop.get_instance_id()]=weakref(prop)
	else:_runtime_shadow_props.erase(prop.get_instance_id())

func set_physics_activity_source(source:Node)->void:
	_restore_physics_activity()
	_physics_activity_source=weakref(source) if is_instance_valid(source) else null
	process_physics_priority=-100 # Restore before ordinary actor movement.

func set_runtime_physics_activity_enabled(enabled:bool)->void:
	_physics_activity_enabled=enabled
	if not enabled:_restore_physics_activity()

func invalidate_physics_activity()->void:
	_physics_activity_stamp.clear()

func runtime_physics_anchors()->Array[Vector3]:
	var source:Node=_physics_activity_source.get_ref() if _physics_activity_source!=null else null
	var anchors:Array[Vector3]=[]
	if is_instance_valid(source):anchors=source.physics_activity_anchors(get_world_3d())
	return anchors

func prepare_physics_destination(point:Vector3)->bool:
	_restore_physics_near(point)
	if is_instance_valid(_visual_surface_projection) and _visual_surface_projection.has_method("prepare_runtime_body_support"):
		_visual_surface_projection.prepare_runtime_body_support(point)
	return physics_destination_ready(point)

func physics_destination_ready(point:Vector3)->bool:
	if not is_instance_valid(_visual_surface_projection) or compact_ground_style!=1:return true
	var radius:=imported_tile_size*0.5
	return _visual_surface_projection.detail_area_ready(Rect2(Vector2(point.x,point.z)-Vector2.ONE*radius,Vector2.ONE*radius*2.0))

func _physics_activity_unit()->float:
	var scale_size:=global_basis.get_scale().abs()
	return maxf(0.001,imported_tile_size*maxf(scale_size.x,scale_size.z))

func _physics_area_distance(prop:EmberVoxelProp,point:Vector3)->float:
	return _physics_area_point_distance(_physics_prop_area(prop),point)

func _physics_prop_area(prop:EmberVoxelProp)->Rect2:
	var bounds:=prop.object_detail_bounds()
	return Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))

func _physics_area_point_distance(area:Rect2,point:Vector3)->float:
	var focus:=Vector2(point.x,point.z)
	return focus.distance_to(focus.clamp(area.position,area.end))

func _restore_physics_activity()->void:
	for reference:WeakRef in _physics_activity_suspended.values():
		var prop:=reference.get_ref() as EmberVoxelProp
		if is_instance_valid(prop):prop.set_runtime_physics_active(true)
	_physics_activity_suspended.clear();_physics_activity_stamp.clear();_physics_activity_scan.clear();_physics_activity_cursor=0

func _restore_physics_near(point:Vector3)->void:
	if _physics_activity_suspended.is_empty():return
	var radius:=36.0*_physics_activity_unit()
	for id in _physics_activity_suspended.keys():
		var prop:=(_physics_activity_suspended[id] as WeakRef).get_ref() as EmberVoxelProp
		if not is_instance_valid(prop):_physics_activity_suspended.erase(id);continue
		if _physics_area_distance(prop,point)<=radius:
			prop.set_runtime_physics_active(true);_physics_activity_suspended.erase(id)

func _restore_physics_near_points(points:Array[Vector3])->void:
	if points.is_empty() or _physics_activity_suspended.is_empty():return
	var radius:=36.0*_physics_activity_unit()
	# One published bound per suspended prop, shared by all returning actors.
	# No cached geometry or stale positions survive this synchronous admission.
	for id in _physics_activity_suspended.keys():
		var prop:=(_physics_activity_suspended[id] as WeakRef).get_ref() as EmberVoxelProp
		if not is_instance_valid(prop):_physics_activity_suspended.erase(id);continue
		var area:=_physics_prop_area(prop)
		for point in points:
			if _physics_area_point_distance(area,point)<=radius:
				prop.set_runtime_physics_active(true);_physics_activity_suspended.erase(id)
				break

func _physics_process(_delta:float)->void:
	var source:Node=_physics_activity_source.get_ref() if _physics_activity_source!=null else null
	if Engine.is_editor_hint() or not _physics_activity_enabled or source==null or not editor_object_detail_enabled():
		if not _physics_activity_suspended.is_empty():_restore_physics_activity()
		return
	var anchors:Array[Vector3]=source.physics_activity_anchors(get_world_3d())
	if anchors.is_empty():_restore_physics_activity();return
	var unit:=_physics_activity_unit()
	var stamp:Array=[]
	for point in anchors:stamp.append(Vector2i(floori(point.x/(4.0*unit)),floori(point.z/(4.0*unit))))
	if stamp!=_physics_activity_stamp:
		# Immediate near admission handles new actors/teleports; only removal is staggered.
		var returning:Array[Vector3]=[]
		for index in anchors.size():
			if index>=_physics_activity_stamp.size() or stamp[index]!=_physics_activity_stamp[index]:returning.append(anchors[index])
		if returning.size()==1:_restore_physics_near(returning[0])
		else:_restore_physics_near_points(returning)
		_physics_activity_stamp=stamp
		_physics_activity_scan=_object_details.values();_physics_activity_cursor=0
	var remaining:=8
	while _physics_activity_cursor<_physics_activity_scan.size() and remaining>0:
		var prop:=(_physics_activity_scan[_physics_activity_cursor] as WeakRef).get_ref() as EmberVoxelProp
		_physics_activity_cursor+=1;remaining-=1
		if not is_instance_valid(prop) or not is_ancestor_of(prop):continue
		if not prop.runtime_physics_safe():
			prop.set_runtime_physics_active(true);_physics_activity_suspended.erase(prop.get_instance_id());continue
		var nearby:=false
		var area:=_physics_prop_area(prop)
		for point in anchors:
			if _physics_area_point_distance(area,point)<=48.0*unit:nearby=true;break
		if not nearby:
			prop.set_runtime_physics_active(false)
			if not prop._runtime_physics_state.is_empty():_physics_activity_suspended[prop.get_instance_id()]=weakref(prop)

func editor_object_detail_enabled()->bool:
	if compact_terrain==null or world_look!=0 or compact_ground_style!=1:return false
	return not is_instance_valid(_visual_surface_projection) or _visual_surface_projection.detail_policy.enabled

func _queue_object_look(prop:EmberVoxelProp)->bool:
	if not editor_object_detail_enabled():return false
	_object_details[prop.get_instance_id()]=weakref(prop)
	invalidate_physics_activity()
	_object_detail_poll=0.0
	if not prop.object_detail_safe():
		_object_detail_pending.erase(prop.get_instance_id());return true
	if prop.owner==null:
		# The existing preview/publication queue owns these temporary nodes.
		# Prepare only the selected world, without eager alternate-world bakes.
		prop.apply_object_detail(true);return true
	if not Engine.is_editor_hint(): _bind_packed_object(prop)
	prop._distance_ready=false
	return true

func _bind_packed_object(prop: EmberVoxelProp) -> void:
	if not _packed_index_checked:
		_packed_index_checked = true
		if owner != null and FileAccess.file_exists(PACKED_OBJECT_INDEX):
			var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKED_OBJECT_INDEX))
			if index is Dictionary and index.get("scene") == owner.scene_file_path and index.get("props") is Dictionary:
				_packed_object_index = index.props
	if _packed_object_index.is_empty(): return
	var entry: Array = _packed_object_index.get(str(get_path_to(prop)), [])
	var path: String = entry[1] if entry.size() == 2 and entry[0] == prop.model_id else ""
	if path != prop.packed_detail_path:
		prop.packed_detail_path = path
		prop.packed_detail_mesh = null

func _request_packed_detail(prop: EmberVoxelProp) -> bool:
	var path := prop.packed_detail_path
	if path.is_empty() or prop.authoring_source != null or prop.packed_detail_mesh != null or _packed_mesh_failures.has(path):
		return true
	if not _packed_mesh_loading.is_empty(): return false
	var cached := ResourceLoader.get_cached_ref(path) as ArrayMesh
	if cached != null:
		prop.packed_detail_mesh = cached
		return true
	if ResourceLoader.load_threaded_request(path, "ArrayMesh") != OK:
		_packed_mesh_failures[path] = true
		return true # Older/missing data uses the original representation.
	_packed_mesh_loading = path
	_packed_mesh_host = weakref(prop)
	return false

func _finish_packed_detail(leaving := false) -> void:
	if _packed_mesh_loading.is_empty(): return
	var status := ResourceLoader.load_threaded_get_status(_packed_mesh_loading)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not leaving: return
	var mesh: ArrayMesh
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		mesh = ResourceLoader.load_threaded_get(_packed_mesh_loading) as ArrayMesh
	if mesh == null: _packed_mesh_failures[_packed_mesh_loading] = true
	var prop := _packed_mesh_host.get_ref() as EmberVoxelProp
	if not leaving and is_instance_valid(prop) and is_ancestor_of(prop) and prop.packed_detail_wanted and prop.packed_detail_path == _packed_mesh_loading:
		prop.packed_detail_mesh = mesh
	_packed_mesh_loading = ""
	_packed_mesh_host = null

func _invalidate_object_lod(id:int)->void:
	if _object_lod_job != null and _object_lod_source.get_ref() != null and _object_lod_source.get_ref().get_instance_id() == id: _object_lod_job.stale = true
	_object_lod_cache.erase(id)
	for reference:WeakRef in _object_details.values():
		var prop:=reference.get_ref() as EmberVoxelProp
		if is_instance_valid(prop) and prop.object_detail_base()!=null and prop.object_detail_base().get_instance_id()==id:prop._distance_ready=false
	_object_detail_poll=0.0

func _object_area(projection:Node3D,prop:EmberVoxelProp)->Rect2:
	var bounds:AABB=projection.global_transform.affine_inverse()*prop.object_detail_bounds()
	return Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))

func _poll_object_details(max_props:int=0)->void:
	var projection:=_visual_surface_projection as TerrainProjection
	if not is_instance_valid(projection) or not projection.editor_detail_active():return
	var selected:Array=[]
	var editor:=Engine.get_singleton("EditorInterface") if Engine.is_editor_hint() else null
	if editor!=null:selected=editor.get_selection().get_selected_nodes()
	if max_props<=0 or _object_detail_scan_cursor>=_object_detail_scan.size():
		_object_detail_scan=_object_details.keys()
		_object_detail_scan_cursor=0
		for id:int in _object_detail_distances.keys():
			if not _object_details.has(id):_object_detail_distances.erase(id)
	var remaining:=max_props if max_props>0 else _object_detail_scan.size()
	# Native caster/material work varies per prop. A count cap alone produces
	# bursts on populated maps; retain the cursor and yield after one millisecond.
	# Explicit full refreshes (max_props=0) keep their existing synchronous contract.
	var started:=Time.get_ticks_usec()
	var visited:=0
	while _object_detail_scan_cursor<_object_detail_scan.size() and remaining>0:
		if max_props>0 and visited>0 and Time.get_ticks_usec()-started>=1000:break
		var id:int=_object_detail_scan[_object_detail_scan_cursor]
		_object_detail_scan_cursor+=1;remaining-=1;visited+=1
		if not _object_details.has(id):continue
		var prop:=(_object_details[id] as WeakRef).get_ref() as EmberVoxelProp
		if not is_instance_valid(prop) or not is_ancestor_of(prop):
			_object_details.erase(id);_object_detail_pending.erase(id);continue
		if prop.owner==null:
			_update_prop_shadow(prop,true);continue
		if not prop.object_detail_safe():
			_update_prop_shadow(prop,true)
			_object_detail_pending.erase(id);continue
		var protected:=prop.authoring_source!=null or (prop.authoring_preview!=null and is_instance_valid(prop.authoring_preview.get_ref()))
		for node:Node in selected:
			if node==prop or prop.is_ancestor_of(node):protected=true;break
		_update_prop_shadow(prop,protected)
		var area := _object_area(projection,prop)
		_object_detail_distances[id] = projection.detail_policy.distance_m(area)
		var wanted:bool=projection.detail_policy.object_resident(area,prop._distance_resident if prop._distance_managed else false,protected)
		if not prop.packed_detail_path.is_empty():
			prop.packed_detail_wanted = wanted or float(_object_detail_distances[id]) <= projection.detail_policy.object_release_m
			if prop.packed_detail_wanted: _request_packed_detail(prop)
			else: prop.packed_detail_mesh = null
		if not prop._distance_ready or not prop._distance_managed or wanted!=prop._distance_resident:_object_detail_pending[id]=wanted
		else:_object_detail_pending.erase(id) # A camera reversal cancels obsolete preparation.
	_object_detail_order=_object_detail_pending.keys()
	_object_detail_order.sort_custom(func(a:int,b:int):
		if _object_detail_pending[a]!=_object_detail_pending[b]:return _object_detail_pending[a]
		return float(_object_detail_distances.get(a, INF)) < float(_object_detail_distances.get(b, INF)))

func _request_object_lod(prop:EmberVoxelProp)->void:
	if not prop.object_lod_allowed():return
	var source:=prop.object_detail_base()
	if source==null:return
	var id:=source.get_instance_id()
	if _object_lod_cache.has(id):prop.install_object_lod(source,_object_lod_cache[id].mesh)
	elif _object_lod_source == null or _object_lod_source.get_ref() != source:_object_lod_waiting[id]=weakref(source)

func _release_object_depth_sources() -> void:
	for source in _object_depth_sources:
		if source.changed.is_connected(_invalidate_object_depth): source.changed.disconnect(_invalidate_object_depth)
	_object_depth_sources.clear()
	_object_depth_host = null
	_object_depth_mesh_id = 0
	_object_depth_keys.clear()

func _depth_host_current() -> bool:
	var host := _object_depth_host.get_ref() as EmberVoxelProp if _object_depth_host != null else null
	if not is_instance_valid(host) or not is_ancestor_of(host) or not host.object_detail_safe(): return false
	var mesh := host.object_far_material_mesh()
	return mesh != null and mesh.get_instance_id() == _object_depth_mesh_id

func _invalidate_object_depth() -> void:
	if _object_depth_job != null: _object_depth_job.stale = true
	else:
		for key in _object_depth_keys: EmberVoxelSurfaceMaterials._bank_height_images.erase(key)
		_release_object_depth_sources()

func _finish_object_depth(wait: bool = false) -> void:
	if _object_depth_task < 0:
		if wait or not editor_object_detail_enabled() or not _depth_host_current(): _release_object_depth_sources()
		return
	if not wait and not WorkerThreadPool.is_task_completed(_object_depth_task): return
	WorkerThreadPool.wait_for_task_completion(_object_depth_task)
	_object_depth_task = -1
	var job := _object_depth_job
	_object_depth_job = null
	if not wait and not job.stale and editor_object_detail_enabled():
		EmberVoxelSurfaceMaterials.publish_depth_preparation(job)
		_object_depth_keys = job.images.keys()
		# Keep source identity stable until this host's material owns the textures.
		# Otherwise an isolated texture dies here and reloads under a new cache key.
		if _depth_host_current(): return
	_release_object_depth_sources()

func _prepare_object_depth(mesh: ArrayMesh, host: EmberVoxelProp) -> bool:
	# A single material may exceed the memo's budget. Consume its completed
	# preflight once; evicted layers use the existing synchronous fallback,
	# rather than repeatedly queueing a batch that can never fit the memo.
	if _object_depth_task < 0 and _depth_host_current() and _object_depth_host.get_ref() == host and not _object_depth_keys.is_empty(): return true
	if _object_depth_task >= 0 or _object_far_task >= 0 or _object_lod_task >= 0: return false
	var prepared := EmberVoxelSurfaceMaterials.depth_preparation(mesh.get_meta("solid_surface_roles", PackedStringArray()), mesh.get_meta("solid_surface_material_ids", PackedStringArray()))
	var job := prepared.job as EmberVoxelSurfaceMaterials.DepthPreparationJob
	if job.recipes.is_empty(): return true
	if not _object_depth_sources.is_empty(): return false
	_object_depth_job = job
	_object_depth_host = weakref(host)
	_object_depth_mesh_id = mesh.get_instance_id()
	_object_depth_sources.assign(prepared.sources)
	for source in _object_depth_sources:
		if not source.changed.is_connected(_invalidate_object_depth): source.changed.connect(_invalidate_object_depth)
	_object_depth_task = WorkerThreadPool.add_task(job.run, false, "Ember object height images")
	return false

func _invalidate_object_far(id: int) -> void:
	SolidLayers._forget_prepared(id)
	if _object_far_job != null and _object_far_source.get_ref() != null and _object_far_source.get_ref().get_instance_id() == id: _object_far_job.stale = true
	for reference: WeakRef in _object_details.values():
		var prop := reference.get_ref() as EmberVoxelProp
		if is_instance_valid(prop):
			var mesh := prop.object_far_preparation_mesh()
			if mesh != null and mesh.get_instance_id() == id: prop._distance_ready = false
	_object_detail_poll = 0.0

func _finish_object_far(wait: bool = false) -> void:
	if not _object_far_loading.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_object_far_loading)
		if wait or status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var path := _object_far_loading
			_object_far_loading = ""
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_object_far_load_failed[path] = true
			else:
				var resource := ResourceLoader.load_threaded_get(path) as EmberVoxelModelResource
				if resource != null and not wait: EmberVoxelProp.remember_solid_source(path, resource)
	if _object_far_task < 0: return
	if not wait and not WorkerThreadPool.is_task_completed(_object_far_task): return
	WorkerThreadPool.wait_for_task_completion(_object_far_task)
	_object_far_task = -1
	var job := _object_far_job
	var source := _object_far_source.get_ref() as ArrayMesh
	_object_far_job = null
	_object_far_source = null
	_object_far_resource = null
	if wait or job.stale or source == null or not editor_object_detail_enabled(): return
	SolidLayers.publish_preparation(source, job)

func _prepare_object_far(prop: EmberVoxelProp) -> bool:
	var material_mesh := prop.object_far_material_mesh()
	if material_mesh != null and not _prepare_object_depth(material_mesh, prop): return false
	var mesh := prop.object_far_preparation_mesh()
	if mesh == null: return true
	var path := "res://content/voxel_models/%s.tres" % prop.model_id
	var resource := prop.authoring_source
	if resource == null: resource = EmberVoxelProp._solid_sources.get(path)
	if resource == null:
		if _object_far_load_failed.has(path): return true # Preserve existing missing-source diagnostics.
		if _object_far_loading.is_empty() and _object_far_task < 0 and _object_lod_task < 0 and _object_depth_task < 0:
			if ResourceLoader.load_threaded_request(path) == OK: _object_far_loading = path
			else: _object_far_load_failed[path] = true
		return false
	if resource.solid_surface.is_empty() or not SolidLayers.needs_preparation(mesh): return true
	if _object_far_task >= 0 or _object_lod_task >= 0 or _object_depth_task >= 0: return false
	var job := SolidLayers.preparation_job(mesh, EmberVoxelPrefab.model_of(resource.to_definition(true)))
	var invalidate := _invalidate_object_far.bind(mesh.get_instance_id())
	if not mesh.changed.is_connected(invalidate): mesh.changed.connect(invalidate)
	if not resource.changed.is_connected(invalidate): resource.changed.connect(invalidate)
	_object_far_resource = resource
	_object_far_source = weakref(mesh)
	_object_far_job = job
	_object_far_task = WorkerThreadPool.add_task(job.run, false, "Ember far face descriptors")
	return false

func _finish_object_lod(wait: bool = false) -> void:
	if _object_lod_task < 0: return
	if not wait and not WorkerThreadPool.is_task_completed(_object_lod_task): return
	WorkerThreadPool.wait_for_task_completion(_object_lod_task)
	_object_lod_task = -1
	var job := _object_lod_job
	var source := _object_lod_source.get_ref() as ArrayMesh
	_object_lod_job = null
	_object_lod_source = null
	if wait or job.stale or source == null or not editor_object_detail_enabled(): return
	var built := ObjectLOD.publish_object(job, source)
	var id := source.get_instance_id()
	while _object_lod_cache.size() >= 8: _object_lod_cache.erase(_object_lod_cache.keys()[0])
	_object_lod_cache[id] = {"source": weakref(source), "mesh": built.mesh}
	_object_detail_profile.lod_builds += 1
	_object_detail_profile.lod_levels += built.levels
	_object_detail_profile.lod_us += built.us
	for reference: WeakRef in _object_details.values():
		var prop := reference.get_ref() as EmberVoxelProp
		if is_instance_valid(prop) and prop.object_lod_allowed() and prop.object_detail_base() == source: _object_lod_attach.append(reference)

func _process(_delta:float)->void:
	var callback_started := Time.get_ticks_usec()
	_update_runtime_shadow_context()
	var started := Time.get_ticks_usec()
	_object_detail_profile.shadow_context_us = started - callback_started
	for key: String in ["finish_depth_us","finish_far_us","finish_lod_us","poll_us","preflight_us","apply_us","snapshot_us","attach_us"]: _object_detail_profile[key] = 0
	_object_detail_profile.profile_frame = Engine.get_process_frames()
	_process_object_details(_delta)
	var elapsed := Time.get_ticks_usec() - started
	_object_detail_profile.process_us = elapsed
	_object_detail_profile.worst_process_us = maxi(int(_object_detail_profile.get("worst_process_us",0)), elapsed)
	_object_detail_profile.total_process_us = Time.get_ticks_usec() - callback_started

func _process_object_details(_delta:float)->void:
	_finish_packed_detail()
	var phase := Time.get_ticks_usec()
	_finish_object_depth()
	_object_detail_profile.finish_depth_us = Time.get_ticks_usec() - phase
	phase = Time.get_ticks_usec()
	_finish_object_far()
	_object_detail_profile.finish_far_us = Time.get_ticks_usec() - phase
	phase = Time.get_ticks_usec()
	_finish_object_lod()
	_object_detail_profile.finish_lod_us = Time.get_ticks_usec() - phase
	# Scene meshes are already visible. Let the initial exact ground publish
	# before replacing those meshes with distance-managed detail in the editor.
	var terrain := _visual_surface_projection as TerrainProjection
	if Engine.is_editor_hint() and is_instance_valid(terrain) and terrain.editor_ground_opening():
		return
	if not editor_object_detail_enabled():
		if _object_lod_job != null: _object_lod_job.stale = true
		if _object_far_job != null: _object_far_job.stale = true
		if _object_depth_job != null: _object_depth_job.stale = true
		for reference:WeakRef in _object_details.values():
			var prop:=reference.get_ref() as EmberVoxelProp
			if is_instance_valid(prop) and prop._distance_managed:prop.restore_object_detail(world_look)
		_object_detail_scan.clear();_object_detail_scan_cursor=0;_object_detail_distances.clear()
		_object_detail_pending.clear();_object_detail_order.clear();_object_lod_waiting.clear();_object_lod_attach.clear();_object_lod_cache.clear();return
	_object_detail_poll-=_delta
	if _object_detail_poll<=0 or _object_detail_scan_cursor<_object_detail_scan.size():
		phase = Time.get_ticks_usec()
		# A dense world must not inspect every prop in one process tick. Keep
		# the existing residency queue; feed it in bounded batches, near first.
		_poll_object_details(128)
		if _object_detail_scan_cursor>=_object_detail_scan.size():_object_detail_poll=0.25
		_object_detail_profile.poll_us = Time.get_ticks_usec() - phase
	var started:=Time.get_ticks_usec()
	while not _object_detail_order.is_empty() and not _object_detail_pending.has(_object_detail_order[0]):_object_detail_order.pop_front()
	var near_urgent:bool=not _object_detail_order.is_empty() and _object_detail_pending[_object_detail_order[0]]
	if not near_urgent and not _object_lod_attach.is_empty():
		var count:=0
		while not _object_lod_attach.is_empty() and count<4 and Time.get_ticks_usec()-started<4000:
			var prop:=_object_lod_attach.pop_front().get_ref() as EmberVoxelProp
			if is_instance_valid(prop):_request_object_lod(prop)
			count+=1
		_object_detail_profile.attach_us = Time.get_ticks_usec() - started
		_object_detail_profile.worst_step_us=maxi(_object_detail_profile.worst_step_us,Time.get_ticks_usec()-started)
		return
	# One existing prop preparation or CPU snapshot admission per tick.
	# LOD indexing/simplification runs off-thread; prop preparation is still
	# indivisible and must not be described as a guaranteed 4ms frame budget.
	if not _object_detail_pending.is_empty() and (near_urgent or _object_lod_waiting.is_empty()):
		while not _object_detail_order.is_empty() and not _object_detail_pending.has(_object_detail_order[0]):_object_detail_order.pop_front()
		if _object_detail_order.is_empty():return
		var id:int=_object_detail_order.pop_front()
		var resident:bool=_object_detail_pending[id]
		var prop:=(_object_details[id] as WeakRef).get_ref() as EmberVoxelProp
		if is_instance_valid(prop) and prop.owner!=null and is_ancestor_of(prop) and prop.object_detail_safe():
			if resident and not _request_packed_detail(prop):
				_object_detail_order.append(id)
				return # Keep the published mesh and collision while reading.
			if not resident:
				phase = Time.get_ticks_usec()
				var ready := _prepare_object_far(prop)
				_object_detail_profile.preflight_us = Time.get_ticks_usec() - phase
				if not ready:
					_object_detail_order.append(id)
					return
			_object_detail_pending.erase(id)
			phase = Time.get_ticks_usec()
			prop.apply_object_detail(resident)
			_object_detail_profile.apply_us = Time.get_ticks_usec() - phase
			_object_detail_profile.apply_model = prop.model_id
			_object_detail_profile.apply_resident = resident
			_object_detail_profile.apply_packed = resident and prop.packed_detail_mesh != null
			if _object_depth_task < 0 and _object_depth_host != null and _object_depth_host.get_ref() == prop: _release_object_depth_sources()
			_object_detail_profile["restored" if resident else "released"]+=1
			_request_object_lod(prop)
		else: _object_detail_pending.erase(id)
	elif not _object_lod_waiting.is_empty() and _object_lod_task < 0 and _object_far_task < 0 and _object_depth_task < 0:
		var id:int=_object_lod_waiting.keys()[0]
		var source:=(_object_lod_waiting[id] as WeakRef).get_ref() as ArrayMesh
		_object_lod_waiting.erase(id)
		if source!=null:
			phase = Time.get_ticks_usec()
			var job := ObjectLOD.object_job(source,source.get_surface_count()>0 and source.surface_get_name(0)=="tree_bark")
			_object_detail_profile.snapshot_us = Time.get_ticks_usec() - phase
			if job != null:
				var invalidate := _invalidate_object_lod.bind(id)
				if not source.changed.is_connected(invalidate): source.changed.connect(invalidate)
				_object_lod_source = weakref(source)
				_object_lod_job = job
				_object_lod_task = WorkerThreadPool.add_task(job.run, false, "Ember object LOD")
	_object_detail_profile.worst_step_us=maxi(_object_detail_profile.worst_step_us,Time.get_ticks_usec()-started)

func object_detail_profile()->Dictionary:
	var result:=_object_detail_profile.duplicate()
	result.pending=_object_detail_pending.size()+_object_lod_waiting.size()+_object_lod_attach.size()+int(_object_lod_task >= 0)+int(_object_far_task >= 0)+int(_object_depth_task >= 0)+int(not _object_far_loading.is_empty());result.shared_lod_meshes=_object_lod_cache.size()
	result.near=0;result.far=0;result.living_meshes=0
	for reference:WeakRef in _object_details.values():
		var prop:=reference.get_ref() as EmberVoxelProp
		if not is_instance_valid(prop):continue
		result["near" if prop._distance_resident else "far"]+=1
		if prop._living_mesh!=null:result.living_meshes+=1
	return result

## One scene-owned presentation; -1 preserves the authored appearance of older maps.
## Physical ground, object colliders and editable Source are shared by all three looks.
@export_enum("Сохранённый вид:-1", "Детальный мир:0", "Low poly:1", "Воксельный мир:2") var world_look := -1:
	set(value):
		world_look = clampi(value, -1, 2)
		_refresh_world_look()


func _refresh_world_look() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(_visual_surface_projection) and _visual_surface_projection.has_method("set_world_look"):
		_visual_surface_projection.set_world_look(world_look)
	_apply_world_look_branch(self)


func _apply_world_look_branch(parent: Node) -> void:
	for child in parent.get_children():
		if child is EmberMapLoader: continue
		if child is EmberVoxelProp:
			if not _queue_object_look(child):child.restore_object_detail(world_look)
		elif child.has_method("set_world_look"): child.set_world_look(world_look)
		else: _apply_world_look_branch(child)
		if child.has_method("apply_voxel_light_settings"): child.apply_voxel_light_settings(self)

@export_group("0 · Карта и тест")
## ID карты. Legacy reimport читает joi-conductor; native scene держит свой Resource.
@export var map_id := EmberMapTransition.DEFAULT_MAP_ID
## Deprecated serialized flag; runtime always uses authored native regions.
@export var hydrate_legacy_regions := false
## Одна общая художественная поверхность карты. Выбранный прямоугольник в 3D
## является только областью редактирования и не создаёт отдельный Resource.
@export var visual_surface: EmberVoxelModelResource:
	set(value):
		if visual_surface == value:
			return
		visual_surface = value
		_refresh_visual_surface_projection()
## Compact ground is an alternative map-owned source. A map may never render
## both this and the legacy dense Surface as its ground.
## Explicit scene budget; ordinary maps retain the conservative 32x32m default.
@export_storage var compact_smooth_study_column_limit := 0
@export var compact_terrain: TerrainResource:
	set(value):
		compact_terrain = value
		if compact_ground_style == 1 and value != null and value.width*value.depth > smooth_column_limit() and not TerrainProjection.supports_editor_residency(value,smooth_column_limit()):
			compact_ground_style = 0
			push_warning("Размер детальной земли превышает бюджет этой карты: %d колонок." % smooth_column_limit())
		_refresh_visual_surface_projection()
## Optional fine-grid smooth appearance; the source columns stay unchanged.
@export_enum("Воксельная земля", "Детальная земля") var compact_ground_style := 0:
	set(value):
		if value == 1 and compact_terrain != null and compact_terrain.width*compact_terrain.depth > smooth_column_limit() and not TerrainProjection.supports_editor_residency(compact_terrain,smooth_column_limit()):
			push_warning("Размер детальной земли превышает бюджет этой карты: %d колонок." % smooth_column_limit())
			return
		compact_ground_style = clampi(value,0,1)
		_refresh_visual_surface_projection()
## Optional derived material feathering; existing scene defaults stay unchanged.
@export var compact_smooth_material_blend := false:
	set(value):
		compact_smooth_material_blend=value
		_refresh_visual_surface_projection()
## Optional scene-owned water look. Zero mesh step preserves the shared
## greedy water geometry; a positive step only refines visual wave vertices.
@export var compact_water_visual_material: ShaderMaterial
@export_range(0, 16, 1) var compact_water_mesh_step := 0
@export var compact_water_volume_sides := false
## Scene-owned material comparison. Old maps retain their existing light.
@export var compact_style_rim_enabled := true:
	set(value):
		compact_style_rim_enabled = value
		refresh_style_rim()

@export_enum("Прежний свет", "Естественный мультяшный", "Игрушечный пластик") var compact_material_light_mode := 0:
	set(value):
		compact_material_light_mode = clampi(value, 0, 2)
		_apply_compact_material_light()
@export var compact_material_gray_preview := false:
	set(value):
		compact_material_gray_preview = value
		_apply_compact_material_light()
## Optical material depth distances in metres, independently of map unit scale.
@export_range(0.0, 64.0, 1.0) var compact_depth_fade_near_m := 6.0:
	set(value):
		compact_depth_fade_near_m = maxf(0.0,value)
		_refresh_material_depth_settings()
@export_range(1.0, 128.0, 1.0) var compact_depth_fade_far_m := 14.0:
	set(value):
		compact_depth_fade_far_m = maxf(1.0,value)
		_refresh_material_depth_settings()


func _refresh_material_depth_settings() -> void:
	if is_instance_valid(_visual_surface_projection) and _visual_surface_projection is TerrainProjection:
		_visual_surface_projection._refresh_look_materials()
	if is_inside_tree(): _bind_voxel_light_branch(self)
	anomaly_materials_changed.emit()


## One scene-owned distance policy, in physical metres rather than texture units.
func bind_material_depth_distance(material: ShaderMaterial, units_per_m: float) -> void:
	if material == null: return
	material.set_shader_parameter("material_depth_fade_near_m", compact_depth_fade_near_m * units_per_m)
	material.set_shader_parameter("material_depth_fade_far_m", maxf(compact_depth_fade_near_m + 1.0, compact_depth_fade_far_m) * units_per_m)

## Lighting grid is scene-owned; changing it only updates existing shader uniforms.
@export_range(0.015625, 0.5, 0.015625, "suffix:m") var voxel_light_cell_m := 0.0625:
	set(value):
		voxel_light_cell_m = clampf(value, 0.015625, 0.5) if is_finite(value) else 0.0625
		_refresh_voxel_light_settings()
@export_range(2, 32, 1) var voxel_light_levels := 8:
	set(value):
		voxel_light_levels = clampi(value, 2, 32)
		_refresh_voxel_light_settings()


## Scene-local derived bindings. Weak references let unloaded props release materials.
var _runtime_tree_materials: Dictionary = {}

func runtime_tree_material(source: ShaderMaterial, look: int) -> ShaderMaterial:
	var signature: Array = [source.shader, source.render_priority, source.next_pass]
	# Godot normalizes unset/default uniform values when enumerating properties
	# (duplicate() does this too). Fingerprint that canonical state from the start.
	for property in source.get_property_list():
		if str(property.name).begins_with("shader_parameter/"):
			signature.append([property.name, source.get(property.name)])
	var key: Array = [source.get_instance_id(), look]
	var entry: Dictionary = _runtime_tree_materials.get(key, {})
	if not entry.is_empty() and entry.source.get_ref() == source and entry.signature == signature:
		var existing := entry.material.get_ref() as ShaderMaterial
		if existing != null: return existing
	# Bound the registry when source/props leave. Each source/look keeps one version.
	for stale_key in _runtime_tree_materials.keys():
		var stale: Dictionary = _runtime_tree_materials[stale_key]
		if stale.source.get_ref() == null or stale.material.get_ref() == null:
			_runtime_tree_materials.erase(stale_key)
	var material := source.duplicate() as ShaderMaterial
	material.set_meta("ember_derived_tree_material", true)
	_runtime_tree_materials[key] = {"source": weakref(source), "signature": signature.duplicate(true), "material": weakref(material)}
	return material

func bind_voxel_light(material: ShaderMaterial, look: int, units_per_m: float, anomaly := false) -> void:
	if material == null: return
	material.set_shader_parameter("voxel_light_enabled", look == 2)
	material.set_shader_parameter("voxel_light_anomaly", anomaly)
	material.set_shader_parameter("voxel_light_cell", voxel_light_cell_m * units_per_m)
	material.set_shader_parameter("voxel_light_levels", float(voxel_light_levels))
	EmberVoxelSurfaceMaterials.refresh_existing_terrain_features(material)


func _refresh_voxel_light_settings() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(_visual_surface_projection) and _visual_surface_projection is TerrainProjection:
		_visual_surface_projection._refresh_look_materials()
	_bind_voxel_light_branch(self)
	anomaly_materials_changed.emit()


func _bind_voxel_light_branch(parent: Node) -> void:
	for child in parent.get_children():
		if child is EmberMapLoader: continue
		if child.has_method("apply_voxel_light_settings"): child.apply_voxel_light_settings(self)
		else: _bind_voxel_light_branch(child)


## Saved map footprint lets a native Surface validate without reading the
## source. Zero means unknown during scene deserialization, never a JSON lookup.
@export var authored_size_blocks := Vector2i.ZERO
## Scene-owned origin of the shared voxel grid, in map-local world units.
## Old maps keep zero. Native ground can reserve volume below sea level.
@export var surface_origin := Vector3.ZERO:
	set(value):
		surface_origin = value
		_refresh_visual_surface_projection()
var _editor_surface_preview: EmberVoxelModelResource
var _editor_surface_origin := Vector3.ZERO
var _editor_terrain_preview: TerrainResource
var editor_warning_timing_enabled := false
var editor_warning_validation_count := 0
var editor_warning_validation_usec := 0
var editor_warning_validation_last_start_usec := 0
var editor_warning_validation_last_duration_usec := 0

func set_editor_terrain_preview(source: TerrainResource) -> void:
	if not Engine.is_editor_hint():
		return
	_editor_terrain_preview = source
	_refresh_visual_surface_projection()

func set_editor_surface_preview(source: EmberVoxelModelResource, origin := Vector3.ZERO) -> void:
	if not Engine.is_editor_hint():
		return
	_editor_surface_preview = source
	_editor_surface_origin = origin
	_refresh_visual_surface_projection()
## Optional native surface physics: world collision and route heights share visual_surface.
## Enabled explicitly per map; compact terrain retains its own native geometry.
@export var use_visual_surface_physics := false
## Число ближайших фонарей с cube-тенью. Fill остальных фонарей всегда остаётся включённым.
@export_enum("Только fill · 0:0", "Быстро · 2:2", "Баланс · 4:4", "Production · 8:8", "Расширенный · 12:12", "Stress · 16:16") var lighting_test_shadows := 4
## Включайте только для проверки кадра: локальные тени в 3D viewport дороже и обновляются при движении камеры.
@export var preview_local_shadows_in_editor := false
@export_tool_button("Применить профиль света") var apply_test_profile_action: Callable = _apply_test_profile
@export_tool_button("Применить все настройки света") var apply_look_action: Callable = apply_authored_lighting

@export_group("1 · Атмосфера")
@export_subgroup("Туман")
@export var fog_enabled := true
@export var fog_depth_begin := 48.0
@export var fog_depth_end := 340.0
@export var fog_aerial := 0.5
@export var fog_sky_affect := 0.8
@export var fog_sun_scatter := 0.16
@export var fog_color_mix := 0.2

@export_subgroup("Небо")
@export var sky_energy := 1.2
@export var star_amount := 0.85
@export var moon_disc_size := 0.034

@export_group("2 · Луна и общая тень")
@export var moon_shadows := true
@export var moon_energy_scale := 1.25
@export var sun_intensity := 1.0
@export var fill_intensity := 1.0
@export var ambient_alpha := 0.5
@export var directional_shadow_distance := 520.0
@export_enum("2 splits:2", "4 splits:4") var directional_shadow_splits := 4
@export_enum("1024:1024", "2048:2048", "4096:4096", "8192:8192") var directional_shadow_size := 4096
@export_enum("Hard:0", "Very Low:1", "Low:2", "Medium:3", "High:4", "Ultra:5") var directional_shadow_filter := 2
@export_range(0.0, 1.0, 0.01) var moon_shadow_bias := 0.14
@export_range(0.0, 4.0, 0.05) var moon_shadow_normal_bias := 2.4
@export_range(0.0, 4.0, 0.05) var moon_shadow_blur := 1.35

@export_group("3 · Фонари")
@export var lamp_energy_scale := 1.15
@export var lamp_range_scale := 1.0
@export var lamp_use_map_range := true
@export var lamp_power := 1.0
@export var lamp_range_tiles := 7.0
@export var lamp_strength0 := 0.62
@export var lamp_falloff := 0.42
@export var lamp_color := Color(1.0, 0.69, 0.337)
@export var lamp_face_color := Color(1.0, 0.565, 0.188)
## 1 = плавный свет без колец; 0 = ступенчатый toon-свет как от луны.
@export_range(0.0, 1.0, 0.05) var lamp_softness := 1.0
## Runtime-бюджет ближайших фонарей с тенями. Для сравнения используйте профиль выше или F4 в Play.
@export_range(0, 16) var omni_shadow_count := 4
@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var lamp_shadow_size := 4096
@export_enum("Hard:0", "Very Low:1", "Low:2", "Medium:3", "High:4", "Ultra:5") var lamp_shadow_filter := 1
## Depth offset локальной тени. Поднимать только если normal bias не убрал self-shadow acne.
@export_range(0.0, 1.0, 0.01) var lamp_shadow_bias := 0.18
## Основной anti-acne для Omni. Он меньше отрывает тень от объекта, чем обычный bias.
@export_range(0.0, 4.0, 0.05) var lamp_shadow_normal_bias := 1.8
## Большой blur усиливает зернистый PCF-рисунок на однотонных voxel-поверхностях.
@export_range(0.0, 2.0, 0.05) var lamp_shadow_blur := 0.25

@export_group("4 · Камера и качество")
@export var camera_fov := 40.0
@export var camera_distance := 120.0
@export var camera_polar := 0.95
@export var camera_yaw := 0.785398
@export var camera_look_height := 6.0
@export var camera_near := 1.0
@export var camera_far := 5000.0
@export_enum("Off:0", "2x:1", "4x:2", "8x:3") var msaa_3d := 2
## Добавляет fullscreen-dither против цветовых полос. На текущем voxel-стиле оставлен выключенным: узор виден сильнее banding.
@export var use_debanding := false
## Temporal accumulation removes stochastic shadow grain; independent of Sun softness.
@export var use_taa := false:
	set(value):
		use_taa = value
		apply_quality()
@export var imported_tile_size := 16.0

@export_group("5 · Интерьеры")
## Deprecated import-era flag; saved Cutaways nodes own runtime roof sections.
@export var native_cutaway_enabled := false

var _voxel_mat: ShaderMaterial
var _look: Node3D
var _terrain: Node3D
var _props: Node3D
var _regions: Node3D
var _cutaways: Node3D
var _stats := {
	"props": 0,
	"omni": 0,
	"omni_shadow": 0,
	"missing_mesh": 0,
	"json_mesh": 0,
	"vox_mesh": 0,
	"terrain_cells": 0,
	"width": 0,
	"height": 0,
	"tile_size": 16,
}
var _omni_shadow_ids: Array = []
var _omni_shadow_candidates := 0
var _omni_shadow_active := 0
var _cutaway_sections := 0
var _cutaway_active := 0
var _visual_surface_projection: Node3D


func _apply_test_profile() -> void:
	set_lighting_test_profile(lighting_test_shadows)
	if Engine.is_editor_hint():
		# The singleton is absent from export templates; even a guarded direct
		# class reference prevents this runtime script from parsing in a build.
		Engine.get_singleton("EditorInterface").call("mark_scene_as_unsaved")


func set_lighting_test_profile(shadow_count: int) -> void:
	var allowed := [0, 2, 4, 8, 12, 16]
	var best := 0
	var best_distance := 999
	for candidate in allowed:
		var distance: int = absi(candidate - shadow_count)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	lighting_test_shadows = best
	omni_shadow_count = best
	_omni_shadow_ids.clear()
	notify_property_list_changed()
	apply_authored_lighting()


const WorldPresets = preload("res://content/world_presets/library.tres")
@export_group("Общие пресеты мира")
@export var sky_preset: Sky:
	set(value):
		sky_preset = value
		if is_inside_tree(): apply_world_presets()
@export var weather_preset: Environment:
	set(value):
		weather_preset = value
		if is_inside_tree(): apply_world_presets()
@export var default_npc_model: PackedScene
@export_group("")


func apply_world_presets() -> void:
	var world := _content_node("Look/WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var environment := world.environment
	if sky_preset != null:
		environment.sky = sky_preset
		environment.background_mode = Environment.BG_SKY
	if weather_preset != null:
		environment.fog_enabled = weather_preset.fog_enabled
		environment.fog_density = weather_preset.fog_density
		environment.fog_light_color = weather_preset.fog_light_color


func _ready() -> void:
	apply_world_presets()
	get_tree().node_added.connect(_style_rim_node_added)
	refresh_style_rim.call_deferred()
	_refresh_world_look.call_deferred()
	apply_authored_lighting()
	_refresh_visual_surface_projection()


func apply_authored_lighting() -> void:
	_restore_runtime_shadows()
	if _voxel_mat == null:
		_voxel_mat = EmberVoxelPrefab.voxel_material()
	if _voxel_mat:
		_voxel_mat.set_shader_parameter("local_light_softness", lamp_softness)
	var moon := _content_node("Look/Moon") as DirectionalLight3D
	if moon:
		moon.light_energy = EmberLights.moon_energy(
			sun_intensity, fill_intensity, ambient_alpha, moon_energy_scale
		)
		moon.shadow_enabled = moon_shadows
		EmberLights.tune_moon_shadows(
			moon,
			directional_shadow_distance,
			directional_shadow_splits,
			moon_shadow_bias,
			moon_shadow_normal_bias,
			moon_shadow_blur,
		)
	apply_quality()
	var ts := imported_tile_size if imported_tile_size > 0.0 else 16.0
	var map_range := maxf(ts, lamp_range_tiles * ts * lamp_range_scale)
	var energy := EmberLights.omni_energy(
		lamp_strength0, lamp_falloff, lamp_power * lamp_energy_scale, ambient_alpha
	)
	var col := EmberLights.lamp_point_color(lamp_color, lamp_face_color)
	_tune_look_environment()
	var props := _content_node("Props")
	if props:
		_retune_omnis(props, map_range, energy, col)
		_isolate_lamp_host_shadows(props)
		_omni_shadow_ids.clear()
		refresh_omni_shadow_focus(spawn_world())


func _tune_look_environment() -> void:
	var env_node := _content_node("Look/WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var e := env_node.environment
	# Contact shading belongs to the authored Environment, like exposure.
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	EmberLights.apply_diorama_environment(e,
		_content_node("Look/Sun") as DirectionalLight3D if compact_material_light_mode == 0 else null)


func _apply_compact_material_light() -> void:
	# Godot can retain Nil for newly added exports during a live script reload.
	var mode: int = compact_material_light_mode if typeof(compact_material_light_mode) == TYPE_INT else 0
	var gray: bool = compact_material_gray_preview if typeof(compact_material_gray_preview) == TYPE_BOOL else false
	if is_instance_valid(_visual_surface_projection) and _visual_surface_projection is TerrainProjection:
		_visual_surface_projection.set_material_light(mode, gray)
	if is_inside_tree():
		for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
			if is_ancestor_of(prop):prop.apply_solid_light(mode,gray)
		for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
			if is_ancestor_of(patch): patch.set_material_light(mode,gray)
		_tune_look_environment()
	anomaly_materials_changed.emit()


func refresh_compact_material_light() -> void:
	# Reconcile only new look defaults, preserving the live Sun and terrain draft.
	if typeof(compact_material_light_mode) != TYPE_INT:
		compact_material_light_mode = 0
	if typeof(compact_material_gray_preview) != TYPE_BOOL:
		compact_material_gray_preview = false
	_apply_compact_material_light()


func apply_viewport_quality(viewport: Viewport) -> void:
	if not is_instance_valid(viewport): return
	viewport.msaa_3d = msaa_3d as Viewport.MSAA
	viewport.use_debanding = use_debanding
	# Reapplying quality must not restart temporal accumulation.
	if viewport.use_taa != use_taa: viewport.use_taa = use_taa
	viewport.positional_shadow_atlas_size = clampi(lamp_shadow_size, 512, 8192)


func apply_quality() -> void:
	if not is_inside_tree():
		return
	EmberLights.apply_shadow_atlas(
		directional_shadow_size,
		lamp_shadow_size,
		directional_shadow_filter,
		lamp_shadow_filter,
	)
	apply_viewport_quality(get_viewport())
	quality_changed.emit()
	var follow := get_tree().get_first_node_in_group("ember_follow_camera") as EmberFollowCamera
	if follow:
		follow.cam_near = camera_near
		follow.cam_far = play_camera_far()
		follow.apply_exploration_framing(camera_fov, camera_distance, camera_polar, imported_tile_size)
		follow.look_height = camera_look_height


func play_camera_far() -> float:
	return maxf(50.0, camera_far)


func _content_node(path: String) -> Node:
	var n := get_node_or_null(path)
	if n:
		return n
	return get_node_or_null("Map/%s" % path)


func _isolate_lamp_host_shadows(node: Node) -> void:
	var body := node as MeshInstance3D
	if body and node.name == "ShadowBody":
		body.layers = EmberLights.SHADOW_LAYER_LAMP_HOST
	var omni := node as OmniLight3D
	if omni and omni.visible:
		omni.shadow_caster_mask = EmberLights.SHADOW_LAYER_WORLD
	for child in node.get_children():
		_isolate_lamp_host_shadows(child)


func _retune_omnis(node: Node, map_range: float, energy: float, col: Color) -> void:
	var omni := node as OmniLight3D
	if omni:
		if omni.visible:
			omni.light_color = col
			omni.light_energy = energy
			if lamp_use_map_range:
				omni.omni_range = map_range
		return
	for child in node.get_children():
		_retune_omnis(child, map_range, energy, col)


func refresh_omni_shadow_focus(world: Vector3) -> void:
	var props := _content_node("Props")
	if props == null:
		return
	var lamps: Array = []
	_collect_focus_omnis(props, lamps, world)
	lamps.sort_custom(func(a, b): return a[0] < b[0])
	var budget := mini(omni_shadow_count, EmberLights.MAX_OMNI_SHADOWS)
	if Engine.is_editor_hint() and not preview_local_shadows_in_editor:
		budget = 0
	_omni_shadow_candidates = lamps.size()
	_omni_shadow_active = mini(lamps.size(), budget)
	var next_ids: Array = []
	for i in mini(lamps.size(), budget):
		next_ids.append((lamps[i][1] as OmniLight3D).get_instance_id())
	if next_ids == _omni_shadow_ids:
		return
	_omni_shadow_ids = next_ids
	for i in lamps.size():
		var omni: OmniLight3D = lamps[i][1]
		var want := i < budget
		if omni.shadow_enabled != want:
			omni.shadow_enabled = want
		if want:
			EmberLights.tune_omni_shadows(
				omni,
				lamp_shadow_bias,
				lamp_shadow_normal_bias,
				lamp_shadow_blur,
			)


func omni_shadow_active_count() -> int:
	return _omni_shadow_active


func omni_shadow_candidate_count() -> int:
	return _omni_shadow_candidates


func _collect_focus_omnis(node: Node, lamps: Array, world: Vector3) -> void:
	var omni := node as OmniLight3D
	if omni:
		if omni.visible:
			var parent := omni.get_parent()
			var mid := str(parent.get("model_id")) if parent else ""
			if EmberLights.omni_casts_world_shadow(mid):
				lamps.append([omni.global_position.distance_squared_to(world), omni])
			elif omni.shadow_enabled:
				omni.shadow_enabled = false
		return
	for child in node.get_children():
		_collect_focus_omnis(child, lamps, world)


func has_authored_content() -> bool:
	# A native scene may have no props; its saved ground is authored content.
	# Never fall through to legacy reimport for either ground representation.
	if compact_terrain != null and compact_terrain.validation_errors().is_empty():
		return true
	if resolved_visual_surface() != null:
		return true
	var props := _content_node("Props")
	return props != null and props.get_child_count() > 0


func stats() -> Dictionary:
	return _stats.duplicate()


func refresh_cutaway_runtime() -> int:
	# Bind saved scene-owned volumes. Startup never manufactures geometry from
	# the legacy tile map and must not delete authored Cutaways children.
	_cutaways = _content_node("Cutaways") as Node3D
	_cutaway_sections = 0
	_cutaway_active = 0
	for volume in _cutaway_volumes():
		_cutaway_sections += 1
		if not volume.reveal_changed.is_connected(_on_cutaway_reveal_changed):
			volume.reveal_changed.connect(_on_cutaway_reveal_changed)
		if volume.is_revealed(): _cutaway_active += 1
	return _cutaway_sections


func _cutaway_volumes() -> Array[EmberCutawayVolume]:
	var result: Array[EmberCutawayVolume] = []
	if is_instance_valid(_cutaways): _collect_cutaway_volumes(_cutaways, result)
	return result


func _collect_cutaway_volumes(node: Node, result: Array[EmberCutawayVolume]) -> void:
	for child in node.get_children():
		if child is EmberCutawayVolume: result.append(child as EmberCutawayVolume)
		_collect_cutaway_volumes(child, result)


func cutaway_section_count() -> int:
	return _cutaway_sections


func cutaway_active_count() -> int:
	return _cutaway_active


func set_cutaway_preview(revealed: bool, immediate := false) -> void:
	for volume in _cutaway_volumes(): volume.set_revealed(revealed, immediate)


func _on_cutaway_reveal_changed(_revealed: bool) -> void:
	_cutaway_active = 0
	for volume in _cutaway_volumes():
		if volume.is_revealed(): _cutaway_active += 1


func spawn_world() -> Vector3:
	for region in _region_nodes():
		# Read export, do not call EmberRegion methods (editor placeholders).
		if str(region.get("kind")) == "player_start":
			return safe_spawn_world(_region_position(region))
	return safe_spawn_world(Vector3(16, 8, 16))


func safe_spawn_world(point: Vector3) -> Vector3:
	prepare_physics_destination(point)
	# Terrain authoring can raise land around an unchanged entry marker. Resolve
	# against the same physical surface, without rewriting authored node positions.
	if compact_terrain != null:
		var floor_sample := surface_floor_sample(point)
		if floor_sample.get("solid", false): point.y = maxf(point.y, floor_sample.position.y)
	return point


func region_world(region_id: String) -> Vector3:
	if region_id.is_empty():
		return spawn_world()
	var region := find_region(region_id)
	if region != null:
		return safe_spawn_world(_region_position(region))
	push_warning("ember map %s: spawn region '%s' not found; using player_start" % [map_id, region_id])
	return spawn_world()


func find_region(region_id: String) -> EmberRegion:
	if region_id.is_empty(): return null
	for region in _region_nodes():
		if region.region_id == region_id or str(region.name) == region_id: return region
	return null


func _region_nodes() -> Array[EmberRegion]:
	var result: Array[EmberRegion] = []
	var visited := {}
	# Free regions keep their established order/default spawn. Object-bound
	# entries and triggers then follow their movable building/NPC under Props.
	for branch in [_content_node("Regions"), _content_node("Props")]:
		if branch == null: continue
		var pending: Array[Node] = []
		pending.assign(branch.get_children())
		while not pending.is_empty():
			var node := pending.pop_front() as Node
			if visited.has(node.get_instance_id()): continue
			visited[node.get_instance_id()] = true
			if node is EmberRegion: result.append(node as EmberRegion)
			pending.append_array(node.get_children())
	return result


func _region_position(region: Node3D) -> Vector3:
	if region.is_inside_tree(): return region.global_position
	var position := Vector3.ZERO
	var current: Node = region
	while current != null and current != self:
		if current is Node3D: position = (current as Node3D).transform * position
		current = current.get_parent()
	return position


func refresh_region_runtime() -> void:
	# Scene-owned properties are canonical; only runtime bindings/visuals refresh.
	var tile_size := imported_tile_size if imported_tile_size > 0.0 else 16.0
	for area in _region_nodes():
		if area.is_inside_tree() and not Engine.is_editor_hint():
			area.refresh_runtime_binding()
		area.refresh_chest_visual(tile_size)
	var props := _content_node("Props")
	if props != null:
		_refresh_interact_runtime_bindings(props)


func _refresh_interact_runtime_bindings(node: Node) -> void:
	if node is EmberInteract:
		(node as EmberInteract).refresh_runtime_binding()
	for child in node.get_children():
		_refresh_interact_runtime_bindings(child)


func occupying_region_id(world: Vector3, kinds: Array[String]) -> String:
	for area in _region_nodes():
		if area.kind in kinds and area.contains_world_xz(world):
			return area.region_id
	return ""


func load_map(id: String) -> Dictionary:
	# Explicit editor Reimport only; gameplay never invokes this legacy reader.
	map_id = id
	_clear_generated()
	_reset_stats()
	EmberVoxelPrefab.begin_import()
	var path := EmberPack.map_path(id)
	var data: Variant = EmberPack.parse_json_file(path)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ember map: failed to parse %s" % path)
		return _stats
	var map: Dictionary = data
	var tile_size := float(map.get("tileSize", 16))
	var width := int(map.get("width", 16))
	var height := int(map.get("height", 16))
	_stats.width = width
	_stats.height = height
	_stats.tile_size = tile_size
	imported_tile_size = tile_size
	_voxel_mat = EmberVoxelPrefab.voxel_material()
	_apply_camera(map.get("camera", {}), tile_size)
	var light_cfg: Variant = map.get("light", {})
	_look = _group("Look")
	_terrain = _group("Terrain")
	_props = _group("Props")
	_regions = _group("Regions")
	_add_look(light_cfg, width, height, tile_size)
	_add_terrain(map)
	var region_by_id := _add_regions(map, tile_size)
	var props: Array = map.get("voxelProps", [])
	for place in props:
		if typeof(place) != TYPE_DICTIONARY:
			continue
		_add_prop(place, tile_size, region_by_id)
	print(
		"ember reimport %s: terrain=%s props=%s vox=%s json=%s missing=%s omni=%s shadow=%s pack=%s"
		% [
			id,
			_stats.terrain_cells,
			_stats.props,
			_stats.vox_mesh,
			_stats.json_mesh,
			_stats.missing_mesh,
			_stats.omni,
			_stats.omni_shadow,
			EmberPack.pack_root(),
		]
	)
	apply_authored_lighting()
	_refresh_visual_surface_projection()
	return _stats


func _group(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	_own_root(n)
	return n


func _clear_generated() -> void:
	_visual_surface_projection = null
	for node_name in ["Look", "Terrain", "Props", "Regions", "Cutaways"]:
		var n := get_node_or_null(node_name)
		if n:
			remove_child(n)
			n.free()
	for child in get_children():
		remove_child(child)
		child.free()


func world_surface_matches_map() -> bool:
	return _world_surface_matches(visual_surface)


func resolved_visual_surface() -> EmberVoxelModelResource:
	if compact_terrain != null:
		return null
	## The explicit scene reference wins. When the author has saved the Surface
	## but not the .tscn yet, runtime/editor preview still resolve the one
	## canonical map-owned Resource by map_id instead of silently showing legacy
	## terrain. A bad explicit assignment remains visible as a warning.
	if visual_surface != null:
		return visual_surface if _world_surface_matches(visual_surface) else null
	var path := EmberVoxelModelResource.world_surface_path(map_id)
	if not ResourceLoader.exists(path):
		return null
	var candidate := ResourceLoader.load(path) as EmberVoxelModelResource
	return candidate if _world_surface_matches(candidate) else null


func _world_surface_matches(surface: EmberVoxelModelResource) -> bool:
	if surface == null:
		return false
	var owner := str(surface.material.get("semanticOwner", "")).strip_edges()
	if not owner.is_empty() and owner != map_id:
		return false
	var expected := _expected_world_surface_blocks()
	return (
		expected == Vector2i.ZERO
		or (
			surface.size_blocks.x == expected.x
			and surface.size_blocks.z == expected.y
		)
	)


func smooth_column_limit() -> int:
	return clampi(compact_smooth_study_column_limit,TerrainProjection.SmoothSurface.MAX_COLUMNS,2097152)

func refresh_visual_surface_projection() -> void:
	_refresh_visual_surface_projection()


func surface_floor_sample(global_point: Vector3) -> Dictionary:
	return surface_floor_sample_with_candidates(global_point,null)

func surface_floor_sample_with_candidates(global_point: Vector3, candidates: Variant) -> Dictionary:
	if not is_instance_valid(_visual_surface_projection):
		return {"solid": false}
	var terrain: Dictionary=_visual_surface_projection.call("floor_surface_sample", global_point)
	var solid:=_solid_floor_sample(global_point,candidates)
	var result:Dictionary=solid if solid.get("solid",false) and (not terrain.get("solid",false) or solid.position.y>terrain.position.y) else terrain
	if terrain.has("cell"):
		result["cell"]=terrain.cell
		var document=_visual_surface_projection.document
		if terrain.cell.x>=0 and terrain.cell.y>=0 and terrain.cell.x<document.width and terrain.cell.y<document.depth:
			var index:int=document.column_index(terrain.cell.x,terrain.cell.y)
			var water:int=document.column_value("water_levels",index)
			result["submerged"]=water>document.column_value("heights",index) and result.get("position",global_point).y<_visual_surface_projection.to_global(Vector3(0,document.origin_y+water,0)).y
	return result


func _solid_floor_candidates(bounds:AABB)->Array:
	var candidates:Array=[]
	for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if not is_ancestor_of(prop):continue
		if prop.authoring_preview!=null and is_instance_valid(prop.authoring_preview.get_ref()):candidates.append(prop);continue
		var box:AABB=prop.surface_floor_bounds()
		if box==AABB() or (box.end.x>=bounds.position.x and box.position.x<=bounds.end.x and box.end.z>=bounds.position.z and box.position.z<=bounds.end.z):candidates.append(prop)
	return candidates

func _solid_floor_sample(global_point: Vector3, candidates:Variant=null) -> Dictionary:
	var result: Dictionary={"solid":false}
	if not is_inside_tree():return result
	for prop in get_tree().get_nodes_in_group(&"ember_solid_surface") if candidates==null else candidates:
		if not is_instance_valid(prop) or not is_ancestor_of(prop):continue
		var sample: Dictionary=prop.surface_floor_sample(global_point)
		if sample.get("solid",false) and (not result.get("solid",false) or sample.position.y>result.position.y):result=sample
	return result


func _solid_navigation_revision() -> int:
	var values: Array=[]
	for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if is_ancestor_of(prop):values.append([prop.get_instance_id(),prop.global_transform,prop.get_node("Mesh").mesh.get_instance_id(),prop._floor_revision,prop.get_node("Collision/Shape").disabled,prop.get_node("Collision").collision_layer])
	return hash(values)


func surface_navigation_path(
	global_start: Vector3,
	global_goal: Vector3,
	max_step_voxels := 4,
) -> PackedVector3Array:
	if not is_instance_valid(_visual_surface_projection):
		return PackedVector3Array()
	if _visual_surface_projection is EmberTerrainPilotProjection:
		_visual_surface_projection.object_floor_sampler=_solid_floor_sample
		_visual_surface_projection.set_object_navigation_revision(_solid_navigation_revision())
	return _visual_surface_projection.call(
		"navigation_path", global_start, global_goal, max_step_voxels
	) as PackedVector3Array


func _refresh_visual_surface_projection() -> void:
	if not is_inside_tree():
		return
	var terrain := _editor_terrain_preview if Engine.is_editor_hint() and _editor_terrain_preview != null else compact_terrain
	if terrain != null:
		if not is_instance_valid(_visual_surface_projection) or not _visual_surface_projection is EmberTerrainPilotProjection:
			if is_instance_valid(_visual_surface_projection):
				remove_child(_visual_surface_projection)
				_visual_surface_projection.queue_free()
			_visual_surface_projection = TerrainProjection.new()
			_visual_surface_projection.name = "DerivedCompactWorldTerrain"
			_visual_surface_projection.source = terrain
			_visual_surface_projection.smooth_column_limit = smooth_column_limit()
			_visual_surface_projection.water_visual_material = compact_water_visual_material
			_visual_surface_projection.water_mesh_step = compact_water_mesh_step
			_visual_surface_projection.water_volume_sides = compact_water_volume_sides
			_visual_surface_projection.material_light_mode = compact_material_light_mode
			_visual_surface_projection.material_gray_preview = compact_material_gray_preview
			_visual_surface_projection.set_ground_style(compact_ground_style)
			_visual_surface_projection.set_smooth_material_blend(compact_smooth_material_blend)
			add_child(_visual_surface_projection)
		else:
			_visual_surface_projection.smooth_column_limit = smooth_column_limit()
			_visual_surface_projection.set_ground_style(compact_ground_style)
			_visual_surface_projection.set_smooth_material_blend(compact_smooth_material_blend)
			_visual_surface_projection.open_document(terrain)
		_visual_surface_projection.set_world_look(world_look)
		_visual_surface_projection.scale = Vector3.ONE * (imported_tile_size / float(TerrainResource.CELLS_PER_BLOCK))
		_visual_surface_projection.object_floor_sampler=_solid_floor_sample
		var terrain_visual := _content_node("Terrain/Mesh") as Node3D
		var terrain_collision := _content_node("Terrain/Collision") as StaticBody3D
		if terrain_visual != null:
			terrain_visual.hide()
		if terrain_collision != null:
			terrain_collision.collision_layer = 0
		update_configuration_warnings()
		return
	if not is_instance_valid(_visual_surface_projection):
		_visual_surface_projection = SurfaceProjection.new()
		_visual_surface_projection.name = "DerivedVoxelWorldSurface"
		add_child(_visual_surface_projection)
	var terrain_visual := _content_node("Terrain/Mesh") as Node3D
	var terrain_collision := _content_node("Terrain/Collision") as StaticBody3D
	var expected := _expected_world_surface_blocks()
	var source := _editor_surface_preview if Engine.is_editor_hint() and _editor_surface_preview != null else resolved_visual_surface()
	_visual_surface_projection.position = _editor_surface_origin if Engine.is_editor_hint() and _editor_surface_preview != null else surface_origin
	_visual_surface_projection.call(
		"configure",
		source,
		imported_tile_size,
		expected,
		terrain_visual,
		use_visual_surface_physics or (Engine.is_editor_hint() and _editor_surface_preview != null),
		terrain_collision,
	)
	update_configuration_warnings()


func _expected_world_surface_blocks() -> Vector2i:
	if int(_stats.get("width", 0)) > 0 and int(_stats.get("height", 0)) > 0:
		return Vector2i(int(_stats.width), int(_stats.height))
	if authored_size_blocks.x > 0 and authored_size_blocks.y > 0:
		return authored_size_blocks
	# Inspector deserialization can ask before the saved extent is assigned.
	return Vector2i.ZERO


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var terrain := _editor_terrain_preview if Engine.is_editor_hint() and _editor_terrain_preview != null else compact_terrain
	if terrain != null:
		if visual_surface != null:
			warnings.append("У карты назначены два источника земли. Оставьте только компактную землю.")
		# The projection validates the whole Resource before it queues any tiles.
		# Godot asks for configuration warnings again as derived tile nodes appear;
		# scanning every column on each request would stall the 3D editor frame.
		# Keep trusting that successful projection after the final tile too: its
		# lifetime is not a validation boundary. Save still validates the draft.
		var projecting_validated_terrain: bool = _visual_surface_projection is EmberTerrainPilotProjection \
			and _visual_surface_projection.source == terrain \
			and _visual_surface_projection.document != null \
			and (Engine.is_editor_hint() or _visual_surface_projection.pending_tile_count() > 0)
		# The world editor creates its private draft only after validating the source.
		# Its brushes and Undo write bounded values; Save validates the full draft
		# again. Rechecking millions of columns for Godot's idle warning refresh
		# stalls the first frame after a stroke, even with no tiles left to build.
		var editing_validated_draft: bool = Engine.is_editor_hint() \
			and _editor_terrain_preview != null \
			and _editor_terrain_preview == terrain \
			and _visual_surface_projection is EmberTerrainPilotProjection \
			and _visual_surface_projection.source == terrain \
			and _visual_surface_projection.document != null
		if not projecting_validated_terrain and not editing_validated_draft:
			var validation_started := Time.get_ticks_usec() if editor_warning_timing_enabled else 0
			var validation_errors := terrain.validation_errors()
			if validation_started > 0:
				editor_warning_validation_count += 1
				editor_warning_validation_last_start_usec = validation_started
				editor_warning_validation_last_duration_usec = Time.get_ticks_usec() - validation_started
				editor_warning_validation_usec += editor_warning_validation_last_duration_usec
			warnings.append_array(PackedStringArray(validation_errors))
		var expected := _expected_world_surface_blocks()
		if expected != Vector2i.ZERO and (terrain.width != expected.x * TerrainResource.CELLS_PER_BLOCK or terrain.depth != expected.y * TerrainResource.CELLS_PER_BLOCK):
			warnings.append("Размер компактной земли не совпадает с размером карты: ожидается %dx%d ячеек." % [expected.x * TerrainResource.CELLS_PER_BLOCK,expected.y * TerrainResource.CELLS_PER_BLOCK])
		return warnings
	if visual_surface != null and not world_surface_matches_map():
		var expected := _expected_world_surface_blocks()
		warnings.append(
			"Visual Surface не совпадает с картой %s: ожидается %dx%d блоков и semanticOwner=%s."
			% [map_id, expected.x, expected.y, map_id]
		)
	if use_visual_surface_physics and authored_size_blocks == Vector2i.ZERO:
		warnings.append(
			"Physical Surface требует сохранённый authored_size_blocks, чтобы runtime не зависел от legacy map JSON."
		)
	return warnings


func _reset_stats() -> void:
	_stats.props = 0
	_stats.omni = 0
	_stats.omni_shadow = 0
	_stats.missing_mesh = 0
	_stats.json_mesh = 0
	_stats.vox_mesh = 0
	_stats.terrain_cells = 0


func _edited_owner() -> Node:
	if not Engine.is_editor_hint():
		return self
	var tree := get_tree()
	if tree and tree.edited_scene_root:
		return tree.edited_scene_root
	return self


func _own_root(node: Node) -> void:
	var o := _edited_owner()
	if o:
		node.owner = o


func _own_tree(node: Node) -> void:
	_own_root(node)
	for child in node.get_children():
		_own_tree(child)


func _apply_camera(raw: Variant, tile_size: float) -> void:
	var cfg: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	camera_fov = float(cfg.get("fov", 40.0))
	camera_distance = float(cfg.get("followDistance", clampf(tile_size * 7.5, 96.0, 160.0)))
	camera_polar = float(cfg.get("polarAngle", 0.95))
	camera_yaw = float(cfg.get("yaw", 0.785398))
	camera_look_height = float(cfg.get("lookHeight", 6.0))


func _add_terrain(map: Dictionary) -> void:
	var built: Dictionary = EmberTileMesher.build(map)
	_stats.terrain_cells = int(built.get("cells", 0))
	var mesh := built.get("mesh") as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "Mesh"
	mesh_i.mesh = mesh
	mesh_i.material_override = _voxel_mat
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_terrain.add_child(mesh_i)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	_terrain.add_child(body)
	_own_tree(_terrain)


func _add_look(light: Variant, width: int, height: int, tile_size: float) -> void:
	var cfg: Dictionary = light if typeof(light) == TYPE_DICTIONARY else {}
	var atmo_raw: Variant = cfg.get("atmosphere", {})
	var atmo: Dictionary = atmo_raw if typeof(atmo_raw) == TYPE_DICTIONARY else {}
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var night := clampf(float(cfg.get("ambientAlpha", 0.5)), 0.0, 1.0)
	var fill := float(cfg.get("fillIntensity", 1.0))
	var fog_amt := float(atmo.get("fog", 0.0))
	var fog_col := EmberLights.hex_color(str(atmo.get("fogColor", "#120810")), Color(0.07, 0.03, 0.08))
	var moon_col := EmberLights.hex_color(str(cfg.get("sunColor", "#789ef7")))
	var az := float(cfg.get("sunAzimuth", 40))
	var el := float(cfg.get("sunElevation", 45))
	var dir := EmberLights.sun_direction(az, el)
	var sky_mat := EmberLights.make_sky_material(
		night,
		fog_amt,
		fog_col,
		dir,
		moon_col,
		star_amount,
		moon_disc_size,
		fog_color_mix,
	)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.background_energy_multiplier = sky_energy
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = EmberLights.hex_color(str(cfg.get("ambientColor", "#032472")))
	e.ambient_light_energy = EmberLights.night_ambient_energy(fill, night)
	e.ambient_light_sky_contribution = 0.18
	e.fog_enabled = fog_enabled
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = fog_col.lerp(Color(0.07, 0.086, 0.19), 0.45)
	e.fog_density = EmberLights.fog_density(fog_amt, float(atmo.get("haze", 0.0)))
	e.fog_aerial_perspective = fog_aerial
	e.fog_sky_affect = fog_sky_affect
	e.fog_sun_scatter = fog_sun_scatter
	e.fog_depth_begin = fog_depth_begin
	e.fog_depth_end = fog_depth_end
	e.glow_enabled = true
	e.glow_intensity = clampf(float(cfg.get("bloomStrength", 0.28)) * 1.35, 0.0, 1.2)
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.22
	sun_intensity = float(cfg.get("sunIntensity", 1.0))
	fill_intensity = fill
	ambient_alpha = night
	lamp_power = float(cfg.get("lampPower", 1.0))
	lamp_range_tiles = float(cfg.get("lampRange", 7.0))
	lamp_strength0 = float(cfg.get("lampStrength0", 0.62))
	lamp_falloff = float(cfg.get("lampStrengthFalloff", 0.42))
	lamp_color = EmberLights.hex_color(str(cfg.get("lampColor", "#ffb056")))
	lamp_face_color = EmberLights.hex_color(str(cfg.get("lampFaceColor", "#ff9030")))
	env.environment = e
	_look.add_child(env)
	var moon := EmberLights.make_sun(
		az,
		el,
		moon_col,
		EmberLights.moon_energy(sun_intensity, fill_intensity, ambient_alpha, moon_energy_scale),
		moon_shadows,
	)
	EmberLights.tune_moon_shadows(
		moon,
		directional_shadow_distance,
		directional_shadow_splits,
		moon_shadow_bias,
		moon_shadow_normal_bias,
		moon_shadow_blur,
	)
	var center := Vector3(width * tile_size * 0.5, 12.0, height * tile_size * 0.5)
	moon.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), center + dir * 90.0)
	_look.add_child(moon)
	_own_tree(_look)


func _add_regions(map: Dictionary, tile_size: float) -> Dictionary:
	var by_id := {}
	var regions: Array = map.get("regions", [])
	for raw in regions:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		var rid := str(rec.get("id", ""))
		if rid.is_empty():
			continue
		var x := float(rec.get("x", 0))
		var y := float(rec.get("y", 0))
		var w := maxf(1.0, float(rec.get("w", 1)))
		var h := maxf(1.0, float(rec.get("h", 1)))
		var elev := float(rec.get("elev", 0))
		var area := EmberRegion.new()
		area.name = rid
		area.region_id = rid
		_apply_region_record(area, rec)
		area.position = Vector3(
			(x + w * 0.5) * tile_size,
			elev * tile_size + 2.0,
			(y + h * 0.5) * tile_size,
		)
		area.collision_layer = 4
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(w * tile_size, 8.0, h * tile_size)
		shape.shape = box
		area.add_child(shape)
		_regions.add_child(area)
		area.refresh_chest_visual(tile_size)
		by_id[rid] = rec
	_own_tree(_regions)
	return by_id


func _apply_region_record(area: EmberRegion, rec: Dictionary) -> void:
	area.map_id = map_id
	area.kind = str(rec.get("kind", "trigger"))
	area.target_map_id = str(rec.get("targetMapId", ""))
	area.target_region_id = str(rec.get("targetRegionId", ""))
	area.bound_object_id = str(rec.get("boundObjectId", ""))
	area.script_id = str(rec.get("scriptId", ""))
	area.loot_ids = _region_loot_ids(rec.get("lootIds", []))
	area.closed_model_id = str(rec.get("closedModelId", "")).strip_edges()
	area.open_model_id = str(rec.get("openModelId", "")).strip_edges()
	area.model_offset_x = float(rec.get("modelOffsetX", 0.0))
	area.model_offset_y = float(rec.get("modelOffsetY", 0.0))
	area.model_rot = int(rec.get("modelRot", 0))
	area.model_scale = float(rec.get("modelScale", 1.0))
	area.model_elev = rec.get("modelElev", null)
	area.repeatable = bool(rec.get("repeatable", false))
	area.opened = bool(rec.get("opened", false))
	area.note = str(rec.get("note", ""))


func _region_loot_ids(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = raw if typeof(raw) == TYPE_ARRAY else str(raw).split(",")
	for value in values:
		var item_id := str(value).strip_edges()
		if not item_id.is_empty() and item_id not in result:
			result.append(item_id)
	return result


func _instantiate_prop(model_id: String, tile_size: float) -> EmberVoxelProp:
	var packed := EmberVoxelPrefab.ensure_saved(model_id, tile_size, _stats)
	if packed == null:
		return null
	var edit := PackedScene.GEN_EDIT_STATE_DISABLED
	if Engine.is_editor_hint():
		edit = PackedScene.GEN_EDIT_STATE_INSTANCE
	var prop := packed.instantiate(edit) as EmberVoxelProp
	if prop:
		prop.configure_voxel_scale(prop.voxels_per_block, tile_size)
	return prop


func _add_prop(place: Dictionary, tile_size: float, region_by_id: Dictionary) -> void:
	var model_id := str(place.get("modelId", ""))
	if model_id.is_empty():
		return
	var inst := _instantiate_prop(model_id, tile_size)
	if inst == null:
		return
	var prefab := EmberVoxelPrefab.load_json(model_id)
	var model := EmberVoxelPrefab.model_of(prefab)
	var blocks: Dictionary = model.get("sizeBlocks", {})
	var fw := maxf(1.0, float(blocks.get("x", 1))) * tile_size
	var fd := maxf(1.0, float(blocks.get("z", 1))) * tile_size
	var elev := float(place.get("elev", 0))
	var rot := int(place.get("rot", 0))
	inst.name = str(place.get("id", model_id))
	inst.placement_id = str(place.get("id", ""))
	inst.position = Vector3(
		float(place.get("x", 0)) * tile_size + fw * 0.5,
		elev * tile_size,
		float(place.get("y", 0)) * tile_size + fd * 0.5,
	)
	inst.rotation.y = float(rot) * PI * 0.5
	_tune_lamp(inst, place, model, tile_size)
	_maybe_interact(inst, place, region_by_id, tile_size)
	_props.add_child(inst)
	_own_root(inst)
	var extra := inst.get_node_or_null("Interact")
	if extra:
		_own_tree(extra)
	_stats.props += 1
	var omni := inst.get_node_or_null("Omni") as OmniLight3D
	if omni and omni.visible:
		_stats.omni += 1
		if omni.shadow_enabled:
			_stats.omni_shadow += 1


func _tune_lamp(inst: Node3D, place: Dictionary, model: Dictionary, tile_size: float) -> void:
	var omni := inst.get_node_or_null("Omni") as OmniLight3D
	if omni == null:
		return
	var casts := bool(place.get("emissiveCastsLight", model.get("emissiveCastsLight", false)))
	if not casts:
		omni.visible = false
		omni.shadow_enabled = false
		return
	var can_shadow := bool(place.get("emissiveLightShadows", model.get("emissiveLightShadows", false)))
	var range_tiles := float(place.get("emissiveLightRange", model.get("emissiveLightRange", 2.0)))
	if lamp_use_map_range and can_shadow:
		range_tiles = maxf(range_tiles, lamp_range_tiles)
	range_tiles *= lamp_range_scale
	var strength := float(place.get("emissiveStrength", model.get("emissiveStrength", 0.75)))
	omni.light_color = EmberLights.lamp_point_color(lamp_color, lamp_face_color)
	omni.omni_range = maxf(tile_size, range_tiles * tile_size)
	omni.light_energy = (
		EmberLights.omni_energy(lamp_strength0, lamp_falloff, lamp_power * lamp_energy_scale, ambient_alpha)
		* (0.7 + clampf(strength, 0.0, 1.2) * 0.4)
	)
	# Prefab defaults leave cubes on; ranker enables K nearest lanterns after import.
	omni.shadow_enabled = false


func _maybe_interact(
	inst: Node3D,
	place: Dictionary,
	region_by_id: Dictionary,
	tile_size: float,
) -> void:
	var raw: Variant = place.get("interactivity", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var inter: Dictionary = raw
	var kind := str(inter.get("kind", ""))
	if kind.is_empty():
		return
	var values := {
		"kind": kind,
		"trigger_id": str(inter.get("triggerId", "")),
		"shop_id": str(inter.get("shopId", "")),
		"script_id": str(inter.get("scriptId", "")),
		"quest_id": str(inter.get("questId", "")),
		"icon_id": str(inter.get("iconId", "")),
		"quest_status": str(inter.get("questStatus", "")),
	}
	if not str(values.trigger_id).is_empty() and region_by_id.has(values.trigger_id):
		var region: Dictionary = region_by_id[values.trigger_id]
		values.target_map_id = str(region.get("targetMapId", ""))
		values.target_region_id = str(region.get("targetRegionId", ""))
		values.note = str(region.get("note", ""))
	var area := EmberSceneAuthoring.make_interact(values, tile_size)
	inst.add_child(area)


func _exit_tree() -> void:
	_finish_packed_detail(true)
	_packed_object_index.clear()
	_packed_index_checked = false
	_packed_mesh_failures.clear()
	_restore_runtime_shadows()
	_runtime_shadow_context.clear();_runtime_shadow_lights_dirty=true
	_restore_physics_activity()
	_finish_object_depth(true)
	_finish_object_far(true)
	_finish_object_lod(true)
	if get_tree().node_added.is_connected(_style_rim_node_added):
		get_tree().node_added.disconnect(_style_rim_node_added)

func _style_rim_node_added(node: Node) -> void:
	if node.get_meta(RuntimeShadowLod.DERIVED_PROXY_META,false):return
	if node is Light3D:_runtime_shadow_lights_dirty=true
	if node is GeometryInstance3D: _apply_style_rim_weak.call_deferred(weakref(node))
	if node.has_method("set_world_look") and node != _visual_surface_projection:
		_apply_added_world_look.call_deferred(weakref(node))


func _apply_added_world_look(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node) and is_ancestor_of(node):
		if node is EmberVoxelProp:
			if not _queue_object_look(node):node.restore_object_detail(world_look)
			return
		node.set_world_look(world_look)
		if node.has_method("apply_voxel_light_settings"): node.apply_voxel_light_settings(self)

func _apply_style_rim_weak(reference: WeakRef) -> void:
	# Canvas may remove a transient preview before the deferred binding runs.
	var node:=reference.get_ref() as Node
	if is_instance_valid(node):_apply_style_rim_instance(node)

func refresh_style_rim() -> void:
	if not is_inside_tree(): return
	var scope := get_parent() if get_parent() != null else self
	_apply_style_rim_branch(scope)

func _apply_style_rim_branch(parent: Node) -> void:
	# Derived preview/projection meshes may be internal children.
	for child in parent.get_children(true):
		if child is EmberMapLoader and child!=self:continue
		if child is GeometryInstance3D:_apply_style_rim_instance(child)
		_apply_style_rim_branch(child)

func _apply_style_rim_instance(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	if node.get_meta(RuntimeShadowLod.DERIVED_PROXY_META,false):return
	var scope := get_parent() if get_parent() != null else self
	if not scope.is_ancestor_of(node): return
	var parent := node.get_parent()
	while parent != null and parent != scope:
		if parent is EmberMapLoader and parent != self: return
		parent = parent.get_parent()
	var visual := node as GeometryInstance3D
	var materials: Array[Material] = []
	if visual.material_override != null: materials.append(visual.material_override)
	elif visual is MeshInstance3D and visual.mesh != null:
		for index in visual.mesh.get_surface_count(): materials.append(visual.get_active_material(index))
	elif visual is MultiMeshInstance3D and visual.multimesh != null and visual.multimesh.mesh != null:
		for index in visual.multimesh.mesh.get_surface_count(): materials.append(visual.multimesh.mesh.surface_get_material(index))
	for material in materials:
		if material is ShaderMaterial and material.shader != null:
			var code: String = material.shader.code
			if code.contains("ember_compact_terrain_body.gdshaderinc") or code.contains("ember_stylized_rim.gdshaderinc") or code.contains("ember_painterly_light.gdshaderinc") or code.contains("ember_voxel_toon_body.gdshaderinc"):
				RuntimeShadowLod.forward_instance_parameter(visual,"ember_style_rim_master", compact_style_rim_enabled)
				return
