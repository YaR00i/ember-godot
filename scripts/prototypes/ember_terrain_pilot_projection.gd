@tool
class_name EmberTerrainPilotProjection
extends Node3D
## Shared terrain projection. The editor builds immediate side quads; gameplay
## can coalesce them while using the same authored and physical surface.

signal all_tiles_ready

const TILE_SIZE := 64
const REPEAT_EDIT_BUILD_INTERVAL_US := 50000
const RUNTIME_GROUND_LOD_BIAS := 1.0 # Native camera-space error, one pixel at the default viewport threshold.
const EDIT_GROUND_LOD_BIAS := 100000.0 # Keep fine render indices under the existing brush overlay.
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const RUNTIME_WATER_LOD_BIAS := 0.25
const MeshLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const GeometryCache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const WaterLOD = preload("res://scripts/prototypes/ember_terrain_water_lod.gd")
const GroundLOD = preload("res://scripts/prototypes/ember_terrain_ground_lod.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const LeafCover = preload("res://scripts/ember_ground_leaf_cover.gd")
const TerrainPattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const SmoothSurface = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const LookBake = preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const DetailPolicy = preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const DetailPreparation = preload("res://scripts/ember_detail_preparation.gd")
var detail_policy := DetailPolicy.new()
var _detail_observer_valid := false
var _detail_poll_seconds := 0.0
var _detail_full_tiles: Dictionary = {}
var _detail_requested: Dictionary = {}
var _far_ground_materials:Dictionary={}
var _ground_material_camera:=Vector3.INF
var _ground_material_distance_active:=false
var _resident_tiles:Dictionary={}
var _overview_pending:Array[Vector2i]=[]
var _overview_jobs:Dictionary={}
var _overviews:Dictionary={}
var _overview_dirty:Dictionary={}
var _overview_revision:Dictionary={}
var _overview_sort_needed:=true
var _opening_overview := false
var _resident_tile_slots:Array[Node3D]=[] # Empty attached hosts, never cached geometry/physics.
var _resident_slot_sequence:=0
# Derived render inventory: dry terrain must not pay for a second full-size camera.
# Keep only published nonempty water, including far overviews without local fields.
var _published_water:Dictionary={}

func _track_water(visual:MeshInstance3D)->void:
	if visual.mesh!=null and visual.mesh.get_surface_count()>0:
		_published_water[visual.get_instance_id()]=weakref(visual)
	else:_published_water.erase(visual.get_instance_id())

func _forget_water(host:Node3D)->void:
	var visual:=host.get_node_or_null("Water") as MeshInstance3D
	if visual!=null:_published_water.erase(visual.get_instance_id())

func has_visible_water(camera_mask:int)->bool:
	for reference:WeakRef in _published_water.values():
		var visual:=reference.get_ref() as MeshInstance3D
		if is_instance_valid(visual) and visual.is_inside_tree() and not visual.is_queued_for_deletion() and visual.is_visible_in_tree() and (visual.layers & camera_mask)!=0:
			return true
	return false

func _new_tile_host(host_name:String,resident_slot:=false)->Node3D:
	var tile:=Node3D.new();tile.name=host_name
	for label in ["Ground","Water"]:
		var visual:=MeshInstance3D.new();visual.name=label
		if label == "Ground": visual.layers |= LeafCover.GROUND_LAYER
		visual.lod_bias=(RUNTIME_GROUND_LOD_BIAS if ground_style==1 else 0.25) if label=="Ground" else (1.0 if Engine.is_editor_hint() else RUNTIME_WATER_LOD_BIAS)
		tile.add_child(visual)
	var body:=StaticBody3D.new();body.name="GroundPhysics";tile.add_child(body)
	var shape:=CollisionShape3D.new();shape.name="Shape";body.add_child(shape)
	if resident_slot:
		var edge:=MeshInstance3D.new();edge.name="ResidencyEdge"
		edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;tile.add_child(edge)
		tile.set_meta("_ember_resident_slot",true);tile.hide()
	add_child(tile)
	_profile_add("new_tile_nodes",6 if resident_slot else 5)
	return tile

func _prepare_resident_tile_slots()->void:
	if not _editor_residency_allowed():return
	var capacity:=maxi(1,smooth_column_limit/(TILE_SIZE*TILE_SIZE))
	while _resident_tile_slots.size()+_tiles.size()<capacity:
		var slot:=_new_tile_host("ResidentTerrainSlot_%d"%_resident_slot_sequence,true)
		_resident_slot_sequence+=1;_resident_tile_slots.append(slot)

func _take_tile_host(key:Vector2i)->Node3D:
	if not _editor_residency_allowed():return _new_tile_host("TerrainTile_%d_%d"%[key.x,key.y])
	if not _resident_tile_slots.is_empty():return _resident_tile_slots.pop_back()
	# Protected brush tiles may temporarily exceed the normal resident budget.
	var slot:=_new_tile_host("ResidentTerrainSlot_%d"%_resident_slot_sequence,true)
	_resident_slot_sequence+=1;return slot

func _release_tile_host(tile:Node3D)->void:
	_forget_water(tile)
	var capacity:=maxi(1,smooth_column_limit/(TILE_SIZE*TILE_SIZE))
	if tile.has_meta("_ember_resident_slot") and _editor_residency_allowed() and _resident_tile_slots.size()+_tiles.size()<=capacity:
		for label in ["Ground","Water","ResidencyEdge"]:
			var visual:=tile.get_node(label) as MeshInstance3D
			visual.mesh=null;visual.material_override=null;visual.material_overlay=null
			if visual.has_meta("ember_far_ground_material"):visual.set_meta("ember_far_ground_material",false)
		(tile.get_node("GroundPhysics/Shape") as CollisionShape3D).shape=null
		tile.hide();_resident_tile_slots.append(tile)
	else:remove_child(tile);tile.queue_free()

func _clear_resident_tile_slots()->void:
	for slot:Node3D in _resident_tile_slots:remove_child(slot);slot.queue_free()
	_resident_tile_slots.clear();_resident_slot_sequence=0

static func supports_editor_residency(terrain:TerrainResource,budget:int)->bool:
	return terrain!=null and terrain.is_sectioned() and terrain.width*terrain.depth>budget

func _editor_residency_allowed()->bool:
	return supports_editor_residency(document,smooth_column_limit) and ground_style==1

func _overview_section(key:Vector2i)->Vector2i:
	return Vector2i(key.x/6,key.y/6)

func _far_material(base:ShaderMaterial)->ShaderMaterial:
	var id:=base.get_instance_id()
	if not _far_ground_materials.has(id):_far_ground_materials[id]=Materials.compact_terrain_far_material(base)
	return _far_ground_materials[id]

func _region_ground_material(section:Vector2i)->ShaderMaterial:
	var material:ShaderMaterial=_water_regions.get(section,{}).get("ground")
	return material if material!=null else _ground_material as ShaderMaterial

func _clear_overviews()->void:
	for record:Dictionary in _overview_jobs.values():record.cancellation.set_cancelled(true)
	for record:Dictionary in _overview_jobs.values():WorkerThreadPool.wait_for_task_completion(record.task)
	_overview_jobs.clear();_overview_pending.clear();_overview_dirty.clear();_overview_revision.clear();_resident_tiles.clear()
	for entry:Dictionary in _overviews.values():
		_forget_water(entry.node)
		remove_child(entry.node);entry.node.queue_free()
	_overviews.clear()

func _queue_overview(key:Vector2i)->void:
	if (not _opening_overview and not _editor_residency_allowed()) or not document.sections.has(key):return
	_overview_revision[key]=int(_overview_revision.get(key,0))+1
	if _overview_jobs.has(key):_overview_jobs[key].cancellation.set_cancelled(true)
	if key not in _overview_pending:_overview_pending.append(key)
	_overview_sort_needed=true
	set_process(true)

func _overview_mesh(arrays:Array,patches:Dictionary,covered:Dictionary)->ArrayMesh:
	var mesh:=ArrayMesh.new()
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX].is_empty():return mesh
	var indices:=PackedInt32Array()
	for key:Vector2i in patches:
		if covered.has(key):continue
		var span:Vector2i=patches[key]
		for i in range(span.x,span.x+span.y):indices.append(i)
	if indices.is_empty():return mesh
	var visible_arrays:=arrays.duplicate();visible_arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,visible_arrays)
	return mesh

func _update_overview_ground(entry:Dictionary,covered:Dictionary)->void:
	var ground:MeshInstance3D=entry.node.get_node("Ground")
	var state:Dictionary=entry.get("ground_coverage",{})
	if state.is_empty() or state.revision!=entry.get("revision",0):
		state={"mesh":ArrayMesh.new(),"revision":entry.get("revision",0),"mask":PackedByteArray()}
		entry["ground_coverage"]=state
	var upload:Dictionary=entry.data.get("index_upload",{})
	if upload.is_empty():
		upload=MeshBuilder.prepare_overview_indices(entry.data.arrays,entry.data.patches)
		entry.data["index_upload"]=upload
	var mask:=PackedByteArray();mask.resize(upload.keys.size())
	var visible_patches:=0
	for i in upload.keys.size():
		mask[i]=1 if covered.has(upload.keys[i]) else 0
		if mask[i]==0:visible_patches+=1
	var mesh:ArrayMesh=state.mesh
	if ground.mesh!=mesh:ground.mesh=mesh
	ground.visible=visible_patches>0 and not upload.arrays[Mesh.ARRAY_VERTEX].is_empty()
	if mask==state.mask:return
	state.mask=mask
	# Keep a fully covered region hidden; defer its vertex allocation until needed.
	if not ground.visible:return
	if mesh.get_surface_count()==0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,upload.arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var stride:=RenderingServer.mesh_surface_get_format_index_stride(mesh.surface_get_format(0),mesh.surface_get_array_len(0))
	if stride!=upload.stride:
		# An unexpected engine index format must not corrupt the render buffer.
		ground.mesh=_overview_mesh(entry.data.arrays,entry.data.patches,covered)
		entry.erase("ground_coverage");return
	var bytes:=PackedByteArray()
	for i in upload.keys.size():bytes.append_array(upload.hidden[i] if mask[i]!=0 else upload.chunks[i])
	RenderingServer.mesh_surface_update_index_region(mesh.get_rid(),0,0,bytes)

func _publish_overview(key:Vector2i,covered:Dictionary)->void:
	var entry:Dictionary=_overviews[key]
	var region:Dictionary=_water_regions.get(key,{})
	var ground_material:=_region_ground_material(key)
	var ground:MeshInstance3D=entry.node.get_node("Ground")
	_update_overview_ground(entry,covered)
	ground.material_override=_far_material(ground_material)
	var join:=entry.node.get_node_or_null("ResidencyEdge") as MeshInstance3D
	var closure:=MeshBuilder.overview_edge(document,entry.data,covered)
	if join==null and closure.get_surface_count()>0:
		join=MeshInstance3D.new();join.name="ResidencyEdge";join.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;entry.node.add_child(join)
	if join!=null:join.mesh=closure;join.material_override=ground.material_override
	var water:MeshInstance3D=entry.node.get_node("Water")
	water.mesh=_overview_mesh(entry.data.water_arrays,entry.data.water_patches,covered)
	_track_water(water)
	water.material_override=region.get("water",_water_material);water.visible=not _water_hidden
	_overview_dirty.erase(key)

func _forget_fine_tile(key:Vector2i,restore_overview:=true)->void:
	# Restore the overview first. There is never a frame with neither surface.
	var region:=_overview_section(key)
	if not _overviews.has(region):return
	if restore_overview:
		var covered:=_tiles.duplicate();covered.erase(key)
		_publish_overview(region,covered)
	var tile:Node3D=_tiles[key];_release_tile_host(tile);_tiles.erase(key)
	for data:Dictionary in [_look_meshes,_smooth_fields,_editor_surface_layouts,_detail_full_tiles,_detail_requested,_geometry_keys,_ground_lod_cache,_geometry_requests,_geometry_prepared]:data.erase(key)
	_look_pending.erase(key)
	_profile_add("resident_tiles_released",1)

func _publish_resident_overview(region:Vector2i)->void:
	if _opening_overview:
		_publish_overview(region, _tiles)
		return
	# Re-evaluate at commit, not when the camera requested a release. A quick
	# reversal, brush edit or actor support can retain a formerly departing tile.
	var covered:=_tiles.duplicate()
	var released:Array[Vector2i]=[]
	var entry:Dictionary=_overviews[region]
	if int(entry.get("revision",0))==int(_overview_revision.get(region,0)):
		for key:Vector2i in _tiles:
			if _overview_section(key)==region and not _resident_tiles.has(key):
				covered.erase(key);released.append(key)
	# One synchronous transaction: restore ground/water/seams before releasing
	# any collision or fine field. Other regions retain their actual coverage.
	_publish_overview(region,covered)
	for key:Vector2i in released:_forget_fine_tile(key,false)

func _sync_ground_residency()->void:
	if not _editor_residency_allowed():return
	var protected:Dictionary=_editor_hover_tiles.duplicate()
	protected.merge(_runtime_support)
	for key:Vector2i in _pending:
		if _pending_edit_flags[key.x+key.y*_pending_tile_columns]!=0:protected[key]=true
	var wanted:=detail_policy.ground_candidates(Vector2i(document.width,document.depth),TILE_SIZE,smooth_column_limit,_resident_tiles,protected)
	for key:Vector2i in wanted.keys():
		if not document.has_column(key.x*TILE_SIZE,key.y*TILE_SIZE):wanted.erase(key)
	_resident_tiles=wanted
	for key:Vector2i in _pending.duplicate():
		if wanted.has(key):continue
		var index:=key.x+key.y*_pending_tile_columns
		_pending.erase(key);_pending_flags[index]=0;_pending_edit_flags[index]=0
		_geometry_requests.erase(key);_geometry_prepared.erase(key)
		if _editor_surface_jobs.has(key):_editor_surface_jobs[key].cancellation.set_cancelled(true)
	for key:Vector2i in _tiles:
		if not wanted.has(key) and _overviews.has(_overview_section(key)):
			# Observer polling only coalesces requests. Keep the existing surface
			# and physics until this region receives a publication budget turn.
			_overview_dirty[_overview_section(key)]=true
	for key:Vector2i in _smooth_fields.keys():
		if not wanted.has(key) and not _tiles.has(key):_smooth_fields.erase(key)
	for key:Vector2i in wanted:
		if not _tiles.has(key) and key not in _pending:_queue_tile(key,false)
	_pending_needs_sort=not _pending.is_empty()

func _poll_overviews(frame_started:int,budget_us:int)->void:
	if not _opening_overview and not _editor_residency_allowed():return
	for key:Vector2i in _overview_jobs.keys():
		var record:Dictionary=_overview_jobs[key]
		if not WorkerThreadPool.is_task_completed(record.task):continue
		if Time.get_ticks_usec()-frame_started>=budget_us:return
		WorkerThreadPool.wait_for_task_completion(record.task);_overview_jobs.erase(key)
		if record.revision!=_overview_revision.get(key,0) or record.job.result.is_empty():
			_profile_add("overview_stale",1);continue
		if not _overviews.has(key):
			var node:=Node3D.new();node.name="TerrainOverview_%d_%d"%[key.x,key.y];add_child(node)
			for name in ["Ground","Water"]:
				var visual:=MeshInstance3D.new();visual.name=name;node.add_child(visual)
				if name == "Ground": visual.layers |= LeafCover.GROUND_LAYER
			var edge:=MeshInstance3D.new();edge.name="ResidencyEdge"
			edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(edge)
			_overviews[key]={"node":node}
		_overviews[key].data=record.job.result
		_overviews[key].revision=record.revision
		_publish_resident_overview(key);_profile_add("overview_sections_published",1)
	for key:Vector2i in _overview_dirty.keys():
		if Time.get_ticks_usec()-frame_started>=budget_us:return
		if _overviews.has(key):_publish_resident_overview(key)
		else:_overview_dirty.erase(key)
	# Share the CPU reservation with existing fine jobs, at most one overview worker.
	if _overview_jobs.is_empty() and not _overview_pending.is_empty() and _editor_surface_jobs.size()<clampi(OS.get_processor_count()-4,1,4):
		if _overview_sort_needed:
			_overview_pending.sort_custom(func(a:Vector2i,b:Vector2i):return (Vector2(a*384)+Vector2.ONE*192-detail_policy.anchor).length_squared()<(Vector2(b*384)+Vector2.ONE*192-detail_policy.anchor).length_squared())
			_overview_sort_needed=false
		var key:Vector2i=_overview_pending.pop_front()
		var part:TerrainResource=document.sections[key]
		var job:=MeshBuilder.OverviewJob.new(document.working_copy(),Rect2i(key*384,Vector2i(part.width,part.depth)))
		var cancellation:=MeshLOD.Cancellation.new()
		var task:=WorkerThreadPool.add_task(job.run.bind(cancellation.is_cancelled),false,"Ember terrain overview")
		if task<0:
			_overview_pending.push_front(key)
			_profile_add("overview_worker_failures",1)
			return
		_overview_jobs[key]={"job":job,"task":task,"cancellation":cancellation,"revision":_overview_revision.get(key,0)}

func _editor_detail_camera()->Camera3D:
	if not Engine.is_editor_hint():return get_viewport().get_camera_3d() if is_inside_tree() else null
	var editor:=Engine.get_singleton("EditorInterface")
	if editor==null:return null
	var viewport:=editor.call("get_editor_viewport_3d",0) as SubViewport
	return viewport.get_camera_3d() if viewport!=null else null

func _ground_material_distance_allowed()->bool:
	if not editor_detail_active() or not detail_policy.material_lod_enabled or world_look!=0:return false
	# Local anomaly carriers keep their established material binding until
	# that consumer is integrated into the distance policy in its own slice.
	var anomaly:=get_parent().get_node_or_null("WorldAnomaly")
	return anomaly==null or not (anomaly.get("_prepared") or anomaly.get("_preparing"))

func _apply_ground_distance_material(key:Vector2i,camera:Camera3D,active:bool)->void:
	if not _tiles.has(key):return
	var visual:=(_tiles[key] as Node3D).get_node("Ground") as MeshInstance3D
	var region:Dictionary=_water_regions.get(Vector2i(key.x/6,key.y/6),{})
	var override_material:=region.get("ground") as ShaderMaterial
	var base:ShaderMaterial=override_material if override_material!=null else _ground_material as ShaderMaterial
	var use_far:=false
	if active and camera!=null and visual.mesh!=null and base!=null and base.shader.get_meta("ember_terrain_bank_depth",false):
		var bounds:AABB=visual.global_transform*visual.mesh.get_aabb()
		var nearest:=camera.global_position.clamp(bounds.position,bounds.end)
		var unit:float=get_parent().imported_tile_size if get_parent() is EmberMapLoader else 16.0
		var fade_end:float=float(base.get_shader_parameter("material_depth_fade_far_m"))/unit
		use_far=not detail_policy.material_depth_required(camera.global_position.distance_to(nearest)/unit,fade_end,visual.get_meta("ember_far_ground_material",false))
	if use_far:
		visual.material_override=_far_material(base)
	else:visual.material_override=override_material
	visual.set_meta("ember_far_ground_material",use_far)
	var edge:=(_tiles[key] as Node3D).get_node_or_null("ResidencyEdge") as MeshInstance3D
	if edge!=null:edge.material_override=_far_material(base)

func _update_ground_material_distance(force:=false)->void:
	if not Engine.is_editor_hint():return
	var camera:=_editor_detail_camera()
	if camera==null:return
	var active:=_ground_material_distance_allowed()
	var unit:float=get_parent().imported_tile_size if get_parent() is EmberMapLoader else 16.0
	# Re-evaluate on movement, not every idle frame. The update step is smaller
	# than the safety margin beyond the completely faded depth endpoint.
	if not force and active==_ground_material_distance_active and camera.global_position.distance_to(_ground_material_camera)<0.25*unit:return
	_ground_material_camera=camera.global_position
	_ground_material_distance_active=active
	for key:Vector2i in _tiles:_apply_ground_distance_material(key,camera,active)

func _refresh_far_ground_materials()->void:
	_far_ground_materials.clear()
	for key:Vector2i in _overviews:_overview_dirty[key]=true
	_update_ground_material_distance(true)

func editor_detail_active() -> bool:
	return detail_policy.enabled and _detail_observer_valid and ground_style==1


func editor_ground_opening() -> bool:
	return _opening_overview

func detail_world_anchor() -> Vector3:
	return to_global(Vector3(detail_policy.anchor.x,0,detail_policy.anchor.y))

func _local_detail_area(world_area: Rect2) -> Rect2:
	return DetailPolicy.local_area(world_area, global_transform.affine_inverse(), global_position.y)

func detail_area_resident(world_area: Rect2, retained: bool) -> bool:
	if not editor_detail_active():return true
	return detail_policy.detail_resident(_local_detail_area(world_area), retained)

func detail_area_ready(world_area: Rect2) -> bool:
	var area := _local_detail_area(world_area)
	return _detail_local_area_ready(Vector3(area.position.x, 0, area.position.y), Vector3(area.end.x, 0, area.end.y))

func detail_preparation_band(world_area:Rect2)->int:
	return detail_policy.preparation_band(_local_detail_area(world_area))

func _detail_foreground_ready()->bool:
	if not _detail_observer_valid or _pending_tile_columns<=0:return false
	# The existing travel gate checks this 12x12m core at the camera's ground
	# focus. Once it is ready, farther preparation must leave time for grass.
	var radius:=6.0*detail_policy.cells_per_m
	var low:Vector2=detail_policy.anchor-Vector2.ONE*radius
	var high:Vector2=detail_policy.anchor+Vector2.ONE*radius
	return _detail_local_area_ready(Vector3(low.x,0,low.y),Vector3(high.x,0,high.y))

func _detail_local_area_ready(a:Vector3,b:Vector3)->bool:
	for z in range(floori(minf(a.z,b.z)/TILE_SIZE),floori(maxf(a.z,b.z)/TILE_SIZE)+1):
		for x in range(floori(minf(a.x,b.x)/TILE_SIZE),floori(maxf(a.x,b.x)/TILE_SIZE)+1):
			var key:=Vector2i(x,z)
			if x<0 or z<0 or x>=_pending_tile_columns or z>=_pending_tile_rows:continue
			if not _tiles.has(key) or _pending_flags[x+z*_pending_tile_columns]!=0:return false
	return true

func _detail_full_requested(_key:Vector2i)->bool:
	# Fine arrays stay canonical. Godot chooses render indices using the actual
	# camera, without rebuilding terrain when a camera crosses a distance band.
	return true

var _runtime_start_anchor:=Vector3.INF
var _runtime_support:Dictionary={}

func set_runtime_start_anchor(world_position:Vector3)->void:
	if Engine.is_editor_hint():return
	_runtime_start_anchor=world_position
	_poll_detail_observer(0.0,true)
	set_process(true)

func _runtime_support_tiles(camera:Camera3D)->Dictionary:
	var points:Array[Vector3]=[]
	var map:=get_parent() as EmberMapLoader
	if map!=null:points.append_array(map.runtime_physics_anchors())
	if camera!=null and camera.get_parent() is EmberFollowCamera:
		var actor:Node3D=camera.get_parent().target
		if is_instance_valid(actor):
			points.append(actor.global_position)
			# Existing exploration followers are visual actors following the
			# leader's valid trail; retain their floor queries as well.
			if actor is EmberPlayer and is_instance_valid(actor.party_followers):
				for follower:Node3D in actor.party_followers._followers:
					if is_instance_valid(follower):points.append(follower.global_position)
	if points.is_empty() and _runtime_start_anchor.is_finite():points.append(_runtime_start_anchor)
	var result:Dictionary={}
	for point:Vector3 in points:
		var local:=to_local(point)
		var centre:=Vector2i(floori(local.x/TILE_SIZE),floori(local.z/TILE_SIZE))
		# A 12m support neighbourhood survives an orbit/zoom looking elsewhere.
		for z in range(centre.y-1,centre.y+2):
			for x in range(centre.x-1,centre.x+2):result[Vector2i(x,z)]=true
	return result

func prepare_runtime_body_support(world_position:Vector3)->void:
	if Engine.is_editor_hint() or document==null:return
	var point:=to_local(world_position)
	var centre:=Vector2i(floori(point.x/TILE_SIZE),floori(point.z/TILE_SIZE))
	var changed:=false
	for z in range(centre.y-1,centre.y+2):
		for x in range(centre.x-1,centre.x+2):
			var key:=Vector2i(x,z)
			if not _runtime_support.has(key):_runtime_support[key]=true;changed=true
	if changed:_detail_poll_seconds=0.0;set_process(true)

func _poll_detail_observer(delta:float,force:=false)->void:
	if document==null or not is_inside_tree():return
	_detail_poll_seconds-=delta
	if not force and _detail_poll_seconds>0:return
	_detail_poll_seconds=0.25
	var camera:=_editor_detail_camera()
	var target:Vector3
	if camera==null:
		if Engine.is_editor_hint() or not _runtime_start_anchor.is_finite():return
		target=to_local(_runtime_start_anchor)
	elif not Engine.is_editor_hint() and camera.get_parent() is EmberFollowCamera and is_instance_valid(camera.get_parent().target):
		# Orbit/zoom changes render visibility. Preparation follows the actor.
		target=to_local(camera.get_parent().target.global_position)
	else:
		var ray_origin:=to_local(camera.global_position)
		var ray_direction:=global_basis.inverse()*(-camera.global_basis.z)
		# Stable plane: never derive the next focus from the previous focus.
		var cell:=Vector2i(document.width/2,document.depth/2)
		var height:float=document.origin_y+document.column_value("heights",document.column_index(cell.x,cell.y))
		var t:float=(height-ray_origin.y)/ray_direction.y if absf(ray_direction.y)>0.001 else -1.0
		target=ray_origin+ray_direction*t if t>0 and t<100000 else ray_origin
	if not Engine.is_editor_hint():_runtime_support=_runtime_support_tiles(camera)
	if detail_policy.anchor.distance_to(Vector2(target.x,target.z))>=TILE_SIZE:_overview_sort_needed=true
	detail_policy.anchor=Vector2(target.x,target.z)
	DetailPreparation.for_projection(self).invalidate_detail_poll()
	camera_anchor=Vector2i(detail_policy.anchor)
	_detail_observer_valid=true
	_sync_ground_residency()
	if ground_style==1:
		for key:Vector2i in _tiles:
			_apply_ground_lod_bias(key)
	var observed:Dictionary=_tiles.duplicate()
	for key:Vector2i in _editor_surface_jobs:observed[key]=true
	for key:Vector2i in observed:
		var full:=_detail_full_requested(key)
		if (_tiles.has(key) or _editor_surface_jobs.has(key)) and full!=_detail_requested.get(key,_detail_full_tiles.get(key,true)):
			_detail_requested[key]=full
			_editor_surface_layouts.erase(key)
			_queue_tile(key,false)
	_pending_needs_sort=not _pending.is_empty()
var world_look := -1
var _look_meshes: Dictionary = {}
var _look_pending: Array[Vector2i] = []


func set_world_look(value: int) -> void:
	if world_look == value: return
	world_look = value
	if value == 2 and _opening_overview:
		_opening_overview = false
		_clear_overviews()
	_look_pending.assign(_tiles.keys())
	_refresh_look_materials()
	set_process(true)


func _refresh_look_materials() -> void:
	if _water_material is ShaderMaterial:
		_water_material.set_shader_parameter("sea_smooth_shore", ground_style == 1 and world_look == 0)
	if _ground_material is ShaderMaterial:
		_bind_depth_material(_ground_material)
		_ground_material.set_shader_parameter("smooth_surface_enabled", ground_style == 1 and world_look != 2)
		Materials.refresh_terrain_features(_ground_material)
	for region: Dictionary in _water_regions.values():
		var water: ShaderMaterial = region.get("water")
		if water != null: water.set_shader_parameter("sea_smooth_shore", ground_style == 1 and world_look == 0)
		var material: ShaderMaterial = region.get("ground")
		if material != null:
			_bind_depth_material(material)
			material.set_shader_parameter("smooth_surface_enabled", ground_style == 1 and world_look != 2)
			Materials.refresh_terrain_features(material)
	_refresh_far_ground_materials()


func _bind_depth_material(material: ShaderMaterial) -> void:
	if get_parent() is EmberMapLoader:
		get_parent().bind_voxel_light(material, world_look, get_parent().imported_tile_size)
	# Working ground uses the existing compiled no-POM/no-DEPTH path at every
	# distance. Preset depth remains available to solid-object materials.
	if not material.shader.get_meta("ember_terrain_cheap", false):
		material.shader = Materials.compact_terrain_bank_far_shader()
		if document != null:
			Materials.set_compact_terrain_roles(material, document.palette_surface_roles, document.palette_material_ids, document.palette)
	var unit: float = get_parent().imported_tile_size if get_parent() is EmberMapLoader else 16.0
	material.set_shader_parameter("ember_texture_world_unit", unit)
	material.set_shader_parameter("terrain_world_look", world_look)
	material.set_shader_parameter("look_study_mode", maxi(0,world_look))
	material.set_shader_parameter("look_study_pixel_m", unit / 16.0)


func _apply_tile_look(key: Vector2i) -> void:
	if not _tiles.has(key) or not _look_meshes.has(key): return
	var variants: Dictionary = _look_meshes[key]
	var visual := (_tiles[key] as Node3D).get_node("Ground") as MeshInstance3D
	if world_look <= 0 or ground_style != 1:
		visual.mesh = variants[0]
		return
	visual.mesh = prepared_look_mesh(key, world_look)


## Shared preparation for whole-map and local looks. The sphere never calls
## this while moving; both endpoints are ready before its field is enabled.
func _canonical_look_mesh(key:Vector2i)->ArrayMesh:
	# Alternate appearances and anomaly carriers retain their established fine
	# topology, even when the ordinary flat render surface is only two triangles.
	if not _editor_surface_layouts.has(key):return _look_meshes[key][0]
	var arrays:Array=_editor_surface_layouts[key].arrays.duplicate()
	if document.is_sectioned():
		var input:=MeshBuilder.editor_surface_input(document,key.x*TILE_SIZE,key.y*TILE_SIZE,TILE_SIZE)
		arrays[Mesh.ARRAY_VERTEX]=Transform3D(Basis.IDENTITY,Vector3(input.start.x,0,input.start.y))*(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	return SmoothSurface.publish_render_mesh(arrays)

func prepared_look_mesh(key: Vector2i, look: int) -> ArrayMesh:
	var variants: Dictionary = _look_meshes[key]
	if not variants.has(look):
		var base: ArrayMesh = variants[0]
		if base.get_surface_count() == 0: return base
		variants[look] = LookBake.faceted(_canonical_look_mesh(key), _smooth_field(key),8,document).mesh if look == 1 else MeshBuilder.build_tile(document, key.x*TILE_SIZE, key.y*TILE_SIZE, TILE_SIZE, 0, false, PackedVector4Array(), {}, true).terrain
		(variants[look] as ArrayMesh).surface_set_material(0, _ground_material)
	return variants[look]


func prepared_anomaly_meshes(key: Vector2i, host: Node) -> Dictionary:
	var variants: Dictionary = _look_meshes[key]
	if not variants.has("anomaly"):
		var start := key*TILE_SIZE
		var bounds := Rect2i(start,Vector2i(mini(TILE_SIZE,document.width-start.x),mini(TILE_SIZE,document.depth-start.y)))
		var storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd").new()
		storage.directory = "user://ember-anomaly-cache"
		storage.max_bytes = 128*1024*1024
		# Include the complete local halo, not the whole document/revision.
		# Risers depend on raw heights as well as the smoothed reference mesh.
		var part = document.dense_window(bounds.grow(SmoothSurface.HALO).intersection(Rect2i(0,0,document.width,document.depth)))
		var field := _smooth_field(key)
		var canonical:=_canonical_look_mesh(key)
		var cache_key: String = storage.digest([LookBake.ANOMALY_CACHE_VERSION,Engine.get_version_info().hex,bounds,document.width,document.depth,document.origin_y,part.heights,part.top_materials,field,canonical.surface_get_arrays(0)])
		var saved: Dictionary = storage.read(cache_key)
		var meshes: Dictionary = {}
		if saved.get("terrain_carriers") is Array and saved.terrain_carriers.size() == 3:
			for look in 3:
				var mesh := ArrayMesh.new()
				mesh.set("_surfaces",saved.terrain_carriers[look])
				meshes[look] = mesh
		else:
			meshes = await LookBake.anomaly_carrier(canonical,prepared_look_mesh(key,1),document,field,bounds,host)
			if meshes.is_empty() or not host.anomaly_preparation_valid(): return {}
			storage.write(cache_key,{"terrain_carriers":[meshes[0].get("_surfaces"),meshes[1].get("_surfaces"),meshes[2].get("_surfaces")]},func(): return not host.anomaly_preparation_valid())
			storage.trim(256*1024*1024)
		variants["anomaly"] = meshes
	return variants.anomaly


func _resize_look_cache(offset: Vector2i) -> void:
	_look_pending.clear()
	if offset != Vector2i.ZERO:
		# Retained tile vertices still use the previous origin. Rebuild these
		# through the ordinary chunk budget before deriving another appearance.
		_look_meshes.clear()
		for key: Vector2i in _tiles: _queue_tile(key, false)
	else:
		for key: Vector2i in _look_meshes.keys():
			if not _tiles.has(key): _look_meshes.erase(key)
var smooth_material_blend_enabled := false
var ground_style := 0 # Scene-owned by MapLoader: 0 old steps, 1 fine-grid smooth.
var smooth_column_limit := SmoothSurface.MAX_COLUMNS # Explicit scene study opt-in.
var _smooth_fields := {}
var _query_field:Dictionary={}
var _query_field_key:=Vector2i(-1,-1)
var _query_field_revision:=-1
var _query_point:Dictionary={}
var _query_point_tasks:Dictionary={}

class PointQueryJob extends RefCounted:
	var result:Dictionary={}
	var _snapshot:Resource
	var _cell:Vector2i
	var _offset:Vector2i
	func _init(source:Resource,cell:Vector2i)->void:
		var halo:=SmoothSurface.HALO
		var bounds:=Rect2i(cell-Vector2i.ONE*halo,Vector2i.ONE*(halo*2+2)).intersection(Rect2i(0,0,source.width,source.depth))
		_snapshot=source.dense_window(bounds);_offset=bounds.position;_cell=cell-_offset
	func run()->void:
		# Private CPU Resource only: no live document, Nodes or rendering calls.
		result=SmoothSurface.field(_snapshot,Rect2i(_cell,Vector2i.ONE))
		result.start+=_offset
		_snapshot=null
var _editor_surface_layouts: Dictionary = {}
var _editor_surface_jobs: Dictionary = {}
var _editor_brush_epoch := 0
var _editor_brush_center := Vector2i.ZERO
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")

@export var source: TerrainResource
@export var camera_anchor := Vector2i(192, 200)
@export var water_visual_material: ShaderMaterial
@export_range(0, 16, 1) var water_mesh_step := 0
@export var water_volume_sides := false
var material_light_mode := 0
var material_gray_preview := false
var document: TerrainResource
var first_tile_ms := -1
var all_tiles_ms := -1
var _started_ms := 0
var _last_process_started_us := 0
var _tiles: Dictionary = {}
var _pending: Array[Vector2i] = []
var _pending_flags := PackedByteArray()
var _pending_edit_flags := PackedByteArray()
var _pending_since_us := PackedInt64Array()
var _last_edit_build_us := PackedInt64Array()
var _pending_tile_columns := 0
var _pending_tile_rows := 0
var _pending_needs_sort := false
var _repeat_edit_build_interval_us := REPEAT_EDIT_BUILD_INTERVAL_US
var _live_brush_active := false
var _tile_revisions := PackedInt32Array()
var _surface_tile_revisions := PackedInt32Array()
var _ground_material: Material
var _water_material: Material
var _water_hidden := false
var _water_revision := 0
var _water_surface_offset_voxels := 0.0
var _sea_swash: RefCounted
var _waterfall: RefCounted
var _wave_obstacles: RefCounted
var _navigation_grid := {}
var object_floor_sampler: Callable
var _object_navigation_revision := 0

func set_object_navigation_revision(value: int) -> void:
	if value!=_object_navigation_revision:
		_object_navigation_revision=value;_navigation_grid.clear()

func _physical_height(point: Vector2, terrain_height: float) -> float:
	if object_floor_sampler.is_valid():
		var sample: Dictionary=object_floor_sampler.call(to_global(Vector3(point.x,terrain_height,point.y)))
		if sample.get("solid",false):return maxf(terrain_height,to_local(sample.position).y)
	return terrain_height
var _column_revision := 0
var _editor_hidden_edge_keys := {}
var _editor_hover_overlay: Material
var _editor_hover_tiles := {}
var _profile: Dictionary = {}
var _water_regions := {}
var _staged_water_fields: RefCounted
## Runtime-only derived policy. Never serialized into the authored Resource.
var runtime_ground_lod_enabled := true
var runtime_water_mesh_optimization := true
var runtime_water_lod_enabled := true
var runtime_geometry_cache_enabled := true
var runtime_geometry_cache_directory := GeometryCache.ROOT
var _geometry_cache: RefCounted
var _geometry_keys := {}
var _geometry_prepared := {}
var _geometry_requests := {}
var _geometry_request_serial := 0
var _geometry_snapshot: TerrainResource
var _geometry_snapshot_revision := -1
var _geometry_prepare_disabled := false # Thread-start failure keeps the exact synchronous fallback.
var _mesh_lod_jobs := {}
var _ground_lod_cache := {}
var _mesh_lod_thread := Thread.new()
var _mesh_lod_cancellation := MeshLOD.Cancellation.new()
var _mesh_lod_in_flight := 0
var _mesh_lod_results: Array = []
var _mesh_lod_cursor := 0


func _ready() -> void:
	add_to_group(&"ember_water_surface_projection")
	_ground_material = Materials.compact_terrain_material()
	set_material_light(material_light_mode, material_gray_preview)
	_water_material = (water_visual_material if water_visual_material != null else Materials.water_material()).duplicate() as Material
	(_water_material as ShaderMaterial).set_shader_parameter("coordinate_scale", float(TerrainResource.CELLS_PER_BLOCK))
	if document != null:
		_refresh_material_atlas()
	if source != null:
		open_document(source)


func _exit_tree() -> void:
	DetailPreparation.release_projection(self)
	_cancel_mesh_lods()


func _cancel_mesh_lods() -> void:
	_preview_tiles_to_publish = {}
	_opening_overview = false
	_editor_fingerprint_memo = null
	_clear_overviews()
	for task:int in _query_point_tasks:WorkerThreadPool.wait_for_task_completion(task)
	_query_point_tasks.clear()
	_query_field.clear();_query_field_revision=-1;_query_point.clear()
	for job: Dictionary in _editor_surface_jobs.values():job.cancellation.set_cancelled(true)
	for job: Dictionary in _editor_surface_jobs.values():
		if job.task>=0:WorkerThreadPool.wait_for_task_completion(job.task)
	_editor_surface_jobs.clear()
	_editor_surface_layouts.clear()
	_mesh_lod_cancellation.set_cancelled(true)
	if _mesh_lod_thread.is_started(): _mesh_lod_thread.wait_to_finish()
	_mesh_lod_jobs.clear()
	_ground_lod_cache.clear()
	_mesh_lod_results.clear()
	_mesh_lod_cursor = 0
	_mesh_lod_in_flight = 0
	_mesh_lod_cancellation.set_cancelled(false)
	_geometry_keys.clear()
	_geometry_cache = null
	_geometry_prepared.clear()
	_geometry_requests.clear()
	_geometry_snapshot = null
	_geometry_snapshot_revision = -1
	_geometry_prepare_disabled = false


func _configure_lod_cache(job: Dictionary) -> void:
	if not runtime_geometry_cache_enabled or runtime_geometry_cache_directory.is_empty() or _geometry_cache == null or not _geometry_keys.has(job.key): return
	job.cache_directory = runtime_geometry_cache_directory
	job.cache_key = GeometryCache.lod_key(_geometry_keys[job.key], job.kind)


func pending_runtime_lod_count() -> int:
	return _mesh_lod_jobs.size() + _mesh_lod_in_flight + _mesh_lod_results.size() - _mesh_lod_cursor


func _uses_geometry_preparation() -> bool:
	return not Engine.is_editor_hint() and ground_style!=1 and runtime_geometry_cache_enabled and not runtime_geometry_cache_directory.is_empty() and not _geometry_prepare_disabled


func _start_geometry_preparation() -> void:
	if not _uses_geometry_preparation() or _pending.is_empty() or not _geometry_prepared.is_empty(): return
	if _geometry_cache == null: _geometry_cache = GeometryCache.new()
	_geometry_cache.directory = runtime_geometry_cache_directory
	if _geometry_snapshot_revision != _column_revision:
		# Sectioned working_copy shares persistent payloads, not its mutable root.
		# Dense maps receive private arrays once per revision, never once per tile.
		_geometry_snapshot = document.working_copy()
		_geometry_snapshot_revision = _column_revision
	var jobs := []
	var swash_tiles: Dictionary = _staged_water_fields.pending_dry_tiles() if _staged_water_fields != null else (_sea_swash.dry_tiles if _sea_swash != null else {})
	var fall: RefCounted = _staged_water_fields.waterfall if _staged_water_fields != null else _waterfall
	for i in mini(GeometryCache.PREPARE_TILES, _pending.size()):
		var key: Vector2i = _pending[i]
		jobs.append({"key": key, "request": _geometry_requests.get(key, 0),
			"policy": _geometry_policy(),
			"swash": (swash_tiles.get(key, PackedVector4Array()) as PackedVector4Array).duplicate(),
			"sheet": (fall.tiles.get(key, {}) as Dictionary).duplicate(true) if fall != null else {}})
	_mesh_lod_in_flight = jobs.size()
	var error := _mesh_lod_thread.start(_geometry_cache.prepare_batch.bind(_geometry_snapshot, jobs, _column_revision, _mesh_lod_cancellation.is_cancelled), Thread.PRIORITY_LOW)
	if error != OK:
		_mesh_lod_in_flight = 0
		_geometry_prepare_disabled = true
		_profile_add("geometry_prepare_worker_failures", 1)
	else:
		_profile_add("geometry_prepare_batches", 1)


func _queue_ground_lod(key: Vector2i, mesh: ArrayMesh, source_arrays: Array = []) -> ArrayMesh:
	if ground_style == 1 or Engine.is_editor_hint() or not runtime_ground_lod_enabled or mesh.get_surface_count() == 0: return mesh
	var cached: Dictionary = _ground_lod_cache.get(key, {})
	if not cached.is_empty() and int(cached.revision) == _column_revision: return cached.mesh
	var arrays := _lod_arrays(mesh, source_arrays)
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < GroundLOD.MIN_INDICES: return mesh
	_mesh_lod_jobs[Vector3i(key.x, key.y, 0)] = {"key": key, "kind": "ground", "builder": GroundLOD.build, "mesh": mesh, "arrays": arrays, "revision": _column_revision,
		"bounds": Rect2i(key * TILE_SIZE, Vector2i(mini(TILE_SIZE, document.width - key.x * TILE_SIZE), mini(TILE_SIZE, document.depth - key.y * TILE_SIZE)))}
	_configure_lod_cache(_mesh_lod_jobs[Vector3i(key.x, key.y, 0)])
	return mesh


func _queue_water_lod(key: Vector2i, mesh: ArrayMesh, source_arrays: Array = []) -> ArrayMesh:
	if Engine.is_editor_hint() or not runtime_water_lod_enabled or mesh.get_surface_count() == 0: return mesh
	var arrays := _lod_arrays(mesh, source_arrays)
	if mesh.surface_get_array_index_len(0) < WaterLOD.MIN_INDICES: return mesh
	# Water can remesh after shoreline fields change without a column revision.
	# Coalesce queued jobs by tile, but never reuse a ground-revision-only cache.
	_mesh_lod_jobs[Vector3i(key.x, key.y, 1)] = {"key": key, "kind": "water", "builder": WaterLOD.build,
		"mesh": mesh, "arrays": arrays, "revision": _water_revision,
		"bounds": Rect2i(key * TILE_SIZE, Vector2i(mini(TILE_SIZE, document.width - key.x * TILE_SIZE), mini(TILE_SIZE, document.depth - key.y * TILE_SIZE)))}
	_configure_lod_cache(_mesh_lod_jobs[Vector3i(key.x, key.y, 1)])
	return mesh


func _lod_arrays(mesh: ArrayMesh, source_arrays: Array) -> Array:
	if not source_arrays.is_empty(): return source_arrays
	# Exact fallback without the geometry cache still uses the old mesh path.
	var started := Time.get_ticks_usec()
	var arrays := mesh.surface_get_arrays(0)
	_profile_add("runtime_lod_array_readbacks", 1)
	_profile_add("runtime_lod_array_readback_us", Time.get_ticks_usec() - started)
	return arrays


func _poll_mesh_lods(frame_started: int) -> void:
	if _mesh_lod_thread.is_started() and not _mesh_lod_thread.is_alive():
		_mesh_lod_results = _mesh_lod_thread.wait_to_finish()
		_mesh_lod_in_flight = 0
		_mesh_lod_cursor = 0
		var prepared_count := 0
		var prepared_size := 0
		for result: Dictionary in _mesh_lod_results:
			if result.kind == "geometry":
				prepared_count += 1
				prepared_size += GeometryCache.prepared_bytes(result.data)
		_profile["geometry_prepare_max_tiles"] = maxi(int(_profile.get("geometry_prepare_max_tiles", 0)), prepared_count)
		_profile["geometry_prepare_max_bytes"] = maxi(int(_profile.get("geometry_prepare_max_bytes", 0)), prepared_size)
	while _mesh_lod_cursor < _mesh_lod_results.size() and Time.get_ticks_usec() - frame_started < 4000:
		var result: Dictionary = _mesh_lod_results[_mesh_lod_cursor]
		_mesh_lod_results[_mesh_lod_cursor] = null
		_mesh_lod_cursor += 1
		if result.kind == "geometry":
			_profile_add("geometry_prepare_jobs", 1)
			_profile_add("geometry_cache_key_us", int(result.key_us))
			_profile_add("geometry_cache_read_us", int(result.read_us))
			_profile_add("geometry_cache_invalid", int(result.cache_invalid))
			_profile_add("geometry_cache_failures", int(result.cache_failures))
			for phase in ["decode", "validate"]:
				_profile_add("geometry_cache_" + phase + "_us", int(result.data.get("cache_" + phase + "_us", 0)))
			if result.request != _geometry_requests.get(result.key, 0):
				_profile_add("geometry_prepare_stale", 1)
			else:
				_geometry_prepared[result.key] = result
			continue
		if result.kind == "cache_maintenance":
			_profile_add("geometry_cache_trim_us", int(result.cpu_us))
			continue
		var prefix: String = result.kind + "_lod_"
		_profile_add(prefix + "jobs", 1)
		_profile_add(prefix + "cpu_us", int(result.cpu_us))
		_profile[prefix + "max_job_us"] = maxi(int(_profile.get(prefix + "max_job_us", 0)), int(result.cpu_us))
		if result.has("cache_hit"):
			_profile_add(prefix + "cache_hits" if result.cache_hit else prefix + "cache_misses", 1)
			_profile_add("geometry_cache_lod_us", int(result.cache_us))
			_profile_add("geometry_cache_invalid", int(result.cache_invalid))
			_profile_add("geometry_cache_failures", int(result.cache_failures))
			_profile_add("geometry_cache_written_bytes", int(result.cache_written_bytes))
		var tile := _tiles.get(result.key) as Node3D
		if tile == null: continue
		var instance := tile.get_node("Ground" if result.kind == "ground" else "Water") as MeshInstance3D
		if instance.mesh != result.mesh:
			_profile_add(prefix + "stale_results", 1)
			continue
		var started := Time.get_ticks_usec()
		var mesh := result.mesh as ArrayMesh
		if int(result.levels) > 0:
			var derived := ArrayMesh.new()
			derived.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result.arrays, [], result.lods)
			derived.surface_set_material(0, mesh.surface_get_material(0))
			mesh = derived
			instance.mesh = mesh
			_profile_add(prefix + "tiles", 1)
			_profile_add(prefix + "levels", int(result.levels))
			_profile_add(prefix + "saved_indices", int(result.base_indices) - int(result.far_indices))
			_profile_add(prefix + "extra_index_bytes", int(result.extra_index_bytes))
		if result.kind == "ground": _ground_lod_cache[result.key] = {"revision": result.revision, "mesh": mesh}
		var elapsed := Time.get_ticks_usec() - started
		_profile_add(prefix + "publish_us", elapsed)
		_profile[prefix + "max_publish_us"] = maxi(int(_profile.get(prefix + "max_publish_us", 0)), elapsed)
	if _mesh_lod_cursor == _mesh_lod_results.size():
		_mesh_lod_results.clear()
		_mesh_lod_cursor = 0
	if not _mesh_lod_thread.is_started() and _mesh_lod_results.is_empty():
		if _uses_geometry_preparation() and not _pending.is_empty(): _start_geometry_preparation()
	if not Engine.is_editor_hint() and _pending.is_empty() and not _mesh_lod_thread.is_started() and _mesh_lod_results.is_empty() and not _mesh_lod_jobs.is_empty():
		var jobs := _mesh_lod_jobs.values()
		_mesh_lod_jobs.clear()
		_mesh_lod_in_flight = jobs.size()
		var error := _mesh_lod_thread.start(MeshLOD.build_batch.bind(jobs, _mesh_lod_cancellation), Thread.PRIORITY_LOW)
		if error != OK:
			_mesh_lod_in_flight = 0
			_profile_add("mesh_lod_worker_failures", 1) # Exact mesh is the fallback.
	if _pending.is_empty() and not _mesh_lod_thread.is_started():
		_geometry_snapshot = null
		_geometry_snapshot_revision = -1
	if _pending.is_empty() and pending_runtime_lod_count() == 0:
		_profile["runtime_mesh_ready_ms"] = Time.get_ticks_msec() - _started_ms


func set_material_light(mode: int, gray_preview: bool) -> void:
	material_light_mode = clampi(mode, 0, 2)
	material_gray_preview = gray_preview
	if _ground_material is ShaderMaterial:
		(_ground_material as ShaderMaterial).set_shader_parameter("material_light_mode", material_light_mode)
		(_ground_material as ShaderMaterial).set_shader_parameter("material_gray_preview", material_gray_preview)
		Materials.refresh_existing_terrain_features(_ground_material as ShaderMaterial)
	for region: Dictionary in _water_regions.values():
		var ground: ShaderMaterial = region.get("ground")
		if ground != null:
			ground.set_shader_parameter("material_light_mode", material_light_mode)
			ground.set_shader_parameter("material_gray_preview", material_gray_preview)
			Materials.refresh_existing_terrain_features(ground)
	_refresh_far_ground_materials()


func _geometry_policy() -> Array:
	var policy: Array=[water_mesh_step, water_volume_sides, runtime_water_mesh_optimization, runtime_ground_lod_enabled, runtime_water_lod_enabled, ground_style]
	if ground_style==1 and smooth_material_blend_enabled:policy.append("material-blend-v1")
	if ground_style==1:policy.append("smooth-shore-v1")
	return policy

func set_smooth_material_blend(next: bool) -> void:
	if smooth_material_blend_enabled==next:return
	smooth_material_blend_enabled=next
	if document==null:return
	var current:=source
	document=null
	open_document(current)

func set_ground_style(next: int) -> void:
	next = clampi(next,0,1)
	if next == 1 and source != null and source.width*source.depth > smooth_column_limit and not supports_editor_residency(source,smooth_column_limit): return
	if ground_style == next: return
	ground_style = next
	_smooth_fields.clear()
	if document == null: return
	var current := source
	document = null # Style changes rebuild the same source through its one owner.
	open_document(current)


func _smooth_field(key: Vector2i) -> Dictionary:
	# Offline authoring/floor queries remain valid outside resident physics.
	# Keep only the last such field, rather than accumulating a whole world.
	if _editor_residency_allowed() and not _resident_tiles.has(key) and not _tiles.has(key):
		if key!=_query_field_key or _query_field_revision!=_column_revision:
			var begin:=key*TILE_SIZE
			_query_field=SmoothSurface.field(document,Rect2i(begin,Vector2i(mini(TILE_SIZE,document.width-begin.x),mini(TILE_SIZE,document.depth-begin.y))))
			_query_field_key=key;_query_field_revision=_column_revision
		return _query_field
	if not _smooth_fields.has(key):
		var begin := key*TILE_SIZE
		_smooth_fields[key] = SmoothSurface.field(document,Rect2i(begin,Vector2i(mini(TILE_SIZE,document.width-begin.x),mini(TILE_SIZE,document.depth-begin.y))))
	return _smooth_fields[key]


func _smooth_height(point: Vector2) -> float:
	var key:=Vector2i(floori(point.x/TILE_SIZE),floori(point.y/TILE_SIZE))
	if _smooth_fields.has(key):return SmoothSurface.sample(_smooth_fields[key],point)
	if key==_query_field_key and _query_field_revision==_column_revision:return SmoothSurface.sample(_query_field,point)
	# Streaming callers can prepare just these exact corners. Other callers
	# retain full-tile caching, which is important for dense authoring/navigation.
	var cell:=Vector2i(point.floor())
	if not _query_point.is_empty() and _query_point.cell==cell and _query_point.revision==_column_revision and _query_point.document==document.get_instance_id():return SmoothSurface.sample(_query_point.field,point)
	return SmoothSurface.sample(_smooth_field(key),point)

func prepare_floor_query(global_point:Vector3)->bool:
	# Streaming callers prepare a bounded CPU snapshot before their ordinary
	# synchronous surface/object query. At most one point task per projection.
	if document==null:return false
	if ground_style!=1:return true
	var local:=to_local(global_point);var cell:=Vector2i(floori(local.x),floori(local.z))
	if cell.x<0 or cell.y<0 or cell.x>=document.width or cell.y>=document.depth:return false
	var key:=Vector2i(cell.x/TILE_SIZE,cell.y/TILE_SIZE)
	if _smooth_fields.has(key) or (key==_query_field_key and _query_field_revision==_column_revision):return true
	var revision:=_column_revision;var document_id:=document.get_instance_id()
	while not _query_point_tasks.is_empty():
		await get_tree().process_frame
		if document==null or document.get_instance_id()!=document_id or _column_revision!=revision:return false
	if not _query_point.is_empty() and _query_point.cell==cell and _query_point.revision==revision and _query_point.document==document_id:return true
	var job:=PointQueryJob.new(document,cell)
	var task:=WorkerThreadPool.add_task(job.run,false,"Ember placement height")
	_query_point_tasks[task]=job
	while _query_point_tasks.has(task) and not WorkerThreadPool.is_task_completed(task):await get_tree().process_frame
	if not _query_point_tasks.has(task):return false # Owner changed/closed and already joined it.
	WorkerThreadPool.wait_for_task_completion(task);_query_point_tasks.erase(task)
	if document==null or document.get_instance_id()!=document_id or _column_revision!=revision:return false
	_query_point={"cell":cell,"revision":revision,"document":document_id,"field":job.result}
	return true


func set_shared_material_pattern(pattern: TerrainPattern) -> bool:
	if pattern == null or not pattern.validation_errors().is_empty(): return false
	_refresh_material_atlas()
	if is_inside_tree():
		for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
			if get_parent().is_ancestor_of(prop):prop.refresh_solid_material()
		for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
			if get_parent().is_ancestor_of(patch): patch.refresh_shared_material()
	if get_parent() is EmberMapLoader: get_parent().anomaly_materials_changed.emit()
	return true

func preview_shared_material_light(pattern: TerrainPattern, id: String) -> void:
	if document==null or pattern==null:return
	if is_inside_tree():
		for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
			if get_parent().is_ancestor_of(prop):prop.preview_solid_material_light(pattern,id)
		for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
			if get_parent().is_ancestor_of(patch): patch.refresh_shared_material(pattern,id)
	for slot in document.palette_surface_roles.size():
		if document.material_id_for_palette(slot)!=id:continue
		Materials.update_grass_light_profile(_ground_material as ShaderMaterial,slot,pattern)
		Materials.update_style_rim_profile(_ground_material as ShaderMaterial,slot,pattern)
		Materials.set_terrain_depth_profiles(_ground_material as ShaderMaterial, document.palette_surface_roles, document.palette_material_ids, {id: pattern})
		for region: Dictionary in _water_regions.values():
			var material: ShaderMaterial=region.get("ground")
			if material!=null:
				Materials.update_grass_light_profile(material,slot,pattern)
				Materials.update_style_rim_profile(material,slot,pattern)
				Materials.set_terrain_depth_profiles(material, document.palette_surface_roles, document.palette_material_ids, {id: pattern})
	_refresh_far_ground_materials()
	if get_parent() is EmberMapLoader: get_parent().anomaly_materials_changed.emit()


func preview_shared_material_scale(pattern: TerrainPattern, id: String) -> void:
	if document == null or pattern == null:
		return
	var changed := false
	for slot in document.palette_surface_roles.size():
		if document.material_id_for_palette(slot) != id:
			continue
		Materials.update_terrain_pattern_scale(_ground_material as ShaderMaterial, slot, pattern)
		for region: Dictionary in _water_regions.values():
			Materials.update_terrain_pattern_scale(region.get("ground") as ShaderMaterial, slot, pattern)
		changed = true
	if changed:
		_refresh_far_ground_materials()


func _refresh_material_atlas() -> void:
	if document != null:
		Materials.set_compact_terrain_roles(_ground_material as ShaderMaterial, document.palette_surface_roles, document.palette_material_ids, document.palette)
		Materials.set_terrain_depth_profiles(_ground_material as ShaderMaterial, document.palette_surface_roles, document.palette_material_ids)
		(_ground_material as ShaderMaterial).set_shader_parameter("smooth_surface_enabled",ground_style == 1)
		for region: Dictionary in _water_regions.values():
			var ground: ShaderMaterial = region.get("ground")
			if ground != null:
				Materials.set_compact_terrain_roles(ground, document.palette_surface_roles, document.palette_material_ids, document.palette)
				Materials.set_terrain_depth_profiles(ground, document.palette_surface_roles, document.palette_material_ids)
				ground.set_shader_parameter("smooth_surface_enabled",ground_style == 1)
	_refresh_look_materials()


var _staged_dry_preview := {}
var _preview_tiles_to_publish := {}
const MAX_REUSABLE_PREVIEW_TILES := 64


func can_reuse_dry_preview(candidate: TerrainResource, keys: Array[Vector2i]) -> bool:
	if document == null or keys.is_empty() or keys.size() > MAX_REUSABLE_PREVIEW_TILES:
		return false
	if not document.is_sectioned() or not candidate.is_sectioned():
		return false
	if ground_style != 1 or world_look != 0 or _editor_residency_allowed():
		return false
	if candidate.palette != document.palette or candidate.palette_material_ids != document.palette_material_ids or candidate.palette_surface_roles != document.palette_surface_roles:
		return false
	var swash: Dictionary = _staged_water_fields.pending_dry_tiles() if _staged_water_fields != null else (_sea_swash.dry_tiles if _sea_swash != null else {})
	var fall: RefCounted = _staged_water_fields.waterfall if _staged_water_fields != null else _waterfall
	for key in keys:
		if swash.has(key) or (fall != null and fall.tiles.has(key)):
			return false
	return true


func stage_dry_preview(candidate: TerrainResource, tiles: Dictionary) -> void:
	# A one-shot handoff for the exact candidate; history keeps only Source.
	_staged_dry_preview = {"candidate":candidate, "tiles":tiles}


func clear_staged_dry_preview() -> void:
	_staged_dry_preview.clear()


func open_document(next_source: TerrainResource) -> bool:
	if next_source == null:
		return false
	if ground_style == 1 and next_source.width*next_source.depth > smooth_column_limit and not supports_editor_residency(next_source,smooth_column_limit): return false
	var stage_started := Time.get_ticks_usec()
	# Entering edit mode and opening the extension dialog can hand us a fresh
	# draft with identical terrain data. Keep the live tiles and pending edits.
	if document != null and document.same_terrain_geometry(next_source):
		if document.palette_surface_roles != next_source.palette_surface_roles or document.palette_material_ids != next_source.palette_material_ids:
			if not next_source.surface_role_errors().is_empty() or not next_source.material_id_errors().is_empty():
				return false
			document.palette_surface_roles = next_source.palette_surface_roles.duplicate()
			document.palette_material_ids = next_source.palette_material_ids.duplicate()
			_refresh_material_atlas()
		source = next_source
		return true
	var compare_us := Time.get_ticks_usec() - stage_started
	if document != null and document.is_sectioned() and next_source.is_sectioned() and not _editor_residency_allowed() and not supports_editor_residency(next_source,smooth_column_limit):
		return _open_changed_sections(next_source, Vector2i.ZERO)
	_profile_reset("open")
	_profile["compare_us"] = compare_us
	stage_started = Time.get_ticks_usec()
	if not next_source.validation_errors().is_empty():
		return false
	_profile["validation_us"] = Time.get_ticks_usec() - stage_started
	_startup_budget_allowed=Engine.is_editor_hint() and document==null
	_cancel_mesh_lods()
	for tile in _tiles.values():
		var old_tile := tile as Node3D
		_forget_water(old_tile)
		remove_child(old_tile)
		old_tile.queue_free()
	_tiles.clear()
	_clear_resident_tile_slots()
	_look_meshes.clear()
	_look_pending.clear()
	_editor_hidden_edge_keys.clear()
	_pending.clear()
	source = next_source
	stage_started = Time.get_ticks_usec()
	document = next_source.working_copy()
	_refresh_material_atlas()
	_profile["copy_us"] = Time.get_ticks_usec() - stage_started
	_reset_pending_flags()
	_column_revision += 1
	_reset_tile_revisions()
	_detail_full_tiles.clear();_detail_requested.clear()
	_navigation_grid.clear()
	_water_revision += 1
	_started_ms = Time.get_ticks_msec()
	_last_process_started_us = 0
	first_tile_ms = -1
	all_tiles_ms = -1
	_profile["focused_on_open"] = DisplayServer.window_is_focused()
	_profile["sleep_us_on_open"] = OS.low_processor_usage_mode_sleep_usec
	stage_started = Time.get_ticks_usec()
	_poll_detail_observer(0.0,true)
	if _editor_residency_allowed():
		_prepare_resident_tile_slots()
		for key:Vector2i in document.sections:_queue_overview(key)
		_sync_ground_residency()
	else:
		_opening_overview = _startup_budget_allowed and document.is_sectioned() and ground_style == 1 and world_look != 2
		if _opening_overview:
			for key: Vector2i in document.sections:
				_queue_overview(key)
		for key in document.tile_keys(TILE_SIZE): _queue_tile(key, false)
	_prioritize_pending()
	_profile["queue_us"] = Time.get_ticks_usec() - stage_started
	set_process(true)
	return true


func open_resized_document(next_source: TerrainResource, previous_source: TerrainResource, direction: String, section_cells: int) -> bool:
	if _editor_residency_allowed() or supports_editor_residency(next_source,smooth_column_limit):
		document=null
		return open_document(next_source)
	# A section changes only one edge of the existing Resource. Reuse every
	# interior tile, including its collision, and queue the strip and seam.
	# The extension owner validates the candidate when it is created. Avoid
	# scanning every column again on Apply/Undo; check its shape before reuse.
	if document == null or source != previous_source or not document.same_terrain_data(previous_source) or section_cells <= 0 or section_cells % TILE_SIZE != 0 or direction not in ["west", "east", "north", "south"] or next_source == null:
		return false
	if document.is_sectioned() and next_source.is_sectioned():
		var shift := Vector2i((next_source.width - document.width) / TILE_SIZE if direction == "west" else 0, (next_source.depth - document.depth) / TILE_SIZE if direction == "north" else 0)
		return _open_changed_sections(next_source, shift)
	var old_size := Vector2i(document.width, document.depth)
	var new_size := Vector2i(next_source.width, next_source.depth)
	var delta := new_size - old_size
	if (direction in ["west", "east"] and (absi(delta.x) != section_cells or delta.y != 0)) or (direction in ["north", "south"] and (absi(delta.y) != section_cells or delta.x != 0)):
		return false
	var count := next_source.width * next_source.depth
	if next_source.schema_version not in [TerrainResource.SCHEMA_VERSION, TerrainResource.SECTION_SCHEMA_VERSION] or next_source.unsupported_holes != 0 or next_source.origin_y != document.origin_y or next_source.height_limit != document.height_limit or next_source.palette != document.palette:
		return false
	for channel in [next_source.heights, next_source.top_materials, next_source.base_materials, next_source.cap_depths, next_source.water_levels, next_source.water_materials]:
		if not next_source.is_sectioned() and channel.size() != count:
			return false
	if not next_source.water_flow.is_empty() and next_source.water_flow.size() != ceili(float(next_source.width) / float(TerrainResource.CELLS_PER_BLOCK)) * ceili(float(next_source.depth) / float(TerrainResource.CELLS_PER_BLOCK)):
		return false
	var growing := delta.x > 0 or delta.y > 0
	_cancel_mesh_lods()
	var tile_delta := section_cells / TILE_SIZE * (1 if growing else -1)
	var offset := Vector2i(tile_delta if direction == "west" else 0, tile_delta if direction == "north" else 0)
	var new_tile_size := Vector2i(ceili(float(new_size.x) / TILE_SIZE), ceili(float(new_size.y) / TILE_SIZE))
	var kept := {}
	var shifted_pending: Array[Vector2i] = []
	if offset != Vector2i.ZERO:
		for tile in _tiles.values():
			(tile as Node3D).name = "MovingTile_%d" % (tile as Node3D).get_instance_id()
	for key in _tiles:
		var next_key: Vector2i = key + offset
		var tile := _tiles[key] as Node3D
		if next_key.x < 0 or next_key.y < 0 or next_key.x >= new_tile_size.x or next_key.y >= new_tile_size.y:
			_forget_water(tile)
			remove_child(tile)
			tile.queue_free()
			continue
		tile.position += Vector3(offset.x * TILE_SIZE, 0, offset.y * TILE_SIZE)
		tile.show()
		kept[next_key] = tile
	for key in kept:
		(kept[key] as Node3D).name = "TerrainTile_%d_%d" % [key.x, key.y]
	for key in _pending:
		var next_key: Vector2i = key + offset
		if next_key.x >= 0 and next_key.y >= 0 and next_key.x < new_tile_size.x and next_key.y < new_tile_size.y and next_key not in shifted_pending:
			shifted_pending.append(next_key)
	_tiles = kept
	_pending = shifted_pending
	_editor_hidden_edge_keys.clear()
	source = next_source
	_profile_reset("resize")
	var copy_started := Time.get_ticks_usec()
	document = next_source.working_copy()
	_refresh_material_atlas()
	_profile["copy_us"] = Time.get_ticks_usec() - copy_started
	_reset_pending_flags()
	_column_revision += 1
	_reset_tile_revisions()
	_resize_look_cache(offset)
	_navigation_grid.clear()
	_water_revision += 1
	_started_ms = Time.get_ticks_msec()
	_last_process_started_us = 0
	first_tile_ms = -1
	all_tiles_ms = -1
	_profile["focused_on_open"] = DisplayServer.window_is_focused()
	_profile["sleep_us_on_open"] = OS.low_processor_usage_mode_sleep_usec
	var queue_started := Time.get_ticks_usec()
	for z in new_tile_size.y:
		for x in new_tile_size.x:
			var key := Vector2i(x, z)
			var on_seam := (direction == "west" and x == (section_cells / TILE_SIZE if growing else 0)) or (direction == "east" and x == (old_size.x / TILE_SIZE - 1 if growing else new_tile_size.x - 1)) or (direction == "north" and z == (section_cells / TILE_SIZE if growing else 0)) or (direction == "south" and z == (old_size.y / TILE_SIZE - 1 if growing else new_tile_size.y - 1))
			if not _tiles.has(key) or on_seam:
				_queue_tile(key, false)
	_prioritize_pending()
	_profile["queue_us"] = Time.get_ticks_usec() - queue_started
	set_process(not _pending.is_empty())
	return true


func _open_changed_sections(next_source: TerrainResource, shift: Vector2i) -> bool:
	if not next_source.validation_errors().is_empty(): return false
	var prepared: Dictionary = _staged_dry_preview.tiles if shift == Vector2i.ZERO and next_source == _staged_dry_preview.get("candidate") else {}
	clear_staged_dry_preview()
	var retained_fields:=_smooth_fields.duplicate()
	var retained_layouts:=_editor_surface_layouts.duplicate()
	_cancel_mesh_lods()
	var previous := document
	var changed := {}
	var colors_changed := previous.palette != next_source.palette
	var part_shift := shift / (TerrainResource.Sections.CELLS / TILE_SIZE)
	for key: Vector2i in previous.sections:
		var moved := key + part_shift
		if not next_source.sections.has(moved): changed[moved] = true
	for key: Vector2i in next_source.sections:
		var old := previous.sections.get(key - part_shift) as TerrainResource
		if colors_changed or old == null or (old != next_source.sections[key] and not old.same_terrain_geometry(next_source.sections[key], true)): changed[key] = true
	# Same-size session restore (Discard/save refresh) keeps the 24m storage
	# snapshots, but must invalidate only the small display tiles that differ.
	var local_restore:=shift==Vector2i.ZERO and previous.width==next_source.width and previous.depth==next_source.depth and previous.origin_y==next_source.origin_y and not colors_changed and previous.surface_rules==next_source.surface_rules
	var changed_tiles: Dictionary={}
	if local_restore and not prepared.is_empty():
		for key: Vector2i in prepared:
			changed_tiles[key] = true
	elif local_restore:
		for section: Vector2i in changed:
			var start:=section*(TerrainResource.Sections.CELLS/TILE_SIZE)
			var span:=TerrainResource.Sections.CELLS/TILE_SIZE
			for z in range(start.y,start.y+span):
				for x in range(start.x,start.x+span):
					var bounds:=Rect2i(Vector2i(x,z)*TILE_SIZE,Vector2i.ONE*TILE_SIZE).intersection(Rect2i(0,0,next_source.width,next_source.depth))
					if not bounds.has_area():continue
					if previous.dense_window(bounds).same_terrain_geometry(next_source.dense_window(bounds),true):continue
					for nz in range(z-1,z+2):
						for nx in range(x-1,x+2):changed_tiles[Vector2i(nx,nz)]=true
	var valid := {}
	for key in next_source.tile_keys(TILE_SIZE): valid[key] = true
	var kept := {}
	for key: Vector2i in _tiles:
		var moved := key + shift
		var tile := _tiles[key] as Node3D
		if not valid.has(moved):
			_forget_water(tile)
			remove_child(tile)
			tile.queue_free()
		else:
			tile.position += Vector3(shift.x * TILE_SIZE, 0, shift.y * TILE_SIZE)
			tile.show()
			kept[moved] = tile
	_tiles = kept
	var pending: Array[Vector2i] = []
	for key in _pending:
		if valid.has(key + shift): pending.append(key + shift)
	_pending = pending
	_editor_hidden_edge_keys.clear()
	source = next_source
	document = next_source.working_copy()
	_profile_reset("sections")
	if colors_changed or previous.palette_surface_roles != document.palette_surface_roles or previous.palette_material_ids != document.palette_material_ids:
		_refresh_material_atlas()
	_reset_pending_flags()
	if local_restore:
		# Discard/Undo retains unchanged meshes. Retain their matching pick/layout
		# data too; only the invalidated footprint gets a new derived surface.
		for key:Vector2i in retained_fields:
			if _tiles.has(key) and not changed_tiles.has(key):_smooth_fields[key]=retained_fields[key]
		for key:Vector2i in retained_layouts:
			if _tiles.has(key) and not changed_tiles.has(key):_editor_surface_layouts[key]=retained_layouts[key]
	_column_revision += 1
	var previous_surface_revisions:=_surface_tile_revisions.duplicate()
	_reset_tile_revisions()
	if local_restore and previous_surface_revisions.size()==_surface_tile_revisions.size():
		_surface_tile_revisions=previous_surface_revisions
		for key:Vector2i in changed_tiles:
			if valid.has(key):_surface_tile_revisions[key.x+key.y*_pending_tile_columns]=_column_revision
	_resize_look_cache(shift)
	_navigation_grid.clear()
	_water_revision += 1
	if local_restore:
		for key: Vector2i in changed_tiles:_queue_tile(key,false)
	else:
		for key: Vector2i in changed:
			var start := key * (TerrainResource.Sections.CELLS / TILE_SIZE)
			var span := TerrainResource.Sections.CELLS / TILE_SIZE
			for z in range(start.y - 1, start.y + span + 1):
				for x in range(start.x - 1, start.x + span + 1): _queue_tile(Vector2i(x, z), false)
	if previous.surface_rules!=next_source.surface_rules:
		var rule_keys:=previous.surface_rules.keys()
		for key in next_source.surface_rules:
			if key not in rule_keys:rule_keys.append(key)
		for key: Vector2i in rule_keys:
			for dz in [-1,0,1]:
				for dx in [-1,0,1]:_queue_tile(key+Vector2i(dx,dz),false)
	if local_restore:
		_preview_tiles_to_publish = prepared
	_prioritize_pending()
	set_process(not _pending.is_empty())
	return true


var _startup_budget_allowed:=false
var _editor_fingerprint_memo: GeometryCache.EditorFingerprintMemo

func _publication_budget_us()->int:
	# Initial opening may spend more of a frame attaching ready resources.
	# The first brush gesture permanently restores the interactive limit.
	if _editor_residency_allowed() and not _live_brush_active:
		var scatter_waiting:bool=DetailPreparation.for_projection(self).has_pending_work()
		return 4000 if scatter_waiting and detail_policy.enabled and _detail_foreground_ready() else 8000
	return 12000 if _startup_budget_allowed and not _live_brush_active else 4000

func _process(_delta: float) -> void:
	# Observer/residency changes are foreground preparation too. Charge them
	# before admitting publication work, not on top of a fresh full allowance.
	var started := Time.get_ticks_usec()
	DetailPreparation.for_projection(self).begin_ground()
	_poll_detail_observer(_delta)
	_update_ground_material_distance()
	var budget_us:=_publication_budget_us()
	# Large-world ground and vegetation spend one shared frame allowance.
	# This gives travelling ground more progress without stacking 4 + 8 ms.
	if _editor_residency_allowed():budget_us=mini(budget_us,DetailPreparation.for_projection(self).remaining_us())
	DetailPreparation.for_projection(self).poll_sleeping()
	if _last_process_started_us > 0:
		var gap_us := started - _last_process_started_us
		_profile_add("between_process_us", gap_us)
		_profile["max_between_process_us"] = maxi(int(_profile.get("max_between_process_us", 0)), gap_us)
	_last_process_started_us = started
	_profile_add("focused_process_calls" if DisplayServer.window_is_focused() else "unfocused_process_calls", 1)
	_profile["max_sleep_us"] = maxi(int(_profile.get("max_sleep_us", 0)), OS.low_processor_usage_mode_sleep_usec)
	if _pending_needs_sort:
		_prioritize_pending()
	_poll_editor_surface_jobs(started,budget_us)
	_poll_overviews(started,budget_us)
	if not Engine.is_editor_hint(): _poll_mesh_lods(started)
	var remaining := _pending.size()
	while remaining > 0 and not _pending.is_empty() and (Time.get_ticks_usec() - started < budget_us or Time.get_ticks_usec() == started):
		var pending_index := 0
		if _uses_geometry_preparation():
			if _geometry_prepared.is_empty(): break
			pending_index = _pending.find(_geometry_prepared.keys()[0])
		var key: Vector2i = _pending.pop_at(pending_index)
		var prepared: Dictionary = _geometry_prepared.get(key, {})
		_geometry_prepared.erase(key)
		remaining -= 1
		var index := key.x + key.y * _pending_tile_columns
		if _preview_tiles_to_publish.has(key):
			var generated: Dictionary = _preview_tiles_to_publish[key]
			_preview_tiles_to_publish.erase(key)
			_pending_flags[index] = 0
			_pending_edit_flags[index] = 0
			_detail_full_tiles[key] = true
			_detail_requested[key] = true
			_rebuild_tile(key, {}, {}, generated)
			_profile_add("editor_preview_reused_tiles", 1)
			continue
		if _editor_surface_jobs.has(key):
			_pending.append(key)
			continue
		if Engine.is_editor_hint() and ground_style==1 and not document.is_sectioned() and _editor_surface_layouts.has(key) and _detail_full_tiles.get(key,true) and _detail_full_requested(key):
			if _editor_surface_jobs.size()>=clampi(OS.get_processor_count()-4,1,2):
				_pending.append(key)
				continue
			var start:=key*TILE_SIZE
			var bounds:=Rect2i(start,Vector2i(mini(TILE_SIZE,document.width-start.x),mini(TILE_SIZE,document.depth-start.y)))
			var layout: Dictionary=_editor_surface_layouts[key]
			if not layout.get("side_paint",false) and SmoothSurface.layout_key(document,bounds,smooth_material_blend_enabled)==layout.key:
				_pending.append(key)
				if _editor_surface_jobs.size()<clampi(OS.get_processor_count()-4,1,2):
					var cancellation:=MeshLOD.Cancellation.new()
					var job:=SmoothSurface.height_update_job(document.working_copy(),bounds,layout)
					var task:=WorkerThreadPool.add_task(job.run.bind(cancellation.is_cancelled),false,"Ember terrain shape")
					_editor_surface_jobs[key]={"job":job,"task":task,"request":_geometry_requests.get(key,0),"cancellation":cancellation,"epoch":_editor_brush_epoch,"live":_live_brush_active,"bounds":bounds}
					_profile_add("editor_shape_jobs",1)
				continue
		if ground_style==1 and not _geometry_prepare_disabled:
			_pending.append(key)
			# Preparation is CPU-only and shares one immutable source snapshot.
			# Reserve four logical CPUs for rendering, input, audio and the OS.
			if _editor_surface_jobs.size()+_overview_jobs.size()<clampi(OS.get_processor_count()-4,1,4):
				if _geometry_snapshot_revision!=_column_revision:
					_geometry_snapshot=document.working_copy();_geometry_snapshot_revision=_column_revision
					_editor_fingerprint_memo = GeometryCache.EditorFingerprintMemo.new()
				var cache:=GeometryCache.new()
				cache.directory=runtime_geometry_cache_directory if runtime_geometry_cache_enabled else ""
				var swash_tiles:Dictionary=_staged_water_fields.pending_dry_tiles() if _staged_water_fields!=null else (_sea_swash.dry_tiles if _sea_swash!=null else {})
				var fall:RefCounted=_staged_water_fields.waterfall if _staged_water_fields!=null else _waterfall
				var water_options:Dictionary={"step":water_mesh_step,"sides":water_volume_sides,"swash":(swash_tiles.get(key,PackedVector4Array()) as PackedVector4Array).duplicate(),"sheet":(fall.tiles.get(key,{}) as Dictionary).duplicate(true) if fall!=null else {}}
				water_options.far_stride=1 if _detail_full_requested(key) else 32
				water_options.residency_edges=_editor_residency_allowed()
				_detail_requested[key]=water_options.far_stride==1
				var prepare_job:=cache.editor_job(_geometry_snapshot,key,smooth_material_blend_enabled,water_options,_editor_fingerprint_memo)
				var cancellation:=MeshLOD.Cancellation.new()
				var task:=WorkerThreadPool.add_task(prepare_job.run.bind(cancellation.is_cancelled),false,"Ember terrain preparation")
				if task>=0:
					_editor_surface_jobs[key]={"job":prepare_job,"task":task,"request":_geometry_requests.get(key,0),"cancellation":cancellation,"epoch":_editor_brush_epoch,"live":_live_brush_active,"bounds":Rect2i(key*TILE_SIZE,Vector2i(mini(TILE_SIZE,document.width-key.x*TILE_SIZE),mini(TILE_SIZE,document.depth-key.y*TILE_SIZE))),"prepare":true,"water_revision":_water_revision,"detail_full":water_options.far_stride==1}
					_profile_add("editor_prepare_jobs",1)
				else:
					_geometry_prepare_disabled=true;_profile_add("geometry_prepare_worker_failures",1)
			continue
		var now := Time.get_ticks_usec()
		if _live_brush_active and _pending_edit_flags[index] != 0 and _last_edit_build_us[index] > 0 and now - _last_edit_build_us[index] < _repeat_edit_build_interval_us:
			_pending.append(key)
			_profile_add("deferred_repeat_builds", 1)
			continue
		_pending_flags[index] = 0
		var edited := _pending_edit_flags[index] != 0
		_pending_edit_flags[index] = 0
		_profile["max_pending_age_us"] = maxi(int(_profile.get("max_pending_age_us", 0)), now - _pending_since_us[index])
		_rebuild_tile(key, prepared)
		if edited:
			if _last_edit_build_us[index] > 0: _profile_add("repeat_edit_builds", 1)
			_last_edit_build_us[index] = Time.get_ticks_usec()
		if first_tile_ms < 0:
			first_tile_ms = Time.get_ticks_msec() - _started_ms
	if not Engine.is_editor_hint(): _poll_mesh_lods(started)
	while not _look_pending.is_empty() and Time.get_ticks_usec() - started < budget_us:
		_apply_tile_look(_look_pending.pop_back())
	if _opening_overview and _pending.is_empty():
		_opening_overview = false
		_clear_overviews()
	if _pending.is_empty() and _overview_pending.is_empty() and _overview_jobs.is_empty() and _overview_dirty.is_empty():
		if _editor_surface_jobs.is_empty():
			_geometry_snapshot=null;_geometry_snapshot_revision=-1
			_editor_fingerprint_memo = null
		if all_tiles_ms < 0:
			all_tiles_ms = Time.get_ticks_msec() - _started_ms
			_startup_budget_allowed=false
			all_tiles_ready.emit()
		set_process(Engine.is_editor_hint() or ground_style==1 or pending_runtime_lod_count() > 0 or not _look_pending.is_empty())
	var elapsed := Time.get_ticks_usec() - started
	DetailPreparation.for_projection(self).finish_ground(started)
	_profile_add("process_us", elapsed)
	_profile_add("process_calls", 1)
	_profile["max_process_us"] = maxi(int(_profile.get("max_process_us", 0)), elapsed)
	var phase:="startup" if _startup_budget_allowed and budget_us>4000 else "interactive"
	_profile_add(phase+"_process_calls",1)
	_profile["max_"+phase+"_process_us"]=maxi(int(_profile.get("max_"+phase+"_process_us",0)),elapsed)


func _poll_editor_surface_jobs(frame_started: int,budget_us:=4000) -> void:
	for key: Vector2i in _editor_surface_jobs.keys():
		if Time.get_ticks_usec()-frame_started>=budget_us:return
		var record: Dictionary=_editor_surface_jobs[key]
		if record.task>=0:
			if not WorkerThreadPool.is_task_completed(record.task):continue
			WorkerThreadPool.wait_for_task_completion(record.task)
			record.task=-1
		var newer_request: bool=record.request!=_geometry_requests.get(key,0)
		# One completed sculpt step must reach the viewport even if more input
		# arrived meanwhile. Only the same stroke and unchanged paint/topology
		# can publish progressively; Undo/cancel/open retain strict invalidation.
		var progressive: bool=_live_brush_active and record.live and record.epoch==_editor_brush_epoch and record.get("water_revision",_water_revision)==_water_revision
		if (newer_request and not progressive) or record.job.result.is_empty():
			_editor_surface_jobs.erase(key)
			_profile_add("editor_shape_stale",1)
			continue
		var smooth: Dictionary=record.job.result
		if record.get("prepare",false) and not record.has("publication"):
			_profile_add("editor_surface_cache_hits" if record.job.cache_hit else "editor_surface_cache_misses",1)
			_profile_add("editor_prepare_us",record.job.elapsed_us)
			_profile_add("editor_surface_cache_invalid",record.job.invalid)
		var generated:Dictionary={}
		if record.get("prepare",false) and not record.job.tile_data.is_empty():
			if not record.has("publication"):
				record.publication=MeshBuilder.EditorTilePublication.new(record.job.tile_data)
				_profile_add("editor_water_prepare_us",int(record.job.tile_data.water_prepare_us))
			var publication:RefCounted=record.publication
			if not publication.ready:
				while not publication.ready and Time.get_ticks_usec()-frame_started<budget_us:
					var began:=Time.get_ticks_usec()
					publication.advance()
					var duration:=Time.get_ticks_usec()-began
					_profile_add("editor_publication_steps",1)
					_profile_add("editor_"+publication.last_phase+"_us",duration)
					_profile["max_editor_publication_step_us"]=maxi(int(_profile.get("max_editor_publication_step_us",0)),duration)
				continue # Commit is its own step on a later frame.
			generated=publication.result
		else:
			smooth=SmoothSurface.publish_arrays(smooth)
		if progressive and newer_request:
			var input:Dictionary=MeshBuilder.editor_surface_input(document,key.x*TILE_SIZE,key.y*TILE_SIZE,TILE_SIZE) if record.get("prepare",false) else {"source":document,"bounds":record.bounds}
			progressive=SmoothSurface.layout_key(input.source,input.bounds,smooth_material_blend_enabled)==record.job.result.get("layout",{}).get("key",PackedByteArray())
		if newer_request and not progressive:
			_editor_surface_jobs.erase(key);_profile_add("editor_shape_stale",1);continue
		_editor_surface_jobs.erase(key)
		var index:=key.x+key.y*_pending_tile_columns
		# Keep newer dirty input queued. Publishing this step never acknowledges
		# changes that were not in its immutable source snapshot.
		if not newer_request:
			_pending.erase(key);_pending_flags[index]=0;_pending_edit_flags[index]=0
		_detail_full_tiles[key]=record.get("detail_full",true)
		_detail_requested[key]=_detail_full_tiles[key]
		_rebuild_tile(key,{},smooth,generated)
		if not _detail_full_tiles[key]:_editor_surface_layouts.erase(key)
		if first_tile_ms<0:first_tile_ms=Time.get_ticks_msec()-_started_ms
		_profile_add("editor_shape_published",1)


func _rebuild_tile(key: Vector2i, prepared: Dictionary = {}, prepared_smooth: Dictionary = {}, generated:Dictionary={}) -> void:
	var tile_started := Time.get_ticks_usec()
	var started := tile_started
	var swash_tiles: Dictionary = _staged_water_fields.pending_dry_tiles() if _staged_water_fields != null else (_sea_swash.dry_tiles if _sea_swash != null else {})
	var fall: RefCounted = _staged_water_fields.waterfall if _staged_water_fields != null else _waterfall
	var swash: PackedVector4Array = swash_tiles.get(key, PackedVector4Array())
	var sheet: Dictionary = fall.tiles.get(key, {}) if fall != null else {}
	var cache_key := ""
	if generated.is_empty():
		if not prepared.is_empty():
			cache_key = prepared.cache_key
			_geometry_keys[key] = cache_key
			if not prepared.data.is_empty(): generated = GeometryCache.publish_geometry(prepared.data)
			_profile_add("geometry_cache_upload_us", int(generated.get("cache_upload_us", 0)))
			_profile_add("geometry_cache_hits" if not generated.is_empty() else "geometry_cache_misses", 1)
		elif not Engine.is_editor_hint() and runtime_geometry_cache_enabled and not runtime_geometry_cache_directory.is_empty():
			if _geometry_cache == null: _geometry_cache = GeometryCache.new()
			_geometry_cache.directory = runtime_geometry_cache_directory
			cache_key = _geometry_cache.tile_key(document, key, _column_revision,
				_geometry_policy(), swash, sheet)
			_geometry_keys[key] = cache_key
			_profile_add("geometry_cache_key_us", Time.get_ticks_usec() - started)
			var read_started := Time.get_ticks_usec()
			var invalid_before: int = _geometry_cache.disk.invalid
			var failures_before: int = _geometry_cache.disk.failures
			generated = _geometry_cache.read_geometry(cache_key)
			for phase in ["decode", "validate", "upload"]:
				_profile_add("geometry_cache_" + phase + "_us", int(generated.get("cache_" + phase + "_us", 0)))
			_profile_add("geometry_cache_read_us", Time.get_ticks_usec() - read_started)
			_profile_add("geometry_cache_invalid", _geometry_cache.disk.invalid - invalid_before)
			_profile_add("geometry_cache_failures", _geometry_cache.disk.failures - failures_before)
			_profile_add("geometry_cache_hits" if not generated.is_empty() else "geometry_cache_misses", 1)
		if generated.is_empty():
			generated = MeshBuilder.build_tile(document, key.x * TILE_SIZE, key.y * TILE_SIZE,
				TILE_SIZE, water_mesh_step, water_volume_sides, swash, sheet, not Engine.is_editor_hint(),
				not Engine.is_editor_hint() and runtime_water_mesh_optimization, ground_style == 1, smooth_material_blend_enabled,prepared_smooth)
			if not cache_key.is_empty():
				var write_started := Time.get_ticks_usec()
				var bytes_before: int = _geometry_cache.disk.written_bytes
				var failures_before: int = _geometry_cache.disk.failures
				generated.merge(_geometry_cache.write_geometry(cache_key, generated))
				_profile_add("geometry_cache_write_us", Time.get_ticks_usec() - write_started)
				_profile_add("geometry_cache_written_bytes", _geometry_cache.disk.written_bytes - bytes_before)
				_profile_add("geometry_cache_failures", _geometry_cache.disk.failures - failures_before)
				_mesh_lod_jobs["cache_maintenance"] = {"kind": "cache_maintenance", "directory": runtime_geometry_cache_directory}
	if generated.has("smooth_field"): _smooth_fields[key] = generated.smooth_field
	if generated.has("smooth_layout"):_editor_surface_layouts[key]=generated.smooth_layout
	_profile_add("mesh_us", Time.get_ticks_usec() - started)
	_profile_add("geometry_us", int(generated.get("geometry_us", 0)))
	_profile_add("top_us", int(generated.get("top_us", 0)))
	_profile_add("side_us", int(generated.get("side_us", 0)))
	_profile_add("water_us", int(generated.get("water_us", 0)))
	_profile_add("uniform_us", int(generated.get("uniform_us", 0)))
	_profile_add("mesh_resource_us", int(generated.get("mesh_resource_us", 0)))
	_profile_add("ground_vertices", (generated["collision_faces"] as PackedVector3Array).size())
	_profile_add("water_vertices", int(generated.get("water_vertices", 0)))
	_profile_add("water_source_vertices", int(generated.get("water_source_vertices", generated.get("water_vertices", 0))))
	_profile_add("water_indices", int(generated.get("water_indices", 0)))
	if bool(generated.get("uniform_dry", false)):
		_profile_add("uniform_dry_tiles", 1)
	if bool(generated.get("grouped_8", false)):
		_profile_add("grouped_8_tiles", 1)
	started = Time.get_ticks_usec()
	var tile := _tiles.get(key) as Node3D
	if tile == null:
		tile = _take_tile_host(key)
		_tiles[key] = tile
	_profile_add("node_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	tile.position = Vector3.ZERO
	var ground_mesh := _queue_ground_lod(key, generated["terrain"] as ArrayMesh, generated.get("ground_arrays", []))
	if ground_mesh.get_surface_count() > 0:
		ground_mesh.surface_set_material(0, _ground_material)
	(tile.get_node("Ground") as MeshInstance3D).mesh = ground_mesh
	_look_meshes[key] = {0: ground_mesh}
	_apply_tile_look(key)
	(tile.get_node("Ground") as MeshInstance3D).material_overlay = _editor_hover_overlay if _editor_hover_tiles.has(key) else null
	_apply_ground_lod_bias(key)
	var water_mesh := _queue_water_lod(key, generated["water"] as ArrayMesh, generated.get("water_arrays", []))
	if water_mesh.get_surface_count() > 0:
		water_mesh.surface_set_material(0, _water_material)
	(tile.get_node("Water") as MeshInstance3D).mesh = water_mesh
	_track_water(tile.get_node("Water") as MeshInstance3D)
	(tile.get_node("Water") as MeshInstance3D).visible = not _water_hidden
	_apply_region_materials(key, tile)
	_profile_add("visual_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	var faces := generated["collision_faces"] as PackedVector3Array
	var collision:=generated.get("collision") as Shape3D
	# Godot's height-map shape requires conformal (uniform-scale) placement.
	# Serialized affine maps retain their established exact triangle collision.
	if collision is HeightMapShape3D and not global_basis.is_conformal():
		collision=null
		generated.erase("collision_position")
	if collision==null:
		collision=ConcavePolygonShape3D.new()
		collision.set_faces(faces)
	_profile_add("collision_shape_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	var shape_node:=tile.get_node("GroundPhysics/Shape") as CollisionShape3D
	shape_node.position=generated.get("collision_position",Vector3.ZERO)
	shape_node.shape=collision
	if _editor_residency_allowed():
		var edge:=tile.get_node_or_null("ResidencyEdge") as MeshInstance3D
		if edge==null:
			edge=MeshInstance3D.new();edge.name="ResidencyEdge";tile.add_child(edge)
			edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var begin:=key*TILE_SIZE
		var edge_arrays:Array=generated.get("residency_edge_upload",{}).get("arrays",generated.get("residency_edge_arrays",[]))
		edge.mesh=MeshBuilder.publish_residency_edge(edge_arrays) if not edge_arrays.is_empty() else MeshBuilder.residency_edge(document,Rect2i(begin,Vector2i(mini(TILE_SIZE,document.width-begin.x),mini(TILE_SIZE,document.depth-begin.y))),_smooth_fields.get(key,{}))
		generated.erase("residency_edge_upload")
		edge.material_override=_far_material(_region_ground_material(_overview_section(key)))
		_overview_dirty[_overview_section(key)]=true
	elif _opening_overview and _overviews.has(_overview_section(key)):
		_overview_dirty[_overview_section(key)] = true
	tile.visible = not _editor_hidden_edge_keys.has(key)
	_profile_add("collision_attach_us", Time.get_ticks_usec() - started)
	_profile_add("tile_builds", 1)
	_profile["max_tile_us"] = maxi(int(_profile.get("max_tile_us", 0)), Time.get_ticks_usec() - tile_started)


func apply_study_smooth_tile(key: Vector2i, field: Dictionary, faces: PackedVector3Array) -> bool:
	# Opt-in presentation study only. Source/cache entries stay canonical;
	# floor/pick/navigation and collision advance to the same derived phase.
	if ground_style!=1 or not _tiles.has(key) or field.is_empty():return false
	var shape:=(_tiles[key] as Node3D).get_node("GroundPhysics/Shape") as CollisionShape3D
	if not shape.shape is ConcavePolygonShape3D:shape.shape=ConcavePolygonShape3D.new()
	shape.position=Vector3.ZERO
	(shape.shape as ConcavePolygonShape3D).set_faces(faces)
	_smooth_fields[key]=field
	_navigation_grid.clear()
	return true

func apply_surface_rules(rules: Dictionary,cells: Array) -> void:
	if document==null:return
	_ensure_surface_tile_revisions()
	document.surface_rules=rules.duplicate()
	if ground_style!=1:return # Saved for smooth view; voxel shape stays exact.
	var dirty:=PackedByteArray();dirty.resize(_pending_flags.size())
	var grid:=PackedByteArray();grid.resize(dirty.size())
	_column_revision+=1
	for cell: Vector2i in cells:
		_mark_smooth_neighbours(cell,dirty,grid,true,_pending_tile_columns,_pending_tile_rows)
	for index in dirty.size():
		if dirty[index]==0:continue
		var key:=Vector2i(index%_pending_tile_columns,index/_pending_tile_columns)
		_smooth_fields.erase(key);_tile_revisions[index]=_column_revision;_surface_tile_revisions[index]=_column_revision;_queue_tile(key,true)
	_navigation_grid.clear();set_process(true)

func _profile_reset(operation: String) -> void:
	if operation!="open":_startup_budget_allowed=false
	_profile = {"operation": operation, "compare_us": 0, "validation_us": 0, "copy_us": 0, "queue_us": 0,
		"mesh_us": 0, "geometry_us": 0, "top_us": 0, "side_us": 0, "water_us": 0, "uniform_us": 0,
		"mesh_resource_us": 0, "node_us": 0, "visual_us": 0,
		"collision_shape_us": 0, "collision_attach_us": 0, "process_us": 0,
		"process_calls": 0, "max_process_us": 0, "tile_builds": 0, "max_tile_us": 0,
		"coalesced_tile_requests": 0, "deferred_repeat_builds": 0, "repeat_edit_builds": 0, "max_pending_age_us": 0,
		"between_process_us": 0, "max_between_process_us": 0,
		"focused_process_calls": 0, "unfocused_process_calls": 0, "max_sleep_us": 0,
		"ground_vertices": 0, "water_vertices": 0, "water_source_vertices": 0, "water_indices": 0,
		"uniform_dry_tiles": 0, "grouped_8_tiles": 0, "new_tile_nodes": 0,
		"ground_lod_jobs": 0, "ground_lod_tiles": 0, "ground_lod_levels": 0,
		"ground_lod_cpu_us": 0, "ground_lod_max_job_us": 0, "ground_lod_publish_us": 0,
		"ground_lod_max_publish_us": 0, "ground_lod_saved_indices": 0, "ground_lod_extra_index_bytes": 0,
		"ground_lod_stale_results": 0, "mesh_lod_worker_failures": 0, "runtime_mesh_ready_ms": -1,
		"water_lod_jobs": 0, "water_lod_tiles": 0, "water_lod_levels": 0,
		"water_lod_cpu_us": 0, "water_lod_max_job_us": 0, "water_lod_publish_us": 0,
		"water_lod_max_publish_us": 0, "water_lod_saved_indices": 0, "water_lod_extra_index_bytes": 0,
		"water_lod_stale_results": 0}
	for key in ["geometry_cache_hits", "geometry_cache_misses", "geometry_cache_invalid", "geometry_cache_failures",
		"geometry_prepare_jobs", "geometry_prepare_batches", "geometry_prepare_stale", "geometry_prepare_worker_failures", "geometry_prepare_max_tiles", "geometry_prepare_max_bytes",
		"geometry_cache_decode_us", "geometry_cache_validate_us", "geometry_cache_upload_us", "runtime_lod_array_readbacks", "runtime_lod_array_readback_us",
		"geometry_cache_key_us", "geometry_cache_read_us", "geometry_cache_write_us", "geometry_cache_lod_us",
		"geometry_cache_written_bytes", "geometry_cache_trim_us", "ground_lod_cache_hits", "ground_lod_cache_misses", "water_lod_cache_hits", "water_lod_cache_misses"]:
		_profile[key] = 0


func _profile_add(key: String, value: int) -> void:
	_profile[key] = int(_profile.get(key, 0)) + value


func begin_live_brush() -> void:
	_startup_budget_allowed=false
	_editor_brush_epoch += 1
	_live_brush_active = true
	var map := get_parent()
	var anomaly := map.get_node_or_null("WorldAnomaly") if map != null else null
	if anomaly != null: anomaly.stop_preview()
	_last_edit_build_us.fill(0)


func end_live_brush() -> void:
	_live_brush_active = false


func set_live_brush_center(cell: Vector2i) -> void:
	if not _live_brush_active or cell==_editor_brush_center:return
	_editor_brush_center=cell
	_pending_needs_sort=true


func profile_snapshot() -> Dictionary:
	var result := _profile.duplicate()
	result["scope"] = "accumulated_since_last_open_or_resize"
	result["built_tiles"] = built_tile_count()
	result["pending_tiles"] = pending_tile_count()
	result["pending_runtime_lods"] = pending_runtime_lod_count()
	result["first_tile_ms"] = first_tile_ms
	result["all_tiles_ms"] = all_tiles_ms
	result["width"] = document.width if document != null else 0
	result["depth"] = document.depth if document != null else 0
	result["resident_mode"]=_editor_residency_allowed()
	result["resident_wanted"]=_resident_tiles.size()
	result["overview_sections"]=_overviews.size()
	result["overview_pending"]=_overview_pending.size()+_overview_jobs.size()
	result["readiness_scope"]="active_tiles_and_overview" if _editor_residency_allowed() else "whole_map"
	return result


func set_editor_extension_edge_hidden(direction: String, hidden: bool) -> void:
	_editor_hidden_edge_keys.clear()
	if hidden and document != null:
		var last_x := ceili(float(document.width) / TILE_SIZE) - 1
		var last_z := ceili(float(document.depth) / TILE_SIZE) - 1
		if direction in ["west", "east"]:
			for z in last_z + 1:
				_editor_hidden_edge_keys[Vector2i(0 if direction == "west" else last_x, z)] = true
		elif direction in ["north", "south"]:
			for x in last_x + 1:
				_editor_hidden_edge_keys[Vector2i(x, 0 if direction == "north" else last_z)] = true
	for key in _tiles:
		(_tiles[key] as Node3D).visible = not _editor_hidden_edge_keys.has(key)


func _apply_ground_lod_bias(key:Vector2i)->void:
	if ground_style!=1 or not _tiles.has(key):return
	var ground:=_tiles[key].get_node("Ground") as MeshInstance3D
	ground.lod_bias=EDIT_GROUND_LOD_BIAS if _editor_hover_tiles.has(key) or not detail_policy.ground_lod_enabled else RUNTIME_GROUND_LOD_BIAS


func set_editor_hover_overlay(overlay: Material, tile_keys: Array[Vector2i]) -> int:
	# Editor-only presentation. The terrain Resource, mesh, and collision remain
	# unchanged; rebuilt tiles inherit the overlay while they are in range.
	var requested := {}
	if overlay != null:
		for key in tile_keys:
			requested[key] = true
	var changes := 0
	for key in _editor_hover_tiles:
		if requested.has(key): continue
		var tile := _tiles.get(key) as Node3D
		if tile != null:
			(tile.get_node("Ground") as MeshInstance3D).material_overlay = null
			changes += 1
	for key in requested:
		if _editor_hover_tiles.has(key) and overlay == _editor_hover_overlay: continue
		var tile := _tiles.get(key) as Node3D
		if tile != null:
			(tile.get_node("Ground") as MeshInstance3D).material_overlay = overlay
			changes += 1
	var affected:=_editor_hover_tiles.duplicate()
	affected.merge(requested)
	_editor_hover_overlay = overlay
	_editor_hover_tiles = requested
	for key:Vector2i in affected:_apply_ground_lod_bias(key)
	_sync_ground_residency()
	return changes


func pending_physics_chunk_count() -> int:
	return _pending.size()


func column_revision() -> int:
	return _column_revision


func set_editor_water_hidden(hidden: bool) -> void:
	_water_hidden = hidden
	for tile in _tiles.values():
		(tile.get_node("Water") as MeshInstance3D).visible = not hidden


func floor_footprint_clear(center:Vector3,radius:float,unit:float)->bool:
	# The same eight physical probes as grass previously made through
	# floor_surface_sample, without constructing unused picking/gameplay metadata.
	if document==null:return false
	var world:=global_transform
	var inverse:=world.affine_inverse()
	var last_cell:=Vector2i(-1,-1)
	var height:=0
	var field_key:=Vector2i(-1,-1)
	var field:Dictionary={}
	for i in 8:
		var offset:=Vector2.from_angle(i*TAU/8.0)*radius
		var local:=inverse*(center+Vector3(offset.x,0,offset.y))
		var cell:=Vector2i(floori(local.x),floori(local.z))
		if cell.x<0 or cell.y<0 or cell.x>=document.width or cell.y>=document.depth:return false
		if cell!=last_cell:
			last_cell=cell
			var index:=document.column_index(cell.x,cell.y)
			height=document.column_value("heights",index)
			if height<=0 or document.surface_role_for_palette(document.column_value("top_materials",index))=="stone":return false
		var physical:float=document.origin_y+height
		if ground_style==1:
			var key:=Vector2i(cell.x/TILE_SIZE,cell.y/TILE_SIZE)
			if key!=field_key:field_key=key;field=_smooth_field(key)
			physical=SmoothSurface.sample(field,Vector2(local.x,local.z))
		if absf((world*Vector3(local.x,physical,local.z)).y-center.y)>0.055*unit:return false
	return true


func floor_surface_sample(global_point: Vector3) -> Dictionary:
	if document == null:
		return {"solid": false}
	var local := to_local(global_point)
	var cell := Vector2i(floori(local.x), floori(local.z))
	if cell.x < 0 or cell.y < 0 or cell.x >= document.width or cell.y >= document.depth:
		return {"solid": false, "cell": cell}
	var index := document.column_index(cell.x, cell.y)
	var height := document.column_value("heights", index)
	if height <= 0:
		return {"solid": false, "cell": cell}
	var physical_height: float = _smooth_height(Vector2(local.x,local.z)) if ground_style == 1 else document.origin_y+height
	return {
		"solid": true,
		"physics_ready":not _editor_residency_allowed() or _tiles.has(Vector2i(cell.x/TILE_SIZE,cell.y/TILE_SIZE)),
		"cell": cell,
		"height_voxel": physical_height-document.origin_y-1,
		"palette_index": document.column_value("top_materials", index),
		"material_role": document.surface_role_for_palette(document.column_value("top_materials", index)),
		"position": to_global(Vector3(local.x, physical_height, local.z)),
	}


func pick_ground_top(ray_start: Vector3, ray_end: Vector3,surface_details:=false) -> Dictionary:
	# Read the same columns that build the mesh. Physics shapes can be one tile
	# behind a live brush stroke, so editor hover must not depend on them.
	if document == null:
		return {}
	var origin := to_local(ray_start)
	var segment := to_local(ray_end) - origin
	var length := segment.length()
	if length <= 0.00001:
		return {}
	var direction := segment / length
	var enter := 0.0
	var leave := length
	for axis in 2:
		var coordinate := origin.x if axis == 0 else origin.z
		var speed := direction.x if axis == 0 else direction.z
		var extent := float(document.width if axis == 0 else document.depth)
		if absf(speed) < 0.000001:
			if coordinate < 0.0 or coordinate >= extent:
				return {}
			continue
		var first := -coordinate / speed
		var last := (extent - coordinate) / speed
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
	if enter > leave:
		return {}
	var distance := enter
	var start := origin + direction * minf(leave, enter + 0.0001)
	var x := clampi(floori(start.x), 0, document.width - 1)
	var z := clampi(floori(start.z), 0, document.depth - 1)
	var step_x := -1 if direction.x < -0.000001 else 1 if direction.x > 0.000001 else 0
	var step_z := -1 if direction.z < -0.000001 else 1 if direction.z > 0.000001 else 0
	var next_x := ((float(x + 1 if step_x > 0 else x) - origin.x) / direction.x) if step_x != 0 else INF
	var next_z := ((float(z + 1 if step_z > 0 else z) - origin.z) / direction.z) if step_z != 0 else INF
	var delta_x := absf(1.0 / direction.x) if step_x != 0 else INF
	var delta_z := absf(1.0 / direction.z) if step_z != 0 else INF
	while x >= 0 and z >= 0 and x < document.width and z < document.depth and distance <= leave:
		var end_distance := minf(leave, minf(next_x, next_z))
		var index := document.column_index(x, z)
		var height := document.column_value("heights", index)
		if ground_style == 1 and not (surface_details and world_look==2) and height > 0 and document.column_value("top_materials",index)>0:
			var f := _smooth_field(Vector2i(x/TILE_SIZE,z/TILE_SIZE))
			var a := Vector3(x,SmoothSurface.corner(f,x,z),z)
			var b := Vector3(x+1,SmoothSurface.corner(f,x+1,z),z)
			var c := Vector3(x,SmoothSurface.corner(f,x,z+1),z+1)
			var d := Vector3(x+1,SmoothSurface.corner(f,x+1,z+1),z+1)
			for triangle: Array in [[a,b,c],[b,d,c]]:
				var hit: Variant = Geometry3D.segment_intersects_triangle(origin,origin+segment,triangle[0],triangle[1],triangle[2])
				if hit != null:
					if not surface_details:return {"cell":Vector2i(x,z),"world":to_global(hit)}
					var n:Vector3=(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
					if n.y<0:n=-n
					return {"cell":SmoothSurface.contact_cell(document,hit,n),"world":to_global(hit),"local":hit,"normal":n}
		if (ground_style == 0 or surface_details and world_look==2) and height > 0 and document.column_value("top_materials", index) > 0:
			var entry_y := origin.y + direction.y * distance
			if distance > 0.00001 and entry_y >= float(document.origin_y) and entry_y < float(document.origin_y + height):
				var hit:=origin+direction*distance
				var n:=Vector3.LEFT if absf(hit.x-float(x))<0.0001 else Vector3.RIGHT if absf(hit.x-float(x+1))<0.0001 else Vector3.FORWARD if step_z>0 else Vector3.BACK
				return {"cell":Vector2i(x,z),"world":to_global(hit),"local":hit,"normal":n}
			if absf(direction.y) >= 0.000001:
				var hit_distance := (float(document.origin_y + height) - origin.y) / direction.y
				if hit_distance >= distance - 0.00001 and hit_distance <= end_distance + 0.00001:
					return {"cell":Vector2i(x,z),"world":to_global(origin+direction*hit_distance),"local":origin+direction*hit_distance,"normal":Vector3.UP}
		if next_x < next_z:
			distance = next_x
			next_x += delta_x
			x += step_x
		else:
			distance = next_z
			next_z += delta_z
			z += step_z
	return {}


func set_sea_swash(swash: RefCounted) -> void:
	var affected := {}
	if _sea_swash != null:
		for key in _sea_swash.dry_tiles: affected[key] = true
	_sea_swash = swash
	if _sea_swash == null:
		for material in [_water_material, _ground_material]:
			if material is ShaderMaterial:
				(material as ShaderMaterial).set_shader_parameter("sea_swash_available", 0.0)
	if _sea_swash != null:
		for key in _sea_swash.dry_tiles: affected[key] = true
	for key in affected: _queue_tile(key, true)
	if not _pending.is_empty(): set_process(true)
	_water_revision += 1
	_refresh_far_ground_materials()


func stage_water_regions(fields: RefCounted) -> void:
	_staged_water_fields = fields
	var affected: Dictionary = fields.changed_dry_tiles()
	if _waterfall != fields.waterfall:
		if _waterfall != null: affected.merge(_waterfall.tiles)
		if fields.waterfall != null: affected.merge(fields.waterfall.tiles)
	for key: Vector2i in affected: _queue_tile(key, true)
	if not _pending.is_empty(): set_process(true)


func commit_water_regions(fields: RefCounted) -> void:
	_far_ground_materials.clear()
	_water_regions = fields.regions
	_sea_swash = fields
	_waterfall = fields.waterfall
	_staged_water_fields = null
	for key: Vector2i in _tiles: _apply_region_materials(key, _tiles[key])
	# Materials can arrive/release without a topology change. Rebind the cheap
	# overviews directly; do not rebuild all their geometry for every batch.
	for key:Vector2i in _overviews:
		var node:Node3D=_overviews[key].node
		(node.get_node("Water") as MeshInstance3D).material_override=_water_regions.get(key,{}).get("water",_water_material)
		var material:=_far_material(_region_ground_material(key))
		(node.get_node("Ground") as MeshInstance3D).material_override=material
		var edge:=node.get_node_or_null("ResidencyEdge") as MeshInstance3D
		if edge!=null:edge.material_override=material
	_water_revision += 1


func cancel_water_regions() -> void:
	_staged_water_fields = null


func clear_water_regions() -> void:
	_far_ground_materials.clear()
	_water_regions.clear()
	_staged_water_fields = null
	for key: Vector2i in _tiles: _apply_region_materials(key, _tiles[key])


func _apply_region_materials(key: Vector2i, tile: Node3D) -> void:
	var region: Dictionary = _water_regions.get(Vector2i(key.x / 6, key.y / 6), {})
	var water: ShaderMaterial = region.get("water")
	if water != null: water.set_shader_parameter("sea_smooth_shore", ground_style == 1 and world_look == 0)
	(tile.get_node("Water") as MeshInstance3D).material_override = region.get("water")
	(tile.get_node("Ground") as MeshInstance3D).material_override = region.get("ground")
	if Engine.is_editor_hint():_apply_ground_distance_material(key,_editor_detail_camera(),_ground_material_distance_allowed())


func set_waterfall(waterfall: RefCounted) -> void:
	var affected := {}
	if _waterfall != null:
		for key in _waterfall.tiles: affected[key] = true
	_waterfall = waterfall
	if _waterfall == null and _water_material is ShaderMaterial:
		(_water_material as ShaderMaterial).set_shader_parameter("waterfall_available", 0.0)
	if _waterfall != null:
		for key in _waterfall.tiles: affected[key] = true
	for key in affected: _queue_tile(key, true)
	if not _pending.is_empty(): set_process(true)
	_water_revision += 1


func set_water_surface_offset(offset_voxels: float) -> void:
	# Derived scene parameter: the same offset drives rendering and water queries.
	if not is_finite(offset_voxels): return
	var next := clampf(offset_voxels, -0.75, 0.0)
	if not is_equal_approx(next, _water_surface_offset_voxels):
		_water_surface_offset_voxels = next
		_water_revision += 1
	if _water_material is ShaderMaterial:
		(_water_material as ShaderMaterial).set_shader_parameter("water_level_offset_voxels", next)


func set_wave_obstacles(field: RefCounted) -> void:
	_wave_obstacles = field
	if field == null and _water_material is ShaderMaterial:
		(_water_material as ShaderMaterial).set_shader_parameter("obstacle_patch_count", 0)
	_water_revision += 1


func water_surface_sample(global_point: Vector3) -> Dictionary:
	if document == null:
		return {"wet": false}
	var local := to_local(global_point)
	var cell := Vector2i(floori(local.x), floori(local.z))
	var block_world_size := to_global(Vector3.RIGHT).distance_to(to_global(Vector3.ZERO)) * float(TerrainResource.CELLS_PER_BLOCK)
	if cell.x < 0 or cell.y < 0 or cell.x >= document.width or cell.y >= document.depth:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	var index := document.column_index(cell.x, cell.y)
	if _sea_swash != null:
		var swash: Dictionary = _sea_swash.sample(cell, false)
		if not swash.is_empty() and (bool(swash.dry_bank) or (_sea_swash.active_height > 0.001 and _sea_swash.coastal_influence(float(swash.distance)) > 0.001)):
			if ground_style == 1 and world_look == 0:
				var point := Vector2(local.x, local.z)
				var detail_surface: float = _sea_swash.surface_height(point, true)
				if not bool(swash.dry_bank):
					var base := float(document.origin_y + document.column_value("water_levels", index)) + 0.085 + _water_surface_offset_voxels
					detail_surface = lerpf(base, detail_surface, _sea_swash.coastal_influence(float(swash.distance)))
				if _wave_obstacles != null and not bool(swash.dry_bank): detail_surface += _wave_obstacles.sample(point).x
				return {"wet": detail_surface > _smooth_height(point) + 0.02, "cell": cell,
					"block_world_size": block_world_size, "position": to_global(Vector3(local.x,detail_surface,local.z)), "flow": Vector2.ZERO,
					"open_swell_weight": 0.0 if swash.dry_bank else 1.0 - _sea_swash.coastal_influence(float(swash.distance))}
			if bool(swash.dry_bank) and float(swash.coverage) <= 0.05:
				return {"wet": false, "cell": cell, "block_world_size": block_world_size}
			var surface: float = _sea_swash.surface_height(Vector2(local.x, local.z))
			if not bool(swash.dry_bank):
				var base := float(document.origin_y + document.column_value("water_levels", index)) + 0.085 + _water_surface_offset_voxels
				surface = lerpf(base, surface, _sea_swash.coastal_influence(float(swash.distance)))
			if _wave_obstacles != null and not bool(swash.dry_bank): surface += _wave_obstacles.sample(Vector2(local.x, local.z)).x
			if bool(swash.dry_bank): surface = maxf(surface, document.origin_y + document.column_value("heights", index) + 0.025)
			return {"wet": true, "cell": cell, "block_world_size": block_world_size,
				"position": to_global(Vector3(local.x, surface, local.z)), "flow": Vector2.ZERO}
	var level := document.column_value("water_levels", index)
	if level <= document.column_value("heights", index) or document.column_value("water_materials", index) == 0:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	return {
		"wet": true,
		"cell": cell,
		"position": to_global(Vector3(local.x, document.origin_y + level + 0.085 + _water_surface_offset_voxels
			+ (_wave_obstacles.sample(Vector2(local.x, local.z)).x if _wave_obstacles != null else 0.0)
			+ (_waterfall.displacement(Vector2(local.x, local.z)) if _waterfall != null and level == _waterfall.info.get("lower_level", -1) else 0.0), local.z)),
		"block_world_size": block_world_size,
		"flow": document.flow_at_cell(cell.x, cell.y),
		"open_swell_weight": smoothstep(0.0, 12.0, float(level - document.column_value("heights", index))),
	}


func water_revision() -> int:
	return _water_revision


func navigation_path(global_start: Vector3, global_goal: Vector3, max_step_voxels := 4) -> PackedVector3Array:
	var result := PackedVector3Array()
	if document == null or document.width % TerrainResource.CELLS_PER_BLOCK != 0 or document.depth % TerrainResource.CELLS_PER_BLOCK != 0:
		return result
	if _navigation_grid.is_empty():
		_navigation_grid = _build_navigation_grid()
	var width: int = _navigation_grid.width
	var block_heights: PackedInt32Array = _navigation_grid.heights
	var start_local := to_local(global_start)
	var goal_local := to_local(global_goal)
	var blocks: Array[Vector2i] = SurfacePhysics.find_block_path_from_grid(
		_navigation_grid,
		Vector2i(floori(start_local.x / float(TerrainResource.CELLS_PER_BLOCK)), floori(start_local.z / float(TerrainResource.CELLS_PER_BLOCK))),
		Vector2i(floori(goal_local.x / float(TerrainResource.CELLS_PER_BLOCK)), floori(goal_local.z / float(TerrainResource.CELLS_PER_BLOCK))),
		max_step_voxels,
	)
	for block in blocks:
		var height := block_heights[block.x + block.y * width]
		var p := Vector2((block.x+0.5)*TerrainResource.CELLS_PER_BLOCK,(block.y+0.5)*TerrainResource.CELLS_PER_BLOCK)
		var y: float = _physical_height(p,_smooth_height(p) if ground_style == 1 else document.origin_y+height)
		result.append(to_global(Vector3(p.x,y+1,p.y)))
	return result


func _build_navigation_grid() -> Dictionary:
	var width := document.width / TerrainResource.CELLS_PER_BLOCK
	var depth := document.depth / TerrainResource.CELLS_PER_BLOCK
	var block_heights := PackedInt32Array()
	block_heights.resize(width * depth)
	block_heights.fill(-1)
	var areas: Array[Rect2i] = []
	if document.is_sectioned():
		for address: Vector2i in document.sections:
			var part := document.sections[address] as TerrainResource
			areas.append(Rect2i(address * (TerrainResource.Sections.CELLS / TerrainResource.CELLS_PER_BLOCK), Vector2i(ceili(float(part.width) / TerrainResource.CELLS_PER_BLOCK), ceili(float(part.depth) / TerrainResource.CELLS_PER_BLOCK))))
	else:
		areas.append(Rect2i(0, 0, width, depth))
	for area in areas:
		for bz in range(area.position.y, area.end.y):
			for bx in range(area.position.x, area.end.x):
				var samples: Array[int] = []
				for oz in [TerrainResource.CELLS_PER_BLOCK / 4, TerrainResource.CELLS_PER_BLOCK / 2, TerrainResource.CELLS_PER_BLOCK * 3 / 4]:
					for ox in [TerrainResource.CELLS_PER_BLOCK / 4, TerrainResource.CELLS_PER_BLOCK / 2, TerrainResource.CELLS_PER_BLOCK * 3 / 4]:
						var height := document.column_value("heights", document.column_index(bx * TerrainResource.CELLS_PER_BLOCK + ox, bz * TerrainResource.CELLS_PER_BLOCK + oz))
						if height > 0:
							var point := Vector2(bx*TerrainResource.CELLS_PER_BLOCK+ox,bz*TerrainResource.CELLS_PER_BLOCK+oz)
							samples.append(roundi(_physical_height(point,_smooth_height(point) if ground_style==1 else document.origin_y+height)-document.origin_y)-1)
				if samples.size() >= 5:
					samples.sort()
					block_heights[bx + bz * width] = samples[samples.size() / 2]
	return {"width": width, "depth": depth, "heights": block_heights}


func apply_heights(indices: PackedInt32Array, values: PackedInt32Array) -> void:
	if document == null or indices.size() != values.size():
		return
	for index in indices:
		if index < 0 or not document.has_column(index % document.width, index / document.width):
			return
	var tops := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	for index in indices:
		tops.append(document.column_value("top_materials", index))
		waters.append(document.column_value("water_levels", index))
		water_colors.append(document.column_value("water_materials", index))
	apply_columns(indices, values, tops, waters, water_colors)


func apply_side_materials(values:Dictionary,written_source:TerrainResource) -> void:
	if document==null or values.is_empty():return
	_ensure_surface_tile_revisions()
	document.write_side_overrides(values)
	var dirty:Dictionary={}
	_column_revision+=1
	for index:int in values:
		var cell:=Vector2i(index%document.width,index/document.width)
		# Detail triangles/pick use the neighbouring source columns. Only the
		# local tile and its one-cell halo need new attributes.
		for z in range(maxi(0,cell.y-1)/TILE_SIZE,mini(document.depth-1,cell.y+1)/TILE_SIZE+1):
			for x in range(maxi(0,cell.x-1)/TILE_SIZE,mini(document.width-1,cell.x+1)/TILE_SIZE+1):dirty[Vector2i(x,z)]=true
	for key:Vector2i in dirty:
		_surface_tile_revisions[key.x+key.y*_pending_tile_columns]=_column_revision
		_queue_tile(key,true)
	set_process(true)


func apply_columns(indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, water_colors: PackedByteArray, written_source: TerrainResource = null,restore_payload:=false) -> void:
	_startup_budget_allowed=false
	_ensure_surface_tile_revisions()
	if document == null or indices.size() != heights.size() or indices.size() != tops.size() or indices.size() != waters.size() or indices.size() != water_colors.size():
		return
	if document.is_sectioned():
		_apply_section_columns(indices, heights, tops, waters, water_colors, written_source,restore_payload)
		return
	var all_heights := document.heights
	var all_caps := document.cap_depths
	# Dense brush history restores caps in Source before publishing columns.
	# Other callers retain the same clipping rule as sectioned writes.
	var written_caps := written_source.cap_depths if written_source != null and written_source == source else PackedByteArray()
	var all_tops := document.top_materials
	var all_waters := document.water_levels
	var all_water_colors := document.water_materials
	var tile_columns := (document.width + TILE_SIZE - 1) / TILE_SIZE
	var tile_rows := (document.depth + TILE_SIZE - 1) / TILE_SIZE
	var dirty := PackedByteArray()
	dirty.resize(tile_columns * tile_rows)
	var grid_dirty := PackedByteArray()
	grid_dirty.resize(tile_columns * tile_rows)
	var changed_ground := false
	var changed_water := false
	for i in indices.size():
		var index := indices[i]
		if index < 0 or index >= all_heights.size():
			continue
		var cap := mini(written_caps[index] if index < written_caps.size() else all_caps[index], heights[i])
		if all_heights[index] == heights[i] and all_caps[index] == cap and all_tops[index] == tops[i] and all_waters[index] == waters[i] and all_water_colors[index] == water_colors[i]:
			continue
		var grid_changed := all_heights[index] != heights[i] or (all_tops[index] == 0) != (tops[i] == 0)
		changed_ground = changed_ground or all_heights[index] != heights[i]
		changed_water = changed_water or all_waters[index] != waters[i] or all_water_colors[index] != water_colors[i]
		all_heights[index] = clampi(heights[i], 0, document.height_limit)
		all_caps[index] = cap
		all_tops[index] = tops[i]
		all_waters[index] = maxi(0, waters[i])
		all_water_colors[index] = water_colors[i]
		var x := index % document.width
		var z := index / document.width
		if ground_style == 1: _mark_smooth_neighbours(Vector2i(x,z),dirty,grid_dirty,grid_changed,tile_columns,tile_rows)
		var tile_index := x / TILE_SIZE + z / TILE_SIZE * tile_columns
		dirty[tile_index] = 1
		if grid_changed: grid_dirty[tile_index] = 1
		if x % TILE_SIZE == 0 and x > 0:
			dirty[tile_index - 1] = 1
			if grid_changed: grid_dirty[tile_index - 1] = 1
		if x % TILE_SIZE == TILE_SIZE - 1 and x + 1 < document.width:
			dirty[tile_index + 1] = 1
			if grid_changed: grid_dirty[tile_index + 1] = 1
		if z % TILE_SIZE == 0 and z > 0:
			dirty[tile_index - tile_columns] = 1
			if grid_changed: grid_dirty[tile_index - tile_columns] = 1
		if z % TILE_SIZE == TILE_SIZE - 1 and z + 1 < document.depth:
			dirty[tile_index + tile_columns] = 1
			if grid_changed: grid_dirty[tile_index + tile_columns] = 1
	var has_dirty := false
	for tile_index in dirty.size():
		if dirty[tile_index] == 0:
			continue
		has_dirty = true
		var key := Vector2i(tile_index % tile_columns, tile_index / tile_columns)
		_queue_tile(key, true)
	if has_dirty:
		document.heights = all_heights
		document.cap_depths = all_caps
		document.top_materials = all_tops
		document.water_levels = all_waters
		document.water_materials = all_water_colors
		_column_revision += 1
		for tile_index in dirty.size():
			if dirty[tile_index]!=0:_surface_tile_revisions[tile_index]=_column_revision
		for tile_index in grid_dirty.size():
			if grid_dirty[tile_index] != 0:
				_tile_revisions[tile_index] = _column_revision
		if changed_ground:
			_navigation_grid.clear()
		if changed_water:
			_water_revision += 1
	set_process(true)


func _apply_section_columns(indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, colors: PackedByteArray, written_source: TerrainResource = null,restore_payload:=false) -> void:
	var dirty := PackedByteArray()
	dirty.resize(_pending_flags.size())
	var grid_dirty := PackedByteArray()
	grid_dirty.resize(dirty.size())
	var has_dirty := false
	var has_grid_dirty := false
	var changed_water := false
	var read_address := Vector2i(-1, -1)
	var part: TerrainResource
	var part_heights := PackedInt32Array()
	var part_tops := PackedByteArray()
	var part_waters := PackedInt32Array()
	var part_colors := PackedByteArray()
	var part_caps:=PackedByteArray();var part_bases:=PackedByteArray()
	var restored_caps:=PackedByteArray();var restored_bases:=PackedByteArray()
	var restored: TerrainResource
	var changed_parts := {}
	var width := document.width
	var count := width * document.depth
	for i in indices.size():
		var index := indices[i]
		if index < 0 or index >= count: continue
		var cell := Vector2i(index % width, index / width)
		var address := Vector2i(cell.x / TerrainResource.Sections.CELLS, cell.y / TerrainResource.Sections.CELLS)
		if address != read_address:
			read_address = address
			part = document.sections.get(address) as TerrainResource
			if part != null:
				part_heights = part.heights
				part_tops = part.top_materials
				part_waters = part.water_levels
				part_colors = part.water_materials
				if restore_payload and written_source!=null and written_source==source:
					part_caps=part.cap_depths;part_bases=part.base_materials
					restored=written_source.sections.get(address)
					if restored!=null:restored_caps=restored.cap_depths;restored_bases=restored.base_materials
		if part == null: continue
		var local_cell := cell % TerrainResource.Sections.CELLS
		if local_cell.x >= part.width or local_cell.y >= part.depth: continue
		var local_index := local_cell.x + local_cell.y * part.width
		var height := part_heights[local_index]
		var top := part_tops[local_index]
		var water := part_waters[local_index]
		var color := part_colors[local_index]
		var payload_changed: bool=restored!=null and (part_caps[local_index]!=restored_caps[local_index] or part_bases[local_index]!=restored_bases[local_index] or part.column_material_overrides.get(local_index,{})!=restored.column_material_overrides.get(local_index,{}))
		if height == heights[i] and top == tops[i] and water == waters[i] and color == colors[i] and not payload_changed: continue
		var grid_changed := height != heights[i] or (top == 0) != (tops[i] == 0)
		changed_water = changed_water or water != waters[i] or color != colors[i]
		has_dirty = true
		changed_parts[address] = true
		has_grid_dirty = has_grid_dirty or grid_changed
		if ground_style == 1: _mark_smooth_neighbours(cell,dirty,grid_dirty,grid_changed,_pending_tile_columns,_pending_tile_rows)
		var tile_index := cell.x / TILE_SIZE + cell.y / TILE_SIZE * _pending_tile_columns
		dirty[tile_index] = 1
		if grid_changed: grid_dirty[tile_index] = 1
		# Interior neighbours belong to this same tile. Only boundary columns
		# can invalidate another tile, including across an addressed section.
		var tile_x := cell.x % TILE_SIZE
		var tile_z := cell.y % TILE_SIZE
		if tile_x != 0 and tile_x != TILE_SIZE - 1 and tile_z != 0 and tile_z != TILE_SIZE - 1: continue
		var neighbours: Array[Vector2i] = []
		if cell.x % TILE_SIZE == 0: neighbours.append(cell + Vector2i.LEFT)
		if cell.x % TILE_SIZE == TILE_SIZE - 1: neighbours.append(cell + Vector2i.RIGHT)
		if cell.y % TILE_SIZE == 0: neighbours.append(cell + Vector2i.UP)
		if cell.y % TILE_SIZE == TILE_SIZE - 1: neighbours.append(cell + Vector2i.DOWN)
		for point in neighbours:
			if not document.has_column(point.x, point.y): continue
			var neighbour_index := point.x / TILE_SIZE + point.y / TILE_SIZE * _pending_tile_columns
			dirty[neighbour_index] = 1
			if grid_changed: grid_dirty[neighbour_index] = 1
	if not has_dirty: return
	if written_source != null and written_source == source and written_source.is_sectioned() and written_source != document:
		# The brush already published immutable payloads to this projection's
		# source. Reuse those exact payloads after comparing the old document;
		# do not copy and apply the same large batch a second time.
		for address: Vector2i in changed_parts: document.sections[address] = written_source.sections[address]
	else:
		document.write_columns(indices, heights, tops, waters, colors)
	_column_revision += 1
	for tile_index in dirty.size():
		if dirty[tile_index] != 0:
			_surface_tile_revisions[tile_index]=_column_revision
			_queue_tile(Vector2i(tile_index % _pending_tile_columns, tile_index / _pending_tile_columns), true)
		if grid_dirty[tile_index] != 0: _tile_revisions[tile_index] = _column_revision
	if has_grid_dirty: _navigation_grid.clear()
	if changed_water: _water_revision += 1
	set_process(true)


func _mark_smooth_neighbours(cell: Vector2i, dirty: PackedByteArray, grid: PackedByteArray, changed: bool, columns: int, rows: int) -> void:
	var begin := (cell-Vector2i(SmoothSurface.HALO,SmoothSurface.HALO))/TILE_SIZE
	var end := (cell+Vector2i(SmoothSurface.HALO,SmoothSurface.HALO))/TILE_SIZE
	for z in range(maxi(0,begin.y),mini(rows-1,end.y)+1):
		for x in range(maxi(0,begin.x),mini(columns-1,end.x)+1):
			dirty[x+z*columns] = 1
			if changed: grid[x+z*columns] = 1


func _reset_pending_flags() -> void:
	_smooth_fields.clear()
	_pending_tile_columns = ceili(float(document.width) / TILE_SIZE)
	_pending_tile_rows = ceili(float(document.depth) / TILE_SIZE)
	_pending_flags.resize(_pending_tile_columns * _pending_tile_rows)
	_pending_flags.fill(0)
	_pending_edit_flags.resize(_pending_flags.size())
	_pending_edit_flags.fill(0)
	_pending_since_us.resize(_pending_flags.size())
	_pending_since_us.fill(Time.get_ticks_usec())
	_last_edit_build_us.resize(_pending_flags.size())
	_last_edit_build_us.fill(0)
	for key in _pending:
		_pending_flags[key.x + key.y * _pending_tile_columns] = 1
	_pending_needs_sort = not _pending.is_empty()


func _reset_tile_revisions() -> void:
	_tile_revisions.resize(_pending_tile_columns * _pending_tile_rows)
	_tile_revisions.fill(_column_revision)
	_surface_tile_revisions.resize(_tile_revisions.size());_surface_tile_revisions.fill(_column_revision)

func surface_tile_revision(key:Vector2i)->int:
	# Scatter follows height, paint and wetness. The brush-grid revision above
	# deliberately excludes paint-only edits and keeps its previous semantics.
	if key.x<0 or key.y<0 or key.x>=_pending_tile_columns or key.y>=_pending_tile_rows:return -1
	_ensure_surface_tile_revisions()
	return _surface_tile_revisions[key.x+key.y*_pending_tile_columns]

func _ensure_surface_tile_revisions()->void:
	# Existing tool instances can survive a script refresh with an empty new cache.
	var size:=_pending_tile_columns*_pending_tile_rows
	if _surface_tile_revisions.size()!=size:
		_surface_tile_revisions.resize(size);_surface_tile_revisions.fill(_column_revision)


func tile_revision(key: Vector2i) -> int:
	if key.x < 0 or key.y < 0 or key.x >= _pending_tile_columns or key.y >= _pending_tile_rows:
		return -1
	return _tile_revisions[key.x + key.y * _pending_tile_columns]


func _queue_tile(key: Vector2i, front: bool) -> void:
	_preview_tiles_to_publish.erase(key)
	if key.x < 0 or key.y < 0 or key.x >= _pending_tile_columns or key.y >= _pending_tile_rows:
		return
	if document.is_sectioned() and not document.has_column(key.x * TILE_SIZE, key.y * TILE_SIZE): return
	if _editor_residency_allowed():
		if front:
			# Coarse normals and shared border samples also depend on neighbours.
			var section:=_overview_section(key)
			for dz in [-1,0,1]:
				for dx in [-1,0,1]:_queue_overview(section+Vector2i(dx,dz))
		if not _resident_tiles.has(key):return
	_geometry_request_serial += 1
	_geometry_requests[key] = _geometry_request_serial
	if _editor_surface_jobs.has(key):
		var record: Dictionary=_editor_surface_jobs[key]
		if not (_live_brush_active and record.live and record.epoch==_editor_brush_epoch):
			record.cancellation.set_cancelled(true)
	if not Engine.is_editor_hint():
		# A newer terrain/water request must never publish an older CPU snapshot.
		_geometry_prepared.erase(key)
	# Picking/floor queries follow the last published mesh while a shape job
	# runs. Computing a fresh full field on mouse motion would block the UI.
	if ground_style!=1 or not _smooth_fields.has(key):_smooth_fields.erase(key)
	var index := key.x + key.y * _pending_tile_columns
	if front:
		_detail_requested[key]=true
		if not _detail_full_tiles.get(key,true):_editor_surface_layouts.erase(key)
	if _pending_flags[index] != 0:
		if front: _pending_edit_flags[index] = 1
		_profile_add("coalesced_tile_requests", 1)
		return
	_pending_flags[index] = 1
	_pending_edit_flags[index] = 1 if front else 0
	_pending_since_us[index] = Time.get_ticks_usec()
	if front:
		_pending.push_front(key)
	else:
		_pending.append(key)
	_pending_needs_sort = true


func _prioritize_pending() -> void:
	var live:=Engine.is_editor_hint() and _live_brush_active
	var anchor:=_editor_brush_center if live else camera_anchor
	var centre_offset:=Vector2.ONE*TILE_SIZE*0.5 if live else Vector2.ZERO
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := (Vector2(a * TILE_SIZE)+centre_offset - Vector2(anchor)).length_squared()
		var distance_b := (Vector2(b * TILE_SIZE)+centre_offset - Vector2(anchor)).length_squared()
		return distance_a < distance_b if distance_a != distance_b else a.y < b.y if a.y != b.y else a.x < b.x
	)
	_pending_needs_sort = false


func pending_tile_count() -> int:
	return _pending.size()


func built_tile_count() -> int:
	return _tiles.size()


func save_document(path: String) -> Error:
	if document == null or not document.validation_errors().is_empty():
		return ERR_INVALID_DATA
	return ResourceSaver.save(document, path)


func reopen_document(path: String) -> bool:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	return open_document(loaded)
