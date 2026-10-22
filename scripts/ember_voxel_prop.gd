@tool
class_name EmberVoxelProp
extends Node3D
## Instance of a voxel PackedScene on an authored map.

const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")

@export var model_id := ""
@export var placement_id := ""
@export_storage var voxels_per_block := 16
@export_storage var block_world_size := 16.0
@export_group("Вода")
@export var water_contact_enabled := false
@export_range(0.05, 1.5, 0.01) var water_contact_radius_blocks := 0.30
@export_group("")
var _floor_mesh: Mesh
var _floor_faces:=PackedVector3Array()
var _floor_revision:=0


func _ready() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if get_meta("ember_solid_source",false) or (mesh != null and mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count()>0 and mesh.mesh.surface_get_name(0)=="solid_surface"):
		_apply_voxel_scale()
		refresh_solid_material()
		if has_node("Collision/Shape"):add_to_group(&"ember_solid_surface")
		var ancestor:=get_parent()
		while ancestor!=null:
			if ancestor is EmberMapLoader:
				apply_solid_light(ancestor.compact_material_light_mode,ancestor.compact_material_gray_preview);break
			ancestor=ancestor.get_parent()
	if Engine.is_editor_hint() or not water_contact_enabled:
		return
	var contact: Node3D = WaterContact.new()
	contact.name = "WaterContact"
	contact.set("radius_blocks", water_contact_radius_blocks)
	add_child(contact)


func apply_solid_light(mode: int,gray: bool) -> void:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh or visual.mesh.get_surface_count()==0 or visual.mesh.surface_get_name(0)!="solid_surface":return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material==null:return
	if material.get_shader_parameter("material_light_mode")==mode and material.get_shader_parameter("material_gray_preview")==gray:return
	material=material.duplicate() as ShaderMaterial
	material.set_shader_parameter("material_light_mode",mode);material.set_shader_parameter("material_gray_preview",gray)
	visual.material_override=material


func refresh_solid_material() -> void:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh:return
	if not visual.mesh.has_meta("solid_surface_material_ids"):
			return
	if visual.material_override!=null and not visual.material_override.get_meta("ember_derived_solid_material",false):return
	var previous:=visual.get_active_material(0) as ShaderMaterial
	var mode:=int(previous.get_shader_parameter("material_light_mode"));var gray:=bool(previous.get_shader_parameter("material_gray_preview"))
	visual.material_override=load("res://scripts/ember_voxel_solid_surface.gd").material_for(visual.mesh,_solid_look==SOLID_LOOK_DETAILED)
	apply_solid_light(mode,gray)
	_sync_solid_unit()
	_sync_solid_depth()


const SOLID_LOOK_LOW_POLY := 0
const SOLID_LOOK_VOXEL := 1
const SOLID_LOOK_DETAILED := 2
var _sun: DirectionalLight3D
var _solid_look := SOLID_LOOK_LOW_POLY
var _hull_mesh: ArrayMesh
var _voxel_mesh: ArrayMesh
var _living_mesh: ArrayMesh


## Developer look switch for a solid-surface object: 0 = low poly hull (default), 1 = voxel
## cubes of the same Source, 2 = detailed: the hull whose faces drift toward the voxel shape (material
## form_pull_mm) with depth derived from the painted colour.
## Display only: collision, floor and Source stay on the hull.
func set_solid_look(look: int) -> bool:
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or not visual.mesh is ArrayMesh or look not in [SOLID_LOOK_LOW_POLY,SOLID_LOOK_VOXEL,SOLID_LOOK_DETAILED]:return false
	if _hull_mesh==null:
		if visual.mesh.has_meta("solid_voxel_look") or visual.mesh.has_meta("solid_living_faces") or visual.mesh.surface_get_name(0)!="solid_surface":return false
		_hull_mesh=visual.mesh as ArrayMesh
	if look==SOLID_LOOK_VOXEL and _voxel_mesh==null:
		var resource:=load("res://content/voxel_models/%s.tres"%model_id) as EmberVoxelModelResource
		if resource==null or resource.solid_surface.is_empty():return false
		var solid=load("res://scripts/ember_voxel_solid_surface.gd")
		var model:=EmberVoxelPrefab.model_of(resource.to_definition())
		_voxel_mesh=solid.build_voxel_look(model)
		if _voxel_mesh.get_surface_count()==0:_voxel_mesh=null;return false
		solid.apply_materials(_voxel_mesh,model)
	if look==SOLID_LOOK_DETAILED:_living_mesh=_living_for(null,"")
	visual.mesh=_voxel_mesh if look==SOLID_LOOK_VOXEL else _living_mesh if look==SOLID_LOOK_DETAILED and _living_mesh!=null else _hull_mesh
	_solid_look=look
	refresh_solid_material()
	set_notify_transform(look==SOLID_LOOK_DETAILED)
	set_process(look==SOLID_LOOK_DETAILED)
	_sync_solid_depth()
	return true


## Hull faces drifted toward the voxel Source by each material's form_pull_mm (null when no material asks
## for it). A draft Pattern replaces the saved one of its own id, so the editor previews before saving.
func _living_for(draft: EmberCompactTerrainPattern,draft_id: String) -> ArrayMesh:
	if _hull_mesh==null or not _hull_mesh.has_meta("solid_surface_material_ids"):return null
	var solid=load("res://scripts/ember_voxel_solid_surface.gd")
	var ids: PackedStringArray=_hull_mesh.get_meta("solid_surface_material_ids")
	var pulls: PackedFloat32Array=solid.living_pulls(ids)
	if draft!=null:
		for slot in ids.size():
			if ids[slot]==draft_id:pulls[slot]=draft.form_pull_mm*0.001
	var resource:=load("res://content/voxel_models/%s.tres"%model_id) as EmberVoxelModelResource
	if resource==null or resource.solid_surface.is_empty():return null
	var model:=EmberVoxelPrefab.model_of(resource.to_definition())
	var mesh:ArrayMesh=solid.living_mesh(model,solid.AUTHORED_BLOCK_M,pulls)
	if mesh.get_surface_count()==0:return null
	if not mesh.has_meta("solid_surface_material_ids"):solid.apply_materials(mesh,model)
	return mesh


## The editor changed a form pull: swap in the matching faces and rebuild the material (the depth and
## light bindings of the draft are applied by the caller afterwards).
func _sync_living(pattern: EmberCompactTerrainPattern,id: String) -> void:
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
	_living_mesh=_living_for(pattern,id)
	visual.mesh=_living_mesh if _living_mesh!=null else _hull_mesh
	refresh_solid_material()


func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and _solid_look==SOLID_LOOK_DETAILED:_sync_solid_depth()


func _process(_delta: float) -> void:
	_sync_solid_depth()


## The depth search runs in world space but reads the height in object space: it needs the inverse of
## the mesh transform and the sun direction (for the depth self-shadow); both follow the object/light.
func _sync_solid_depth() -> void:
	if _solid_look!=SOLID_LOOK_DETAILED:return
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null:return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material==null or not material.get_meta("ember_detailed_depth",false):return
	material.set_shader_parameter("solid_depth_world_to_local",Projection(visual.global_transform.affine_inverse()))
	if _sun==null or not is_instance_valid(_sun):
		var ancestor:=get_parent()
		while ancestor!=null and not ancestor is EmberMapLoader:ancestor=ancestor.get_parent()
		var scope:Node=ancestor if ancestor!=null else get_tree().current_scene
		if scope!=null:
			var lights:=scope.find_children("*","DirectionalLight3D",true,false)
			if not lights.is_empty():_sun=lights[0] as DirectionalLight3D
	if _sun!=null:material.set_shader_parameter("material_depth_sun_direction",_sun.global_transform.basis.z.normalized())


func solid_look() -> int:
	return _solid_look


func _sync_solid_unit() -> void:
	# Object-local pattern coordinates are model units; the pattern size is in metres.
	var visual:=get_node_or_null("Mesh") as MeshInstance3D
	if visual==null:return
	var material:=visual.get_active_material(0) as ShaderMaterial
	if material!=null and material.get_meta("ember_derived_solid_material",false):
		var solid=load("res://scripts/ember_voxel_solid_surface.gd")
		# One authored block is one metre whatever the world draws it as; the depth search runs in world units.
		if int(material.get_shader_parameter("solid_projection_mode"))==1:material.set_shader_parameter("solid_local_unit_m",solid.AUTHORED_BLOCK_M)
		solid.set_world_scale(material,block_world_size/solid.AUTHORED_BLOCK_M)


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


func _invalidate_floor_faces() -> void:
	_floor_faces=PackedVector3Array()
	_floor_revision+=1


func surface_floor_sample(point: Vector3) -> Dictionary:
	# Query the same transformed triangles as Collision/Shape; no rounded
	# height approximation or additional serialized floor data.
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	var body:=get_node_or_null("Collision") as StaticBody3D
	var shape:=get_node_or_null("Collision/Shape") as CollisionShape3D
	if visual==null or visual.mesh==null or body==null or (body.collision_layer & 1)==0 or shape==null or shape.disabled or shape.shape==null:return {"solid":false}
	# The floor is the physical hull, never a display look (voxel cubes, living faces) shown on top of it.
	var physical: Mesh=_hull_mesh if _hull_mesh!=null else visual.mesh
	var bounds: AABB=visual.global_transform*physical.get_aabb()
	if point.x<bounds.position.x or point.z<bounds.position.z or point.x>bounds.end.x or point.z>bounds.end.z:return {"solid":false}
	var start := visual.to_local(Vector3(point.x,bounds.end.y+block_world_size,point.z))
	var finish := visual.to_local(Vector3(point.x,bounds.position.y-block_world_size,point.z))
	var direction := (finish-start).normalized()
	var best := -INF; var normal := Vector3.UP
	if _floor_mesh!=physical:
		if _floor_mesh!=null and _floor_mesh.changed.is_connected(_invalidate_floor_faces):_floor_mesh.changed.disconnect(_invalidate_floor_faces)
		_floor_mesh=physical;_floor_faces=PackedVector3Array();_floor_mesh.changed.connect(_invalidate_floor_faces)
	if _floor_faces.is_empty():_floor_faces=physical.get_faces()
	var faces := _floor_faces
	for i in range(0,faces.size(),3):
		var hit: Variant=Geometry3D.ray_intersects_triangle(start,direction,faces[i],faces[i+1],faces[i+2])
		if hit==null:continue
		var world := visual.to_global(hit)
		if world.y>best:
			best=world.y
			normal=visual.global_basis.inverse().transposed()*((faces[i+2]-faces[i]).cross(faces[i+1]-faces[i])).normalized()
	if best==-INF:return {"solid":false}
	return {"solid":true,"position":Vector3(point.x,best,point.z),"normal":normal.normalized(),"material_role":"stone","object":self}


func configure_voxel_scale(density: int, world_size: float) -> void:
	voxels_per_block = 32 if density == 32 else 16
	block_world_size = maxf(0.01, world_size)
	_apply_voxel_scale()


func _apply_voxel_scale() -> void:
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
