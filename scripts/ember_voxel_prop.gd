@tool
class_name EmberVoxelProp
extends Node3D
## Instance of a voxel PackedScene on an authored map.

const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")
const RuntimeShadowLod := preload("res://scripts/ember_runtime_shadow_lod.gd")
const ObjectMoss := preload("res://scripts/ember_object_moss.gd")

@export var model_id := ""
@export var placement_id := ""
@export_storage var voxels_per_block := 16
@export_storage var block_world_size := 16.0
@export_storage var moss_mask := PackedByteArray():
	set(value):
		if not value.is_empty() and value.size() != ObjectMoss.BYTE_COUNT:
			return
		if value == moss_mask:
			return
		moss_mask = value
		_moss_texture = null
		_moss_tuft_source = null
		if is_node_ready():
			var visual := get_node_or_null("Mesh") as MeshInstance3D
			if visual != null:
				if _has_bark(visual): _apply_tree_moss(visual)
				else: _bind_moss(visual.get_active_material(0) as ShaderMaterial)
## 1 — размер материала земли; больше — крупнее рисунок только этого экземпляра.
## Меняет цвет, световой рисунок и частоту рельефа, но не его глубину и не форму.
@export_range(0.125,16.0,0.025) var material_pattern_scale := 1.0:
	set(value):
		material_pattern_scale=clampf(value,0.125,16.0) if is_finite(value) else 1.0
		_sync_solid_unit()
		if is_inside_tree():
			var ancestor:=get_parent()
			while ancestor!=null and not ancestor is EmberMapLoader:ancestor=ancestor.get_parent()
			if ancestor is EmberMapLoader:ancestor.anomaly_materials_changed.emit()
@export_group("Вода")
@export var water_contact_enabled := false:
	set(value):
		water_contact_enabled = value
		if is_node_ready(): _sync_water_contact()
@export_range(0.05, 1.5, 0.01) var water_contact_radius_blocks := 0.30:
	set(value):
		water_contact_radius_blocks = value
		if is_node_ready(): _sync_water_contact()
@export_group("")
var _moss_texture: ImageTexture3D
var _moss_tufts: MeshInstance3D
var _moss_tuft_source: Mesh
var _moss_tuft_detail := Vector3.ZERO
var _moss_preview := Vector3.ZERO
var _tree_moss_material: ShaderMaterial
var _tree_moss_base_override: Material
var _moss_bark_source: Mesh
var _moss_bark_bounds := AABB()
var _moss_pick_source: Mesh
var _moss_pick_triangles: TriangleMesh
var _floor_mesh: Mesh
var _floor_faces:=PackedVector3Array()
var _floor_data_ready:=false
var _floor_revision:=0
var _floor_grid:Dictionary={}
var _floor_bin_bounds:=PackedInt32Array()
var _floor_world_transform:=Transform3D()
var _floor_cell_size:=0.0
var _floor_shape:Shape3D
var _floor_slots:=PackedByteArray()
var _floor_roles:=PackedStringArray()
var _floor_stamp:=0
var _surface_change_bounds:=AABB()
var _tree_meshes: Dictionary = {}
var _world_look := -1
var _published_material: Material
## Unsaved Canvas forms use the same Source in memory until ordinary Save.
## Not exported: an editor draft never becomes embedded gameplay state.
var _external_meshes: Dictionary={}
var _external_active:=false
var authoring_source: EmberVoxelModelResource
var authoring_preview: WeakRef
static var _solid_sources:Dictionary={}
static var _solid_filesystem_hooked:=false

static func _forget_solid_source(path:String)->void:
	_solid_sources.erase(path)

static func _forget_solid_sources()->void:
	_solid_sources.clear()

func _solid_source() -> EmberVoxelModelResource:
	if authoring_source!=null:return authoring_source
	var path:="res://content/voxel_models/%s.tres"%model_id
	if _solid_sources.has(path):return _solid_sources[path]
	var source:=load(path) as EmberVoxelModelResource
	if source==null:return null
	remember_solid_source(path, source)
	return source

static func remember_solid_source(path: String, source: EmberVoxelModelResource) -> void:
	if _solid_sources.size()>=4:_solid_sources.erase(_solid_sources.keys()[0])
	_solid_sources[path]=source
	var invalidate:=_forget_solid_source.bind(path)
	if not source.changed.is_connected(invalidate):source.changed.connect(invalidate)
	if Engine.is_editor_hint() and not _solid_filesystem_hooked:
		var editor:=Engine.get_singleton("EditorInterface")
		if editor!=null:
			var filesystem:Object=editor.call("get_resource_filesystem")
			if not filesystem.is_connected("filesystem_changed",_forget_solid_sources):filesystem.connect("filesystem_changed",_forget_solid_sources)
			_solid_filesystem_hooked=true

var _solid_material_initialized := false
var _world_look_initialized := false
var _voxel_light_tree_meshes: Dictionary = {}
var _tree_authored_overrides:Array[Material]=[]
var _tree_overrides_initialized:=false
var _distance_managed:=false
var _distance_resident:=true
var _distance_ready:=false
var _distance_mesh:ArrayMesh
var _distance_source:ArrayMesh
var _distance_flat_mesh:ArrayMesh
var packed_detail_path := ""
var packed_detail_mesh: ArrayMesh
var packed_detail_wanted := false
var _runtime_physics_state:Array=[] # Derived body processing state; never a new collider.
var _runtime_shadow: RefCounted

func update_runtime_shadow_lod(state:Dictionary)->bool:
	if _runtime_shadow==null:_runtime_shadow=RuntimeShadowLod.new()
	return _runtime_shadow.update(self,state)

func recheck_runtime_shadow_receivers(state:Dictionary)->bool:
	return _runtime_shadow!=null and _runtime_shadow.recheck_receivers(state)

func restore_runtime_shadow_lod()->void:
	if _runtime_shadow!=null:_runtime_shadow.restore()

func runtime_physics_safe()->bool:
	if Engine.is_editor_hint() or authoring_source!=null or (authoring_preview!=null and is_instance_valid(authoring_preview.get_ref())):return false
	# Gameplay subclasses/components and moving platforms retain their own activity.
	if get_script()!=load("res://scripts/ember_voxel_prop.gd"):return false
	var body:=get_node_or_null("Collision") as StaticBody3D
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if body==null or body is AnimatableBody3D or body.get_script()!=null or shape==null or shape.shape==null or shape.disabled:return false
	if body.constant_linear_velocity!=Vector3.ZERO or body.constant_angular_velocity!=Vector3.ZERO:return false
	if _runtime_physics_state.is_empty() and body.process_mode!=Node.PROCESS_MODE_INHERIT:return false
	for child in get_children():
		if child.name not in [&"Mesh",&"Collision",&"ShadowBody",&"WaterContact"] and not child is Light3D:return false
	return body.get_child_count()==1 and shape.get_child_count()==0

func set_runtime_physics_active(active:bool)->void:
	if active:
		if _runtime_physics_state.is_empty():return
		var body:StaticBody3D=_runtime_physics_state[0].get_ref()
		if is_instance_valid(body):
			body.disable_mode=_runtime_physics_state[2]
			body.process_mode=_runtime_physics_state[1]
		_runtime_physics_state.clear()
	elif _runtime_physics_state.is_empty() and runtime_physics_safe():
		var body:=get_node("Collision") as StaticBody3D
		_runtime_physics_state=[weakref(body),body.process_mode,body.disable_mode]
		# Native REMOVE leaves authored shape/layers and floor/navigation queries intact.
		body.disable_mode=CollisionObject3D.DISABLE_MODE_REMOVE
		body.process_mode=Node.PROCESS_MODE_DISABLED

func _owning_map()->EmberMapLoader:
	var ancestor:=get_parent()
	while ancestor!=null and not ancestor is EmberMapLoader:ancestor=ancestor.get_parent()
	return ancestor as EmberMapLoader

func object_detail_base()->ArrayMesh:
	if not _tree_meshes.is_empty():return _tree_meshes[0]
	if _external_active and _external_meshes.get(0)!=null:return _external_meshes[0]
	if _distance_flat_mesh!=null:return _distance_flat_mesh
	if _hull_mesh!=null:return _hull_mesh
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	return visual.mesh as ArrayMesh if visual!=null else null

func object_detail_safe()->bool:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh:return false
	# A direct authored replacement must never be mistaken for our old carrier.
	if not _tree_meshes.is_empty():return visual.mesh in _tree_meshes.values() or visual.mesh==_distance_mesh
	if _hull_mesh!=null:return visual.mesh in [_hull_mesh,_living_mesh,_voxel_mesh,_distance_mesh,_distance_flat_mesh] or visual.mesh in _external_meshes.values()
	return true

func object_detail_bounds()->AABB:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	var base:=object_detail_base()
	return visual.global_transform*base.get_aabb() if visual!=null and base!=null else AABB(global_position,Vector3.ZERO)

## Existing far solid path requires its Source and face descriptors. Leave trees,
## external and edited-volume paths with their existing representation owners.
func object_far_material_mesh() -> ArrayMesh:
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or not visual.mesh is ArrayMesh: return null
	if get_meta("ember_external_source", false) or (authoring_source != null and not authoring_source.external_surface.is_empty()): return null
	var hull := _hull_mesh if _hull_mesh != null else visual.mesh as ArrayMesh
	if hull.get_surface_count() == 0 or hull.surface_get_name(0) != "solid_surface": return null
	return hull

func object_far_preparation_mesh() -> ArrayMesh:
	var hull := object_far_material_mesh()
	return hull if hull != null and not hull.get_meta("solid_volume_boundary", false) else null


func apply_object_detail(resident:bool)->void:
	restore_runtime_shadow_lod()
	_distance_managed=true;_distance_resident=resident
	for look in _tree_meshes.keys():
		if look!=0:_tree_meshes.erase(look)
	for look in _voxel_light_tree_meshes.keys():
		if look!=0:_voxel_light_tree_meshes.erase(look)
	if resident:_distance_mesh=null;_distance_source=null;_distance_flat_mesh=null
	set_world_look(0)
	_distance_ready=true

func restore_object_detail(look:int)->void:
	restore_runtime_shadow_lod()
	_distance_managed=false;_distance_resident=true;_distance_ready=false
	_distance_mesh=null;_distance_source=null;_distance_flat_mesh=null
	set_world_look(look)

func object_lod_allowed()->bool:
	if not _distance_managed:return false
	if not _distance_resident:return true
	# Preparation residency follows the player. Render LOD follows the camera:
	# a wide shot must also simplify detailed trees close to the player.
	# The native carrier retains LOD0; authoring and other looks keep their source.
	if Engine.is_editor_hint() or _world_look!=0:return false
	if authoring_preview!=null and is_instance_valid(authoring_preview.get_ref()):return false
	var source:=object_detail_base()
	return source!=null and source.get_surface_count()>0 and source.surface_get_name(0)=="tree_bark"


func install_object_lod(source:ArrayMesh,mesh:ArrayMesh)->void:
	if not object_lod_allowed() or object_detail_base()!=source or not object_detail_safe():return
	restore_runtime_shadow_lod()
	_distance_source=source;_distance_mesh=mesh
	get_node("Mesh").mesh=mesh
	_bind_map_lighting()

func _set_far_object_detail(visual:MeshInstance3D)->void:
	if visual.mesh.surface_get_name(0)=="tree_bark":
		if _tree_meshes.is_empty():_tree_meshes[0]=visual.mesh
		for look in _tree_meshes.keys():
			if look!=0:_tree_meshes.erase(look)
		_voxel_light_tree_meshes.clear()
		visual.mesh=_tree_meshes[0]
	elif _set_external_look(0):
		for look in _external_meshes.keys():
			if look!=0:_external_meshes.erase(look)
	elif _hull_mesh!=null or visual.mesh.surface_get_name(0)=="solid_surface":
		if _hull_mesh==null:_hull_mesh=visual.mesh
		_distance_flat_mesh=_hull_mesh
		if not _hull_mesh.get_meta("solid_volume_boundary",false):
			var source:=_solid_source()
			if source!=null and not source.solid_surface.is_empty():
				# Preserve the accepted face IDs, pigment/weathering and UV layout.
				# Only fine form drift is omitted. The flat carrier is shared by hull.
				_distance_flat_mesh=load("res://scripts/ember_solid_material_layers.gd").prepared_mesh(_hull_mesh,func():return EmberVoxelPrefab.model_of(source.to_definition()))
		visual.mesh=_distance_flat_mesh
		_solid_look=SOLID_LOOK_DETAILED
		refresh_solid_material()
		_sync_solid_depth(true)
	_living_mesh=null;_voxel_mesh=null
	# Keep the published physical surface, release only generated duplicates.
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if shape!=null and _published_volume_shape!=null and shape.shape in _volume_shapes.values():shape.shape=_published_volume_shape
	_volume_shapes.clear()
	set_process(false)
	if _distance_source==object_detail_base() and _distance_mesh!=null:visual.mesh=_distance_mesh
	_bind_map_lighting()

func _remember_tree_overrides(visual:MeshInstance3D,capture_reset:=false)->void:
	if visual.mesh==null:return
	var count:=visual.mesh.get_surface_count()
	if _tree_authored_overrides.size()<count:_tree_authored_overrides.resize(count)
	for surface in count:
		var material:=visual.get_surface_override_material(surface)
		if material!=null and material.get_meta("ember_derived_tree_material",false):continue
		if not _tree_overrides_initialized or material!=null or capture_reset:
			if _tree_authored_overrides[surface]!=material:_voxel_light_tree_meshes.clear()
			_tree_authored_overrides[surface]=material
	_tree_overrides_initialized=true


func apply_voxel_light_settings(map: EmberMapLoader) -> void:
	restore_runtime_shadow_lod()
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or visual.mesh == null or visual.mesh.get_surface_count() == 0: return
	# Named presentation surfaces belong to ArrayMesh, not primitive placeholders.
	if not visual.mesh is ArrayMesh: return
	if visual.mesh.surface_get_name(0) == "tree_bark":
		_remember_tree_overrides(visual)
		# Runtime bindings share within their owning map; editor previews stay private.
		var cached: Dictionary = _voxel_light_tree_meshes.get(_world_look, {})
		if cached.is_empty() or visual.mesh != cached.source:
			var materials:Array[Material]=[]
			for surface in visual.mesh.get_surface_count():
				var material:Material=_tree_authored_overrides[surface] if surface<_tree_authored_overrides.size() else null
				if material==null:material=visual.mesh.surface_get_material(surface)
				if material is ShaderMaterial and not Engine.is_editor_hint():
					material=map.runtime_tree_material(material,_world_look)
				else:
					material=material.duplicate() if material!=null else null
				if material!=null:material.set_meta("ember_derived_tree_material",true)
				materials.append(material)
			cached = {"source": visual.mesh, "materials": materials}
			_voxel_light_tree_meshes[_world_look] = cached
		for surface in visual.mesh.get_surface_count():
			visual.set_surface_override_material(surface,cached.materials[surface])
			map.bind_voxel_light(cached.materials[surface] as ShaderMaterial, _world_look, 1.0)
		_apply_tree_moss(visual)
	elif visual.mesh.surface_get_name(0) == "solid_surface":
		var material := visual.get_active_material(0) as ShaderMaterial
		map.bind_voxel_light(material, _world_look, 1.0)
		map.bind_material_depth_distance(material, block_world_size / load("res://scripts/ember_voxel_solid_surface.gd").AUTHORED_BLOCK_M)


func _bind_map_lighting() -> void:
	var ancestor := get_parent()
	while ancestor != null and not ancestor is EmberMapLoader: ancestor = ancestor.get_parent()
	if ancestor is EmberMapLoader:
		apply_solid_light(ancestor.compact_material_light_mode,ancestor.compact_material_gray_preview)
		apply_voxel_light_settings(ancestor)
	else:
		var visual := get_node_or_null("Mesh") as MeshInstance3D
		if _has_bark(visual): _apply_tree_moss(visual)


func set_world_look(look: int) -> void:
	restore_runtime_shadow_lod()
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or not visual.mesh is ArrayMesh or visual.mesh.get_surface_count() == 0: return
	if visual.mesh.surface_get_name(0)=="tree_bark":_remember_tree_overrides(visual)
	if not _world_look_initialized:
		if not _solid_material_initialized:_published_material = visual.material_override
		_world_look_initialized = true
	_world_look = look
	if look!=0:
		_distance_managed=false;_distance_resident=true;_distance_ready=false
		_distance_mesh=null;_distance_source=null;_distance_flat_mesh=null
	if _distance_managed and not _distance_resident and look==0:
		_set_far_object_detail(visual);return
	if look < 0:
		if _hull_mesh != null: set_solid_look(SOLID_LOOK_LOW_POLY)
		elif not _tree_meshes.is_empty(): visual.mesh = _tree_meshes[0]
		_bind_map_lighting()
		return
	if _set_external_look(look):return
	if _external_active:
		_external_active=false;visual.mesh=_hull_mesh;visual.material_override=null
	if visual.mesh.surface_get_name(0) == "solid_surface" or _hull_mesh != null:
		set_solid_look([SOLID_LOOK_DETAILED, SOLID_LOOK_LOW_POLY, SOLID_LOOK_VOXEL][look])
		return
	if visual.mesh.surface_get_name(0) != "tree_bark": return
	if _tree_meshes.is_empty():
		_tree_meshes[0] = visual.mesh
	if not _distance_managed and _tree_meshes.size()==1 or not _tree_meshes.has(look):
		var source := load("res://content/voxel_models/%s.tres" % model_id) as EmberVoxelModelResource
		if source != null:
			_tree_meshes.merge(load("res://scripts/ember_tree_look_bake.gd").prepare(source, _tree_meshes[0]))
	if not _tree_meshes.has(look): return
	visual.mesh = _tree_meshes[look]
	if look==0 and object_lod_allowed() and _distance_source==_tree_meshes[0] and _distance_mesh!=null:
		visual.mesh=_distance_mesh
	_bind_map_lighting()


func _set_external_look(look:int)->bool:
	if not get_meta("ember_external_source",false) and (authoring_source==null or authoring_source.external_surface.is_empty()):return false
	var source:=_solid_source()
	if source==null or source.external_surface.is_empty():return false
	var external=load("res://scripts/ember_external_mesh_surface.gd")
	# prepared() already validates the full Source fingerprint. Avoid doing
	# that same scan twice when restoring a saved detailed/low-poly carrier.
	var prepared:ArrayMesh=external.prepared(source,look) if look in [0,1] else null
	if (look in [0,1] and prepared==null) or (look==2 and not external.pristine(source)):return false
	var visual:=get_node("Mesh") as MeshInstance3D
	if _hull_mesh==null:_hull_mesh=visual.mesh
	if not _external_meshes.has(look):
		if look==2:
			var solid=load("res://scripts/ember_voxel_solid_surface.gd")
			var model:=EmberVoxelPrefab.model_of(source.to_definition())
			var voxel:ArrayMesh=solid.build_voxel_look(model);solid.apply_materials(voxel,model)
			_external_meshes[look]=voxel
		else:_external_meshes[look]=prepared
	if _external_meshes[look]==null:return false
	visual.mesh=_external_meshes[look];visual.material_override=null
	_external_active=true;_sync_volume_collision(_hull_mesh);_invalidate_floor_faces()
	if look==2:
		_solid_look=SOLID_LOOK_VOXEL;refresh_solid_material()
	set_process(false)
	return true


func _ready() -> void:
	set_notify_transform(true)
	var map:=_owning_map()
	var queued:=map!=null and map.editor_object_detail_enabled()
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if get_meta("ember_solid_source",false) or (mesh != null and mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count()>0 and mesh.mesh.surface_get_name(0)=="solid_surface"):
		_apply_voxel_scale()
		if not queued:refresh_solid_material()
		if has_node("Collision/Shape"):add_to_group(&"ember_solid_surface")
	if not queued and _world_look<0 and get_meta("ember_external_source",false):
		var source:=_solid_source()
		if source!=null and not source.external_surface.is_empty():set_world_look(0)
	if not queued and not moss_mask.is_empty() and _has_bark(mesh): _apply_tree_moss(mesh)
	_sync_water_contact()


func _sync_water_contact() -> void:
	var contact := get_node_or_null("WaterContact") as EmberWaterContact3D
	if not water_contact_enabled:
		if contact != null and contact.get_meta("ember_derived_contact", false):
			remove_child(contact); contact.queue_free()
		return
	if contact == null:
		contact = WaterContact.new()
		contact.name = "WaterContact"
		contact.set_meta("ember_derived_contact", true)
		add_child(contact)
	contact.radius_blocks = water_contact_radius_blocks


func apply_solid_light(mode: int,gray: bool) -> void:
	restore_runtime_shadow_lod()
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh or visual.mesh.get_surface_count()==0 or visual.mesh.surface_get_name(0)!="solid_surface":return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material==null:return
	if material.get_shader_parameter("material_light_mode")==mode and material.get_shader_parameter("material_gray_preview")==gray:return
	material=material.duplicate() as ShaderMaterial
	material.set_shader_parameter("material_light_mode",mode);material.set_shader_parameter("material_gray_preview",gray)
	visual.material_override=material


func refresh_solid_material() -> void:
	restore_runtime_shadow_lod()
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh:return
	if not visual.mesh.has_meta("solid_surface_material_ids"):
			return
	if visual.material_override!=null and not visual.material_override.get_meta("ember_derived_solid_material",false):return
	if not _solid_material_initialized:
		_published_material=visual.material_override
		_solid_material_initialized=true
	var previous:=visual.get_active_material(0) as ShaderMaterial
	var mode:=1;var gray:=false
	if previous!=null:
		var old_mode:Variant=previous.get_shader_parameter("material_light_mode")
		if old_mode is int or old_mode is float:mode=int(old_mode)
		gray=previous.get_shader_parameter("material_gray_preview")==true
	visual.material_override=load("res://scripts/ember_voxel_solid_surface.gd").material_for(visual.mesh,_solid_look==SOLID_LOOK_DETAILED)
	apply_solid_light(mode,gray)
	_sync_solid_unit()
	_sync_solid_depth()
	_bind_map_lighting()


const SOLID_LOOK_LOW_POLY := 0
const SOLID_LOOK_VOXEL := 1
const SOLID_LOOK_DETAILED := 2
var _sun: DirectionalLight3D
var _solid_look := SOLID_LOOK_LOW_POLY
var _hull_mesh: ArrayMesh
var _voxel_mesh: ArrayMesh
var _living_mesh: ArrayMesh
var _volume_shapes: Dictionary = {}
var _published_volume_shape: Shape3D

func install_prepared_looks(meshes:Array[ArrayMesh])->void:
	restore_runtime_shadow_lod()
	_living_mesh=meshes[0];_hull_mesh=meshes[1];_voxel_mesh=meshes[2]
	get_node("Mesh").mesh=_hull_mesh


## Developer look switch for a solid-surface object: 0 = low poly hull (default), 1 = voxel
## cubes of the same Source, 2 = detailed: the hull whose faces drift toward the voxel shape (material
## form_pull_mm) with depth derived from the painted colour.
## Saved transactions compare the published hull, not a derived world look.
func authoring_visual_state() -> Dictionary:
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null: return {}
	if not _tree_meshes.is_empty() and (visual.mesh in _tree_meshes.values() or visual.mesh==_distance_mesh):
		_remember_tree_overrides(visual,true)
		var state:Dictionary={"mesh":_tree_meshes[0],"material_override":_published_material}
		for surface in _tree_authored_overrides.size():state["surface_material_override/%d"%surface]=_tree_authored_overrides[surface]
		return state
	var published:Material=visual.material_override
	if published==null or published.get_meta("ember_derived_solid_material",false):
		if _solid_material_initialized:published=_published_material
	if _hull_mesh != null and (visual.mesh in [_hull_mesh, _voxel_mesh, _living_mesh,_distance_mesh,_distance_flat_mesh] or visual.mesh in _external_meshes.values()):
		return {"mesh":_hull_mesh,"material_override":published}
	# An unknown replacement is an external edit, not a presentation to ignore.
	return {"mesh":visual.mesh,"material_override":published}

## A Canvas Save/Undo installs a new published mesh before restoring its look.
func refresh_authoring_projection() -> void:
	restore_runtime_shadow_lod()
	_distance_mesh=null;_distance_source=null;_distance_flat_mesh=null;_distance_ready=false
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	var solid: bool = _hull_mesh != null or (visual != null and visual.mesh != null and visual.mesh.get_surface_count()>0 and visual.mesh.surface_get_name(0)=="solid_surface")
	if not solid:
		refresh_solid_material()
		return
	_hull_mesh=null;_voxel_mesh=null;_living_mesh=null
	_external_meshes.clear();_external_active=false
	_volume_shapes.clear()
	_published_volume_shape=null
	_solid_look=SOLID_LOOK_LOW_POLY
	_world_look_initialized=false
	_solid_material_initialized=false
	if _world_look>=0: set_world_look(_world_look)
	else: refresh_solid_material()

## Display only: collision, floor and Source stay on the hull.
func set_solid_look(look: int) -> bool:
	restore_runtime_shadow_lod()
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh or look not in [SOLID_LOOK_LOW_POLY,SOLID_LOOK_VOXEL,SOLID_LOOK_DETAILED]:return false
	if _hull_mesh==null:
		if visual.mesh.has_meta("solid_voxel_look") or visual.mesh.has_meta("solid_living_faces") or visual.mesh.surface_get_name(0)!="solid_surface":return false
		_hull_mesh=visual.mesh as ArrayMesh
	if look==SOLID_LOOK_VOXEL and _voxel_mesh==null:
		var resource:=_solid_source()
		if resource==null or resource.solid_surface.is_empty():return false
		var solid=load("res://scripts/ember_voxel_solid_surface.gd")
		var model:=EmberVoxelPrefab.model_of(resource.to_definition())
		_voxel_mesh=solid.build_voxel_look(model)
		if _voxel_mesh.get_surface_count()==0:_voxel_mesh=null;return false
		solid.apply_materials(_voxel_mesh,model)
	if look==SOLID_LOOK_DETAILED and (_living_mesh==null or authoring_source==null):_living_mesh=_living_for(null,"")
	visual.mesh=_voxel_mesh if look==SOLID_LOOK_VOXEL else _living_mesh if look==SOLID_LOOK_DETAILED and _living_mesh!=null else _hull_mesh
	_solid_look=look
	_sync_volume_collision(_hull_mesh)
	refresh_solid_material()
	set_notify_transform(true)
	set_process(look==SOLID_LOOK_DETAILED)
	if not Engine.is_editor_hint():process_priority=1 # Follow the default-priority camera update.
	_sync_solid_depth()
	return true

## The published volume boundary includes carved interiors and owns physics in
## every display look. Switching to voxel cubes must not move the physical edge.
func _sync_volume_collision(mesh: Mesh) -> void:
	if _hull_mesh==null or not _hull_mesh.get_meta("solid_volume_boundary",false):return
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if shape==null or shape.disabled:return
	if _published_volume_shape==null:
		# The authored collider is already installed. Compare its triangles
		# only when asked to replace it with a different physical mesh.
		if mesh==_hull_mesh:return
		# Retain authored collision masks/overrides instead of replacing them
		# with the visible shell. Only the generated full boundary follows looks.
		if not shape.shape is ConcavePolygonShape3D or shape.shape.get_faces()!=_hull_mesh.get_faces():return
		_published_volume_shape=shape.shape
	elif shape.shape!=_published_volume_shape and shape.shape not in _volume_shapes.values():return
	# The published boundary already owns this exact physical surface. A
	# visual detail return must not rebuild an identical trimesh and emit a
	# false surface change to every nearby scatter patch.
	if mesh==_hull_mesh:
		if shape.shape!=_published_volume_shape:
			shape.shape=_published_volume_shape
			_invalidate_floor_faces()
		return
	var key:=mesh.get_instance_id()
	if not _volume_shapes.has(key):_volume_shapes[key]=mesh.create_trimesh_shape()
	if shape.shape==_volume_shapes[key]:return
	shape.shape=_volume_shapes[key]
	_invalidate_floor_faces()

func authoring_collision_shape() -> Shape3D:
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if shape==null:return null
	if _published_volume_shape!=null and shape.shape in _volume_shapes.values():return _published_volume_shape
	return shape.shape


## Hull faces drifted toward the voxel Source by each material's form_pull_mm (null when no material asks
## for it). A draft Pattern replaces the saved one of its own id, so the editor previews before saving.
func _living_for(draft: EmberCompactTerrainPattern,draft_id: String) -> ArrayMesh:
	if _hull_mesh==null or not _hull_mesh.has_meta("solid_surface_material_ids"):return null
	if packed_detail_mesh != null and draft == null and authoring_source == null:
		return packed_detail_mesh
	var solid=load("res://scripts/ember_voxel_solid_surface.gd")
	if _hull_mesh.get_meta("solid_volume_boundary",false):return solid.detailed_volume_from_boundary(_hull_mesh)
	var ids: PackedStringArray=_hull_mesh.get_meta("solid_surface_material_ids")
	var pulls: PackedFloat32Array=solid.living_pulls(ids)
	if draft!=null:
		for slot in ids.size():
			if ids[slot]==draft_id:pulls[slot]=draft.form_pull_mm*0.001
	var resource:=_solid_source()
	if resource==null or resource.solid_surface.is_empty():return null
	var model:=EmberVoxelPrefab.model_of(resource.to_definition(true))
	var mesh:ArrayMesh=solid.living_mesh(model,solid.AUTHORED_BLOCK_M,pulls)
	if mesh.get_surface_count()==0:mesh=_hull_mesh
	if not mesh.has_meta("solid_surface_material_ids"):solid.apply_materials(mesh,model)
	# Hull-face overlays cannot describe an interior surface. Keep the same
	# material/depth renderer, without projecting the old convex face layout.
	return mesh if mesh.get_meta("solid_volume_boundary",false) else load("res://scripts/ember_solid_material_layers.gd").prepared_mesh(mesh,model)

## The exporter calls this on a detached instance of the saved map.
func bake_packed_detail_mesh() -> ArrayMesh:
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or not visual.mesh is ArrayMesh or authoring_source != null or get_meta("ember_external_source", false):
		return null
	var hull := visual.mesh as ArrayMesh
	if hull.get_surface_count() == 0 or hull.surface_get_name(0) != "solid_surface" or not hull.has_meta("solid_surface_material_ids"):
		return null
	if not hull.get_meta("solid_volume_boundary", false):
		var source_path := "res://content/voxel_models/%s.tres" % model_id
		if not ResourceLoader.exists(source_path): return null
		authoring_source = ResourceLoader.load(source_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
		if authoring_source == null: return null
	# An export may follow several saves in the same editor process.
	preload("res://scripts/ember_voxel_solid_surface.gd").clear_living_cache()
	var previous := _hull_mesh
	_hull_mesh = hull
	var result := _living_for(null, "")
	_hull_mesh = previous
	authoring_source = null
	return result


## The editor changed a form pull: swap in the matching faces and rebuild the material (the depth and
## light bindings of the draft are applied by the caller afterwards).
func _sync_living(pattern: EmberCompactTerrainPattern,id: String) -> void:
	if _distance_managed and not _distance_resident:_distance_ready=false
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or _solid_look!=SOLID_LOOK_DETAILED or _hull_mesh==null:return
	var ids: PackedStringArray=_hull_mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	var slots:=PackedInt32Array()
	for slot in ids.size():
		if ids[slot]==id:slots.append(slot)
	if slots.is_empty():return
	var current: PackedFloat32Array=_living_mesh.get_meta("solid_living_pulls",PackedFloat32Array()) if _living_mesh!=null else PackedFloat32Array()
	var wanted:=pattern.form_pull_mm*0.001
	var same:=true
	for slot in slots:
		var have:=current[slot] if slot<current.size() else 0.0
		if not is_equal_approx(have,wanted):same=false
	if same:return
	restore_runtime_shadow_lod()
	_living_mesh=_living_for(pattern,id)
	visual.mesh=_living_mesh if _living_mesh!=null else _hull_mesh
	refresh_solid_material()


func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSFORM_CHANGED:
		restore_runtime_shadow_lod()
		set_runtime_physics_active(true)
		var map:=_owning_map()
		if map!=null:map.invalidate_physics_activity()
		_sync_solid_unit()
		if _solid_look==SOLID_LOOK_DETAILED:_sync_solid_depth(true)
		if is_node_ready():
			_floor_grid.clear()
			_notify_surface_change()
	# Save the published prefab, not a generated presentation override in the map.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		restore_runtime_shadow_lod()
		set_runtime_physics_active(true)
	if what == NOTIFICATION_EDITOR_PRE_SAVE and (_world_look >= 0 or _tree_moss_material != null):
		var visual := get_node_or_null("Mesh") as MeshInstance3D
		if visual != null:
			# Strip our known representations; preserve an unknown authored
			# replacement instead of restoring an obsolete cached mesh over it.
			var authored:=authoring_visual_state()
			for key:String in authored:visual.set(key,authored[key])
			if _hull_mesh != null and visual.mesh==_hull_mesh:_sync_volume_collision(_hull_mesh)
	elif what == NOTIFICATION_EDITOR_POST_SAVE and (_world_look >= 0 or _tree_moss_material != null):
		var map:=_owning_map()
		if map!=null and map.editor_object_detail_enabled():map._queue_object_look(self)
		else:set_world_look.call_deferred(_world_look)


func _process(_delta: float) -> void:
	_sync_solid_depth()


## The depth search runs in world space but reads the height in object space: it needs the inverse of
## the mesh transform and the sun direction (for the depth self-shadow); both follow the object/light.
func _sync_solid_depth(force:=false) -> void:
	if _distance_managed and not _distance_resident and not force:return
	if _solid_look!=SOLID_LOOK_DETAILED:return
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null:return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material==null or not material.get_meta("ember_detailed_depth",false):return
	_sync_depth_program(visual,material)
	material.set_shader_parameter("solid_depth_world_to_local",Projection(visual.global_transform.affine_inverse()))
	load("res://scripts/ember_solid_material_layers.gd").sync_scale(material,visual)
	if _sun==null or not is_instance_valid(_sun):
		var ancestor:=get_parent()
		while ancestor!=null and not ancestor is EmberMapLoader:ancestor=ancestor.get_parent()
		var scope:Node=ancestor if ancestor!=null else get_tree().current_scene
		if scope!=null:_sun=_first_depth_sun(scope)
	if _sun!=null:material.set_shader_parameter("material_depth_sun_direction",_sun.global_transform.basis.z.normalized())


## Conservative whole-object distance: never drop relief on a near side of a large rock.
## Editor/active authoring keeps the original program, including live Pattern previews.
func _sync_depth_program(visual: MeshInstance3D, material: ShaderMaterial) -> void:
	var shader := material.shader
	if shader == null:return
	var full := shader.get_meta("ember_depth_full_shader",shader) as Shader
	var eligible := is_inside_tree() and not Engine.is_editor_hint() and authoring_source == null and (authoring_preview == null or not is_instance_valid(authoring_preview.get_ref()))
	# A morph can move vertices outside the undeformed mesh bounds.
	if material.get_shader_parameter("ember_anomaly_prepared") == true:eligible=false
	var camera := get_viewport().get_camera_3d() if eligible else null
	var far := false
	if camera != null and visual.mesh != null:
		var fade: Variant = material.get_shader_parameter("material_depth_fade_far_m")
		if fade is float or fade is int:
			var bounds := visual.global_transform * visual.get_aabb()
			var nearest := camera.global_position.clamp(bounds.position,bounds.end)
			var margin := block_world_size * (0.5 if shader != full else 2.0)
			far = camera.global_position.distance_to(nearest) > float(fade) + margin
	var target := load("res://scripts/ember_voxel_solid_surface.gd").far_depth_shader(full) as Shader if far else full
	if target != null and material.shader != target:material.shader=target


## Same preorder and owned=false semantics as find_children, but the depth
## material needs only its first light, not an inventory of the entire world.
static func _first_depth_sun(scope: Node) -> DirectionalLight3D:
	for child in scope.get_children(true):
		if child is DirectionalLight3D: return child as DirectionalLight3D
		var light := _first_depth_sun(child)
		if light != null: return light
	return null


func solid_look() -> int:
	return _solid_look


func _sync_solid_unit() -> void:
	# Object-local pattern coordinates are model units; the pattern size is in metres.
	if not is_inside_tree():return
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null:return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material!=null and material.get_meta("ember_derived_solid_material",false):
		var solid=load("res://scripts/ember_voxel_solid_surface.gd")
		var units_per_metre:float = block_world_size/solid.AUTHORED_BLOCK_M
		bind_pattern_size(material)
		# One authored block is one metre whatever the world draws it as; the depth search runs in world units.
		if int(material.get_shader_parameter("solid_projection_mode"))==1:material.set_shader_parameter("solid_local_unit_m",solid.AUTHORED_BLOCK_M)
		solid.set_world_scale(material,units_per_metre)
		var ancestor := get_parent()
		while ancestor != null and not ancestor is EmberMapLoader: ancestor = ancestor.get_parent()
		if ancestor is EmberMapLoader: ancestor.bind_material_depth_distance(material,units_per_metre)


## The sphere's copied materials use this same instance-owned size, including
## alternate voxel carriers. Binding parameters never rebuilds their geometry.
func bind_pattern_size(material:ShaderMaterial)->void:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if material==null or visual==null or not visual.is_inside_tree():return
	var unit:float=block_world_size/load("res://scripts/ember_voxel_solid_surface.gd").AUTHORED_BLOCK_M
	material.set_shader_parameter("solid_pattern_scale",material_pattern_scale)
	material.set_shader_parameter("solid_texture_unit_m",visual.global_basis.get_scale().abs()/unit)
	material.set_shader_parameter("ember_texture_world_unit",unit*material_pattern_scale)
	if not moss_mask.is_empty(): _bind_moss(material)


func moss_paint_bounds() -> AABB:
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or visual.mesh == null or visual.mesh.get_surface_count() == 0:
		return AABB()
	var material := visual.get_active_material(0) as ShaderMaterial
	if material == null: return AABB()
	if _has_bark(visual):
		if visual.material_override != null or not _is_moss_bark_material(material): return AABB()
		var source := _tree_meshes.get(0, visual.mesh) as Mesh
		if source != _moss_bark_source:
			_moss_bark_source = source
			var vertices: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			_moss_bark_bounds = AABB()
			if not vertices.is_empty():
				_moss_bark_bounds.position = vertices[0]
				for vertex in vertices: _moss_bark_bounds = _moss_bark_bounds.expand(vertex)
		return _moss_bark_bounds
	if not material.get_meta("ember_derived_solid_material", false): return AABB()
	var authored := authoring_visual_state().get("mesh") as Mesh
	return authored.get_aabb() if authored != null else AABB()


func _has_bark(visual: MeshInstance3D) -> bool:
	return visual != null and visual.mesh != null and visual.mesh.get_surface_count() > 0 and visual.mesh.surface_get_name(0) == "tree_bark"


func _is_moss_bark_material(material: ShaderMaterial) -> bool:
	return material != null and material.shader != null and material.shader.resource_path == "res://shaders/ember_tree_bark.gdshader"


func _apply_tree_moss(visual: MeshInstance3D) -> void:
	if moss_mask.is_empty():
		if _tree_moss_material != null:
			if visual.get_surface_override_material(0) == _tree_moss_material:
				visual.set_surface_override_material(0, _tree_moss_base_override)
			_tree_moss_material = null
			_tree_moss_base_override = null
			_refresh_moss_tufts(AABB())
		return
	var active := visual.get_active_material(0) as ShaderMaterial
	if visual.material_override != null or not _is_moss_bark_material(active): return
	if active != _tree_moss_material:
		if _tree_meshes.is_empty():
			_tree_meshes[0] = visual.mesh
			_published_material = visual.material_override
		_remember_tree_overrides(visual)
		var base_override := visual.get_surface_override_material(0)
		if _tree_moss_material == null or base_override == null or base_override != _tree_moss_base_override:
			_tree_moss_base_override = base_override
			_tree_moss_material = active.duplicate() as ShaderMaterial
			_tree_moss_material.set_meta("ember_derived_tree_material", true)
		visual.set_surface_override_material(0, _tree_moss_material)
	_bind_moss(_tree_moss_material)


func moss_surface_hit(first: Vector3, last: Vector3, physics_hit: Dictionary) -> Dictionary:
	var visual := get_node("Mesh") as MeshInstance3D
	if not _has_bark(visual): return physics_hit
	if _moss_pick_source != visual.mesh:
		_moss_pick_source = visual.mesh
		_moss_pick_triangles = TriangleMesh.new()
		if not _moss_pick_triangles.create_from_faces(ObjectMoss.bark_faces(visual.mesh)):
			_moss_pick_triangles = null
	if _moss_pick_triangles == null: return {}
	var hit := _moss_pick_triangles.intersect_segment(visual.to_local(first), visual.to_local(last))
	if hit.is_empty(): return {}
	hit.position = visual.to_global(hit.position)
	hit.normal = (visual.global_basis.inverse().transposed() * hit.normal).normalized()
	return hit


func _bind_moss(material: ShaderMaterial) -> void:
	if material == null or (not material.get_meta("ember_derived_solid_material", false) and not _is_moss_bark_material(material)):
		return
	var bounds := moss_paint_bounds() if not moss_mask.is_empty() else AABB()
	if bounds.has_volume() and _moss_texture == null:
		_moss_texture = ObjectMoss.texture(moss_mask)
	material.set_shader_parameter("object_moss_enabled", _moss_texture != null and bounds.has_volume())
	material.set_shader_parameter("object_moss_mask", _moss_texture)
	if bounds.has_volume():
		material.set_shader_parameter("object_moss_origin", bounds.position)
		material.set_shader_parameter("object_moss_extent", bounds.size)
		var dark := ObjectMoss.preset.shadow_color.srgb_to_linear()
		var light := ObjectMoss.preset.light_color.srgb_to_linear()
		material.set_shader_parameter("object_moss_shadow", Vector3(dark.r, dark.g, dark.b))
		material.set_shader_parameter("object_moss_light", Vector3(light.r, light.g, light.b))
		add_to_group(ObjectMoss.PAINTED_GROUP)
	_refresh_moss_tufts(bounds)


func preview_moss_details(detail: Vector3) -> void:
	_moss_preview = detail
	if not moss_mask.is_empty(): _refresh_moss_tufts(moss_paint_bounds())


func _refresh_moss_tufts(bounds: AABB) -> void:
	if not bounds.has_volume():
		if is_instance_valid(_moss_tufts):
			_moss_tufts.free()
			_moss_tufts = null
		return
	var visual := get_node("Mesh") as MeshInstance3D
	var detail := _moss_preview if _moss_preview.x > 0.0 else ObjectMoss.saved_detail()
	if visual.mesh == _moss_tuft_source and detail == _moss_tuft_detail: return
	_moss_tuft_source = visual.mesh
	_moss_tuft_detail = detail
	var tuft_mesh := ObjectMoss.tuft_mesh(visual.mesh, bounds, moss_mask, detail, _has_bark(visual))
	if tuft_mesh == null and _moss_tufts == null: return
	if _moss_tufts == null:
		_moss_tufts = MeshInstance3D.new()
		_moss_tufts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moss_tufts.visibility_range_end = 12.0 * block_world_size
		_moss_tufts.visibility_range_end_margin = 3.0 * block_world_size
		_moss_tufts.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		visual.add_child(_moss_tufts, false, Node.INTERNAL_MODE_BACK)
	_moss_tufts.mesh = tuft_mesh


func preview_solid_material_light(pattern: EmberCompactTerrainPattern,id: String) -> void:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or visual.mesh==null:return
	_sync_living(pattern,id)
	var ids: PackedStringArray=visual.mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	var material:=visual.get_active_material(0) as ShaderMaterial
	var materials=load("res://scripts/ember_voxel_surface_materials.gd")
	for slot in ids.size():
		if ids[slot]==id:
			materials.update_grass_light_profile(material,slot,pattern)
			materials.update_style_rim_profile(material,slot,pattern)
	if _solid_look==SOLID_LOOK_DETAILED:load("res://scripts/ember_voxel_solid_surface.gd").update_detail(material,visual.mesh as ArrayMesh,pattern,id)
	if _solid_look==SOLID_LOOK_DETAILED:load("res://scripts/ember_solid_material_layers.gd").update(material,visual.mesh as ArrayMesh,pattern,id)


func _invalidate_floor_faces() -> void:
	restore_runtime_shadow_lod()
	set_runtime_physics_active(true)
	var map:=_owning_map()
	if map!=null:map.invalidate_physics_activity()
	_floor_faces=PackedVector3Array()
	_floor_data_ready=false
	_floor_grid.clear()
	_floor_bin_bounds=PackedInt32Array()
	_floor_revision+=1
	_notify_surface_change()

func _exit_tree()->void:
	packed_detail_path = ""
	packed_detail_mesh = null
	packed_detail_wanted = false
	restore_runtime_shadow_lod()
	set_runtime_physics_active(true)
	_notify_surface_change()

func _notify_surface_change()->void:
	if not is_inside_tree():return
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or visual.mesh==null:return
	# Children may already have left the tree during the parent's exit.
	var bounds:AABB=visual.global_transform*(_hull_mesh if _hull_mesh!=null else visual.mesh).get_aabb() if visual.is_inside_tree() else _surface_change_bounds
	var changed:=bounds.merge(_surface_change_bounds) if _surface_change_bounds.has_volume() else bounds
	_surface_change_bounds=bounds
	var ancestor:=get_parent()
	while ancestor!=null and not ancestor is EmberMapLoader:ancestor=ancestor.get_parent()
	if ancestor is EmberMapLoader:ancestor.surface_object_changed.emit(changed)

## Local physical data also supplies the stable scatter signature. Computing
## that signature must not eagerly build a world-space query index per prop.
func _prepare_floor_data(physical:Mesh,shape:Shape3D)->void:
	if _floor_mesh!=physical or _floor_shape!=shape:
		if _floor_mesh!=null and _floor_mesh.changed.is_connected(_invalidate_floor_faces):_floor_mesh.changed.disconnect(_invalidate_floor_faces)
		if is_instance_valid(_floor_shape) and _floor_shape.changed.is_connected(_invalidate_floor_faces):_floor_shape.changed.disconnect(_invalidate_floor_faces)
		_floor_mesh=physical;_floor_shape=shape;_floor_faces=PackedVector3Array();_floor_grid.clear();_floor_bin_bounds=PackedInt32Array();_floor_data_ready=false
		_floor_mesh.changed.connect(_invalidate_floor_faces)
		if _floor_shape!=null:_floor_shape.changed.connect(_invalidate_floor_faces)
	if _floor_data_ready:return
	var canonical:=physical.get_faces()
	_floor_faces=shape.get_faces() if _hull_mesh!=null and _hull_mesh.get_meta("solid_volume_boundary",false) and shape is ConcavePolygonShape3D else canonical
	_floor_slots=PackedByteArray();_floor_slots.resize(_floor_faces.size()/3)
	_floor_roles=physical.get_meta("solid_surface_roles",PackedStringArray())
	if _floor_faces==canonical and physical.get_surface_count()==1:
		var arrays:=physical.surface_get_arrays(0)
		var colours:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		for t in _floor_slots.size():
			var at:int=indices[t*3] if not indices.is_empty() else t*3
			if at<colours.size():_floor_slots[t]=clampi(roundi(colours[at].a*255),0,255)
	_floor_stamp=hash([_floor_faces,_floor_slots,_floor_roles])
	_floor_data_ready=true

## Transient XZ bins over the same physical triangles. Only real floor queries
## need this acceleration structure; it remains separate from saved data.
func _prepare_floor(visual:MeshInstance3D,physical:Mesh,shape:Shape3D)->void:
	_prepare_floor_data(physical,shape)
	var cell_size:=maxf(block_world_size*0.25,0.001)
	if _floor_world_transform!=visual.global_transform or _floor_cell_size!=cell_size:
		_floor_grid.clear();_floor_bin_bounds=PackedInt32Array();_floor_world_transform=visual.global_transform;_floor_cell_size=cell_size

func _floor_bin(key:Vector2i,cell_size:float)->PackedInt32Array:
	if _floor_grid.has(key):return _floor_grid[key]
	var candidates:=PackedInt32Array()
	# Large flat triangles used to insert themselves into thousands of bins
	# before the first root query. Cache only the cells actually sampled, using
	# the same inclusive triangle bounds and triangle order as the full index.
	if _floor_bin_bounds.is_empty():
		var frame:=_floor_world_transform
		_floor_bin_bounds.resize((_floor_faces.size()/3)*4)
		for i in range(0,_floor_faces.size(),3):
			var a:Vector3=frame*_floor_faces[i];var b:Vector3=frame*_floor_faces[i+1];var c:Vector3=frame*_floor_faces[i+2]
			var low:=a.min(b).min(c)/cell_size;var high:=a.max(b).max(c)/cell_size
			var at:int=(i/3)*4
			_floor_bin_bounds[at]=floori(low.x);_floor_bin_bounds[at+1]=floori(low.z)
			_floor_bin_bounds[at+2]=floori(high.x);_floor_bin_bounds[at+3]=floori(high.z)
	for at in range(0,_floor_bin_bounds.size(),4):
		if key.x>=_floor_bin_bounds[at] and key.x<=_floor_bin_bounds[at+2] and key.y>=_floor_bin_bounds[at+1] and key.y<=_floor_bin_bounds[at+3]:candidates.append((at/4)*3)
	_floor_grid[key]=candidates
	return candidates

func detail_surface_signature()->Array:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if visual==null or visual.mesh==null or shape==null or shape.shape==null:return []
	var physical:Mesh=_hull_mesh if _hull_mesh!=null else visual.mesh
	_prepare_floor_data(physical,shape.shape)
	return [model_id,_floor_stamp,visual.global_transform,shape.disabled,get_node("Collision").collision_layer]


func surface_floor_bounds() -> AABB:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or visual.mesh==null:return AABB()
	var physical:Mesh=_hull_mesh if _hull_mesh!=null else _tree_meshes[0] if not _tree_meshes.is_empty() else visual.mesh
	return visual.global_transform*physical.get_aabb()

func surface_floor_sample(point: Vector3) -> Dictionary:
	if authoring_preview!=null and is_instance_valid(authoring_preview.get_ref()):return authoring_preview.get_ref().surface_floor_sample(point)
	# Query the same transformed triangles as Collision/Shape; no rounded
	# height approximation or additional serialized floor data.
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	var body:=get_node_or_null("Collision") as StaticBody3D
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if visual==null or visual.mesh==null or body==null or (body.collision_layer & 1)==0 or shape==null or shape.disabled or shape.shape==null:return {"solid":false}
	# The floor is the physical hull, never a display look (voxel cubes, living faces) shown on top of it.
	var physical: Mesh=_hull_mesh if _hull_mesh!=null else _tree_meshes[0] if not _tree_meshes.is_empty() else visual.mesh
	var bounds: AABB=visual.global_transform*physical.get_aabb()
	if point.x<bounds.position.x or point.z<bounds.position.z or point.x>bounds.end.x or point.z>bounds.end.z:return {"solid":false}
	var start := visual.to_local(Vector3(point.x,bounds.end.y+block_world_size,point.z))
	var finish := visual.to_local(Vector3(point.x,bounds.position.y-block_world_size,point.z))
	var direction := (finish-start).normalized()
	var best := -INF; var normal := Vector3.UP
	_prepare_floor(visual,physical,shape.shape)
	var faces := _floor_faces
	var best_slot:=0
	var cell_size:=maxf(block_world_size*0.25,0.001)
	for i:int in _floor_bin(Vector2i(floori(point.x/cell_size),floori(point.z/cell_size)),cell_size):
		var hit: Variant=Geometry3D.ray_intersects_triangle(start,direction,faces[i],faces[i+1],faces[i+2])
		if hit==null:continue
		var world := visual.to_global(hit)
		if world.y>best:
			best=world.y
			best_slot=_floor_slots[i/3]
			normal=visual.global_basis.inverse().transposed()*((faces[i+2]-faces[i]).cross(faces[i+1]-faces[i])).normalized()
	if best==-INF:return {"solid":false}
	var role:String=_floor_roles[best_slot] if best_slot<_floor_roles.size() and not _floor_roles[best_slot].is_empty() else "stone"
	return {"solid":true,"position":Vector3(point.x,best,point.z),"normal":normal.normalized(),"material_role":role,"palette_index":best_slot,"object":self}


func configure_voxel_scale(density: int, world_size: float) -> void:
	voxels_per_block = 32 if density == 32 else 16
	block_world_size = maxf(0.01, world_size)
	_apply_voxel_scale()


func _apply_voxel_scale() -> void:
	restore_runtime_shadow_lod()
	for child_name in ["Mesh", "ShadowBody"]:
		var visual := get_node_or_null(child_name) as MeshInstance3D
		if visual:
			_apply_scaled_node(visual)
	var shape := get_node_or_null("Collision/Shape") as CollisionShape3D
	if shape:
		_apply_scaled_node(shape)
	_sync_solid_unit()
	var omni := get_node_or_null("Omni") as OmniLight3D
	if omni:
		_apply_scaled_node(omni)
		var range_blocks := float(omni.get_meta("ember_range_blocks", 0.0))
		if range_blocks > 0.0:
			omni.omni_range = range_blocks * block_world_size


func _apply_scaled_node(node: Node3D) -> void:
	var base_position: Vector3 = node.get_meta("ember_block_position", node.position / maxf(0.01, block_world_size))
	node.set_meta("ember_block_position", base_position)
	node.position = base_position * block_world_size
	node.scale = Vector3.ONE * block_world_size
