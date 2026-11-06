extends RefCounted
## Authored solid parts of the canonical voxel Source. Unedited guides fit
## convex hulls; a carved occupancy keeps its full concave volume boundary.
## The returned triangles also own collision, picking and floor queries.
const CONTRACT := "voxel-solid-surface-v4-silhouette-frame-stable-buffers"
const VOLUME_CONTRACT := "solid-edited-volume-v3-surface-paint-weights"
const PART_PALETTE_CONTRACT := "solid-part-palette-v1"
## Material look applied to solid-surface meshes that carry form normals (CUSTOM0).
## 0.35 keeps steep bevels from streaking while staying continuous across edges.
const FACET_PROJECTION_BIAS := 0.35
## Narrow, crisp rim band (facing range) chosen on the ordinary rock; other surfaces keep 0.10..0.32.
## The rim is a thin frame along the silhouette (convex edges whose far side faces away from the
## camera); the facing band is therefore left open and the frame width is a material setting
## (style_rim_width_mm). Other surfaces keep the shared 0.10..0.32 band.
const FORM_RIM_EDGE := Vector2(0.95, 1.0)

static func occupancy_hash(voxels: PackedByteArray) -> String:
	var occupied:=voxels.duplicate()
	for index in occupied.size():occupied[index]=mini(occupied[index],1)
	return occupied.hex_encode().sha256_text()

static func active(model: Dictionary) -> bool:
	if model.get("solidSurface", {}).is_empty():return false
	var voxels:=VoxMesher.model_channel(model,"voxels")
	var ids:=PackedInt32Array(model.get("voxelPartIds",[]))
	if ids.size()!=voxels.size():return false
	# Part zero is the editor's legitimate "Added" selection. Volume surfaces
	# read material slots from voxels and need no convex guide for those cells.
	for index in voxels.size():
		if voxels[index]>0 and (ids[index]<0 or ids[index]>model.solidSurface.parts.size()):return false
	return true

## The saved guide reference describes the generated hull. A changed occupancy
## has its own concave boundary; never fit a convex hull across a carved cavity.
## A composed union has no single hull reference and records its volume topology
## in this same profile. Legacy/uncarved sources need no migration.
static func uses_volume(model: Dictionary) -> bool:
	if model.get("solidSurface",{}).is_empty():return false
	var voxels:=VoxMesher.model_channel(model,"voxels")
	if model.solidSurface.get("topology","hull")=="volume" or occupancy_hash(voxels)!=model.solidSurface.get("occupancy",""):return true
	var ids:=PackedInt32Array(model.get("voxelPartIds",[]))
	if ids.size()==voxels.size():
		for index in voxels.size():
			if voxels[index]>0 and ids[index]==0:return true
	return false

## Grab preserves guides on uncarved objects, and the volume boundary on carved
## ones. Unknown ownership still takes the protective ordinary voxel path.
static func grab_profile(source: EmberVoxelModelResource, voxels: PackedByteArray, owners: PackedInt32Array) -> Dictionary:
	if source.solid_surface.is_empty(): return {}
	var previous := source.voxels
	var previous_owners := source.voxel_part_ids
	if previous_owners.size()!=previous.size(): return {}
	if voxels.size()!=previous.size() or owners.size()!=voxels.size():
		return {"error":"Тянуть: не удалось сохранить части объёма. Жест не применён."}
	var before_occupancy := previous.duplicate()
	var after_occupancy := voxels.duplicate()
	var seen := PackedByteArray();seen.resize(source.merge_parts.size()+1)
	var baseline_valid := true
	var owners_valid := true
	for i in previous.size():
		before_occupancy[i]=mini(previous[i],1)
		after_occupancy[i]=mini(voxels[i],1)
		if previous[i]>0:
			var owner := previous_owners[i]
			if owner<1 or owner>=seen.size(): baseline_valid=false
			else: seen[owner] |= 1
		if voxels[i]>0:
			var owner := owners[i]
			if owner<1 or owner>=seen.size(): owners_valid=false
			else: seen[owner] |= 2
	if not baseline_valid: return {}
	if not owners_valid:
		return {"error":"Тянуть: новый объём потерял принадлежность к частям. Жест не применён."}
	for owner in range(1,seen.size()):
		if seen[owner]==1:
			return {"error":"Тянуть: исчезает целая часть объекта. Уменьшите силу жеста."}
	var profile := source.solid_surface.duplicate(true)
	if before_occupancy.hex_encode().sha256_text()==source.solid_surface.get("occupancy",""):
		profile.occupancy=after_occupancy.hex_encode().sha256_text()
	return {"profile":profile}

static func validation_errors(data: Dictionary, part_count: int, palette_count: int) -> Array[String]:
	var errors: Array[String] = []
	if data.is_empty(): return errors
	if data.get("version") != 1 or not data.get("parts") is Array:
		return ["invalid solid surface version/parts"]
	if data.get("topology","hull") not in ["hull","volume"]:errors.append("invalid solid surface topology")
	if data.has("building_offset"):
		var offset: Variant = data.building_offset
		if not offset is Vector3 or not offset.is_finite() or offset.y != 0.0 or offset.length() > 12.0:
			errors.append("invalid building placement offset")
	if data.has("building_entry"):
		var entry:Variant=data.building_entry
		if not entry is Dictionary or not entry.get("point") is Vector3 or not entry.get("normal") is Vector3:
			errors.append("invalid prepared building entry")
		elif not entry.point.is_finite() or entry.point.length()>8192 or not entry.normal in [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT]:errors.append("invalid prepared building entry frame")
	if data.parts.size() != part_count or part_count < 1 or part_count > 32:
		errors.append("solid surface requires one guide per merge part (1..32)")
	if not data.get("occupancy") is String or str(data.get("occupancy","")).length()!=64 or not str(data.get("occupancy","")).is_valid_hex_number():errors.append("invalid solid surface occupancy reference")
	for directions in data.parts:
		if not directions is PackedVector3Array or directions.size() < 6 or directions.size() > 32:
			errors.append("solid surface requires 6..32 plane directions"); continue
		for direction: Vector3 in directions:
			if not direction.is_finite() or absf(direction.length() - 1.0) > 0.00001:
				errors.append("invalid solid surface plane direction"); break
		for axis: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
			var support:=-INF
			for direction: Vector3 in directions:support=maxf(support,direction.dot(axis))
			if support<0.25:errors.append("solid surface guides must enclose all six directions");break
	for key in ["roles", "material_ids"]:
		if not data.get(key) is PackedStringArray or data[key].size() != palette_count:
			errors.append("solid surface " + key + " must match palette")
	return errors

static func part_points(model: Dictionary) -> Array[PackedVector3Array]:
	var size := VoxMesher.ember_grid_size(model)
	var voxels := VoxMesher.model_channel(model, "voxels")
	var ids := PackedInt32Array(model.get("voxelPartIds", []))
	var columns: Array[Dictionary] = []
	var result: Array[PackedVector3Array] = []
	for _part in model.solidSurface.parts:
		columns.append({}); result.append(PackedVector3Array())
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var index := VoxMesher.cell_index(x,y,z,size.x,size.z)
				if voxels[index] == 0 or ids[index] < 1: continue
				var part := ids[index] - 1
				var key := Vector2i(x,z)
				var extent: Vector2i = columns[part].get(key,Vector2i(size.y,0))
				columns[part][key] = Vector2i(mini(extent.x,y),maxi(extent.y,y+1))
	for part in columns.size():
		for key: Vector2i in columns[part]:
			var extent: Vector2i = columns[part][key]
			for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
				result[part].append(Vector3(key.x+offset.x,extent.y,key.y+offset.y))
				result[part].append(Vector3(key.x+offset.x,extent.x,key.y+offset.y))
	return result

static func corners_of(planes: Array[Plane]) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in Geometry3D.compute_convex_mesh_points(planes):
		var found := false
		for other in result:
			if point.distance_squared_to(other) < 0.000001: found = true; break
		if not found: result.append(point)
	return result

static func face_of(corners: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var face := PackedVector3Array(); var centre := Vector3.ZERO
	for point in corners:
		if absf(plane.distance_to(point)) < 0.003: face.append(point); centre += point
	if face.size() < 3: return PackedVector3Array()
	centre /= face.size()
	var u := (face[0]-centre).normalized(); var v := plane.normal.cross(u)
	var ordered: Array[Vector3] = []
	for point in face: ordered.append(point)
	ordered.sort_custom(func(a: Vector3,b: Vector3): return atan2((a-centre).dot(v),(a-centre).dot(u)) < atan2((b-centre).dot(v),(b-centre).dot(u)))
	return PackedVector3Array(ordered)

## Hull faces of every merge part in voxel units: the part, its plane, the polygon (counter-clockwise
## around the plane normal) and the palette slot painted on it. `planes` keeps the planes of each part.
static func hull_faces(model: Dictionary) -> Dictionary:
	var size := VoxMesher.ember_grid_size(model)
	var voxels := VoxMesher.model_channel(model,"voxels")
	var part_ids := PackedInt32Array(model.get("voxelPartIds",[]))
	var points := part_points(model)
	var faces: Array[Dictionary] = []
	var part_planes: Array = []
	for part in points.size():
		var planes: Array[Plane] = []
		part_planes.append(planes)
		if points[part].is_empty(): continue
		for direction: Vector3 in model.solidSurface.parts[part]:
			var distance := -INF
			for point in points[part]: distance = maxf(distance,direction.dot(point))
			planes.append(Plane(direction,distance))
		var corners := corners_of(planes)
		for plane in planes:
			var face := face_of(corners,plane)
			if face.size()<3: continue
			var centre := Vector3.ZERO
			for point in face: centre += point
			centre /= face.size()
			# Existing palette paint chooses the closest occupied support column.
			var nearest := Vector3.ZERO; var best := INF
			for point in points[part]:
				var distance := point.distance_squared_to(centre)
				if distance<best: best=distance; nearest=point
			var sample := Vector3i((nearest-plane.normal*0.51).floor()).clamp(Vector3i.ZERO,size-Vector3i.ONE)
			var slot := int(voxels[VoxMesher.cell_index(sample.x,sample.y,sample.z,size.x,size.z)])
			if part_ids[VoxMesher.cell_index(sample.x,sample.y,sample.z,size.x,size.z)] != part+1:
				# The support corner belongs to this part, but stepping inward can land
				# in a neighbouring roof/window/frame. One of its eight incident cells
				# belongs to the owner; retain that part's painted colour.
				var owner_distance := INF
				for dy in [-1,0]:
					for dz in [-1,0]:
						for dx in [-1,0]:
							var candidate := Vector3i(nearest)+Vector3i(dx,dy,dz)
							if candidate.x<0 or candidate.y<0 or candidate.z<0 or candidate.x>=size.x or candidate.y>=size.y or candidate.z>=size.z: continue
							var index := VoxMesher.cell_index(candidate.x,candidate.y,candidate.z,size.x,size.z)
							if part_ids[index] != part+1 or voxels[index]==0: continue
							var distance := (Vector3(candidate)+Vector3.ONE*0.5).distance_squared_to(centre)
							if distance<owner_distance: owner_distance=distance;slot=int(voxels[index])
			if slot==0: slot=1
			faces.append({"part":part,"plane":plane,"face":face,"slot":slot})
	return {"faces":faces,"planes":part_planes}


static func build(model: Dictionary) -> ArrayMesh:
	if uses_volume(model): return volume_mesh(model)
	var mesh := ArrayMesh.new()
	var arrays := hull_geometry(model)
	if arrays.is_empty(): return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},CUSTOM_FORMAT)
	mesh.surface_set_name(0,"solid_surface")
	mesh.set_meta("solid_surface_contract",CONTRACT)
	mesh.set_meta("solid_form_contract",FORM_CONTRACT)
	return mesh

## Immutable worker input; the same hull, volume and voxel builders as published props.
static func look_geometry(model:Dictionary,pulls:PackedFloat32Array)->Dictionary:
	if not active(model):return {}
	var volume:=uses_volume(model)
	var hull:Array=volume_geometry(model) if volume else hull_geometry(model)
	var detailed:Array=hull.duplicate()
	var living:Dictionary={}
	var has_pull:=false
	for pull in pulls:has_pull=has_pull or pull>0.0
	if volume and not detailed.is_empty():
		var custom:PackedFloat32Array=detailed[Mesh.ARRAY_CUSTOM0]
		var normals:=PackedVector3Array();normals.resize(custom.size()/4)
		for i in normals.size():normals[i]=Vector3(custom[i*4],custom[i*4+1],custom[i*4+2])
		detailed[Mesh.ARRAY_NORMAL]=normals
	elif not volume and has_pull:
		var field:=LivingFaces.new();field.prepare_field(model)
		living=living_geometry(model,AUTHORED_BLOCK_M,pulls,field)
		if not living.is_empty():detailed=living.arrays
	return {"arrays":[detailed,hull,voxel_geometry(model)],"volume":volume,"living":living,"pulls":pulls}

## Upload on the main thread and retain the ordinary prop material contracts.
static func look_meshes(model:Dictionary,geometry:Dictionary)->Array[ArrayMesh]:
	var result:Array[ArrayMesh]=[]
	for look in 3:
		var mesh:=ArrayMesh.new();var arrays:Array=geometry.arrays[look]
		if not arrays.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},CUSTOM_FORMAT)
			mesh.surface_set_name(0,"solid_surface")
		mesh.set_meta("solid_surface_contract",CONTRACT);mesh.set_meta("solid_form_contract",FORM_CONTRACT)
		if geometry.volume:mesh.set_meta("solid_volume_boundary",true)
		if look==2:
			mesh.set_meta("solid_pixel_cells",float(VoxMesher.voxels_per_block(model)));mesh.set_meta("solid_voxel_look",true)
		elif look==0 and not geometry.living.is_empty():
			mesh.set_meta("solid_living_faces",LIVING_CONTRACT);mesh.set_meta("solid_living_pulls",geometry.pulls)
			mesh.set_meta("solid_living_stats",geometry.living.stats)
		apply_materials(mesh,model)
		if look==0 and not geometry.volume:mesh=load("res://scripts/ember_solid_material_layers.gd").prepared_mesh(mesh,model)
		result.append(mesh)
	return result


## CPU-only buffers: workers never create rendering resources or modify the Source.
static func hull_geometry(model: Dictionary) -> Array:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	var colours := PackedColorArray(); var uv := PackedVector2Array(); var uv2 := PackedVector2Array()
	var density := float(VoxMesher.voxels_per_block(model))
	for entry in hull_faces(model).faces:
		var plane: Plane = entry.plane; var face: PackedVector3Array = entry.face; var slot: int = entry.slot
		for i in range(1,face.size()-1):
			if (face[i]-face[0]).cross(face[i+1]-face[0]).length_squared()<0.000001: continue
			for point in [face[0],face[i+1],face[i]]:
				vertices.append(point/density); normals.append(plane.normal)
				colours.append(Color(1,0,0,slot/255.0)); uv.append(Vector2(slot,slot)/255.0); uv2.append(Vector2(slot/255.0,0))
	if vertices.is_empty(): return []
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colours; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_TEX_UV2]=uv2
	arrays[Mesh.ARRAY_CUSTOM0]=form_custom(vertices,normals,PackedInt32Array())
	attach_edge_frame(arrays,vertices,normals)
	return arrays


static func apply_materials(mesh: ArrayMesh, model: Dictionary) -> void:
	if mesh.get_surface_count()==0 or mesh.surface_get_name(0)!="solid_surface":return
	mesh.set_meta("solid_surface_roles",model.solidSurface.roles.duplicate())
	mesh.set_meta("solid_surface_material_ids",model.solidSurface.material_ids.duplicate())
	mesh.set_meta("solid_surface_palette",VoxMesher._model_colors(model))
	var material:=material_for(mesh)
	for surface in mesh.get_surface_count(): mesh.surface_set_material(surface,material)

static var _depth_shader: Shader
const DEPTH_FADE_M := Vector2(9.0, 22.0)
## One authored block is one metre in every world; a world may draw a block as 16 units (the playable
## maps), so everything measured in metres here is a physical size, not a world-unit size.
const AUTHORED_BLOCK_M := 1.0


## The same terrain renderer with the optional material depth, in its solid-object form (object-local
## mapping, no extra varyings). Only the detailed look uses it; everything else keeps the plain shader.
static func solid_depth_shader() -> Shader:
	if _depth_shader == null:
		var base := load("res://shaders/ember_compact_terrain_textured.gdshader") as Shader
		_depth_shader = Shader.new()
		_depth_shader.code = "#define EMBER_TERRAIN_MATERIAL_DEPTH\n#define EMBER_SOLID_DEPTH\n" + base.code
		_depth_shader.set_meta("ember_compact_terrain_shader", true)
	return _depth_shader


static var _far_depth_shaders: Dictionary = {}

## Same color/finish program and bindings; only the already faded POM is absent.
static func far_depth_shader(full: Shader) -> Shader:
	if full != null:full=full.get_meta("ember_depth_full_shader",full) as Shader
	if full == null or not full.code.contains("#define EMBER_SOLID_DEPTH\n") or full.code.contains("EMBER_BEVEL_STUDY"):
		return null
	var key := full.get_instance_id()
	if not _far_depth_shaders.has(key):
		var far := Shader.new()
		far.code = "#define EMBER_SOLID_FAR\n" + full.code
		for name in full.get_meta_list():far.set_meta(name,full.get_meta(name))
		far.set_meta("ember_depth_full_shader", full)
		_far_depth_shaders[key] = far
	return _far_depth_shaders[key]


## World units per authored metre as the material currently knows it (1 = a metre-sized world).
static func depth_scale(material: ShaderMaterial) -> float:
	return float(material.get_meta("ember_units_per_metre", 1.0))


## The depth search runs in world space: amplitude and fade distances follow the world's unit size.
## Safe to call repeatedly; the colour mapping needs nothing (it converts blocks to metres itself).
static func set_world_scale(material: ShaderMaterial, units_per_metre: float) -> void:
	var previous := depth_scale(material)
	if units_per_metre <= 0.0 or is_equal_approx(previous, units_per_metre): return
	material.set_meta("ember_units_per_metre", units_per_metre)
	if not material.get_meta("ember_detailed_depth", false): return
	material.set_shader_parameter("terrain_depth_world_unit",units_per_metre)
	var ratio := units_per_metre / previous
	for parameter in ["material_depth_amplitude_m", "material_depth_fade_near_m", "material_depth_fade_far_m"]:
		var value = material.get_shader_parameter(parameter)
		if value != null: material.set_shader_parameter(parameter, float(value) * ratio)


## The same per-material bank as ground. No first-slot restriction on layered objects.
static func bind_detail(material: ShaderMaterial, mesh: ArrayMesh) -> bool:
	var materials=load("res://scripts/ember_voxel_surface_materials.gd")
	var ids: PackedStringArray=mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	materials.set_terrain_depth_profiles(material,mesh.get_meta("solid_surface_roles",PackedStringArray()),ids)
	var scale:=depth_scale(material)
	material.set_shader_parameter("terrain_depth_world_unit",scale)
	material.set_shader_parameter("material_depth_fade_near_m",DEPTH_FADE_M.x*scale)
	material.set_shader_parameter("material_depth_fade_far_m",DEPTH_FADE_M.y*scale)
	material.set_shader_parameter("material_depth_shadows",true)
	return bool(material.get_shader_parameter("material_depth_enabled"))


## Live update from a draft Pattern (editor preview): amplitude is a uniform; the height map is only
## re-derived when softness/sharpness changed (the caller decides when, e.g. on slider release).
static func update_detail(material: ShaderMaterial, mesh: ArrayMesh, pattern, id: String) -> void:
	if material == null or mesh == null or not material.get_meta("ember_detailed_depth", false):return
	var ids: PackedStringArray=mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	if not id in ids:return
	var drafts:Dictionary=material.get_meta("ember_depth_drafts",{})
	drafts[id]=pattern
	material.set_meta("ember_depth_drafts",drafts)
	load("res://scripts/ember_voxel_surface_materials.gd").set_terrain_depth_profiles(material,mesh.get_meta("solid_surface_roles",PackedStringArray()),ids,drafts)


static func material_for(mesh: ArrayMesh, detailed := false) -> ShaderMaterial:
	var materials=load("res://scripts/ember_voxel_surface_materials.gd")
	var material: ShaderMaterial=materials.compact_terrain_material()
	if detailed:material.shader=solid_depth_shader()
	materials.set_compact_terrain_roles(material,mesh.get_meta("solid_surface_roles"),mesh.get_meta("solid_surface_material_ids"),mesh.get_meta("solid_surface_palette"))
	material.set_shader_parameter("smooth_surface_enabled",true)
	material.set_shader_parameter("material_light_mode",1)
	material.set_meta("ember_derived_solid_material",true)
	# Meshes built before form normals keep the previous look exactly.
	if mesh.has_meta("solid_form_contract"):apply_form_look(material,1.0)
	# Voxel look: the same pattern is read once per voxel (texel-space quantisation).
	if mesh.has_meta("solid_pixel_cells"):material.set_shader_parameter("solid_pixel_cells",float(mesh.get_meta("solid_pixel_cells")))
	if detailed:
		material.set_meta("ember_detailed_depth",true)
		bind_detail(material,mesh)
		load("res://scripts/ember_solid_material_layers.gd").bind(material,mesh)
	return material

## Object-local periodic projection + rim from the continuous form normal.
## unit_m converts model units (blocks) to metres; the owning prop supplies it.
static func apply_form_look(material: ShaderMaterial, unit_m: float) -> void:
	material.set_shader_parameter("solid_projection_mode",1)
	material.set_shader_parameter("solid_form_rim",true)
	material.set_shader_parameter("solid_facet_bias",FACET_PROJECTION_BIAS)
	material.set_shader_parameter("solid_rim_edge",FORM_RIM_EDGE)
	material.set_shader_parameter("solid_local_unit_m",unit_m)


## Probe contract: per-vertex "form normal" in CUSTOM0.xyz. Facet normals keep
## lighting crisp; this smoother field (same hull, same positions) drives rim and
## projection-axis choice. Vertices are welded by position, so the field is
## continuous across facets of a part. Source/occupancy/collider are untouched.
## CUSTOM0 = form normal; CUSTOM1..3 = convex-edge distances and neighbour normals (edge_frame).
const CUSTOM_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
const FORM_CONTRACT := "solid-form-normals-v1"

static func with_form_normals(source: ArrayMesh, smoothing := 0) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
	arrays[Mesh.ARRAY_CUSTOM0] = form_custom(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], indices, smoothing)
	if indices.is_empty(): attach_edge_frame(arrays, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL])
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, CUSTOM_FORMAT if indices.is_empty() else Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	result.surface_set_name(0, source.surface_get_name(0))
	for meta in source.get_meta_list(): result.set_meta(meta, source.get_meta(meta))
	result.set_meta("solid_form_contract", FORM_CONTRACT)
	result.surface_set_material(0, source.surface_get_material(0))
	return result


## CUSTOM0 RGBA float payload: smoothed form normal in xyz (non-indexed or indexed triangles).
static func form_custom(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, smoothing := 0) -> PackedFloat32Array:
	var corner_count := indices.size() if not indices.is_empty() else vertices.size()
	var weld := {}; var welded := PackedInt32Array(); welded.resize(vertices.size())
	var positions := PackedVector3Array()
	for i in vertices.size():
		var key := Vector3i((vertices[i] * 1000.0).round())
		if not weld.has(key): weld[key] = positions.size(); positions.append(vertices[i])
		welded[i] = weld[key]
	var accum := PackedVector3Array(); accum.resize(positions.size())
	var neighbours: Array[PackedInt32Array] = []
	for _i in positions.size(): neighbours.append(PackedInt32Array())
	for t in range(0, corner_count, 3):
		var corner: Array[int] = []
		for k in 3: corner.append(indices[t + k] if not indices.is_empty() else t + k)
		for k in 3:
			var a := vertices[corner[k]]; var b := vertices[corner[(k + 1) % 3]]; var c := vertices[corner[(k + 2) % 3]]
			var angle := (b - a).normalized().angle_to((c - a).normalized())
			# Interior angle summed over a facet's fan equals the polygon corner angle.
			accum[welded[corner[k]]] += normals[corner[k]] * angle
			var other := welded[corner[(k + 1) % 3]]
			if not neighbours[welded[corner[k]]].has(other): neighbours[welded[corner[k]]].append(other)
			other = welded[corner[(k + 2) % 3]]
			if not neighbours[welded[corner[k]]].has(other): neighbours[welded[corner[k]]].append(other)
	var field := PackedVector3Array(); field.resize(positions.size())
	for i in field.size(): field[i] = accum[i].normalized() if accum[i].length_squared() > 0.0 else Vector3.UP
	for _pass in maxi(smoothing, 0):
		var next := PackedVector3Array(); next.resize(field.size())
		for i in field.size():
			var sum := field[i]
			for other in neighbours[i]: sum += field[other]
			next[i] = sum.normalized() if sum.length_squared() > 0.0 else field[i]
		field = next
	var custom := PackedFloat32Array(); custom.resize(vertices.size() * 4)
	for i in vertices.size():
		var n := field[welded[i]]
		custom[i * 4] = n.x; custom[i * 4 + 1] = n.y; custom[i * 4 + 2] = n.z; custom[i * 4 + 3] = 1.0
	return custom


## Living faces (detailed look): every hull face is re-triangulated on a ~14 cm point set and its inside is
## pushed along the face normal, following how the voxel Source itself undulates behind that face. The pull is
## clamped to the material's form_pull_mm and fades to zero towards hull edges and towards the creases where
## another part's hull cuts the face, so the silhouette, the hull edges and the collider stay exact.
## Display only: the Source, the hull and the collider are not changed.
const LIVING_CONTRACT := "solid-living-faces-v1"
const LIVING_SPACING_M := 0.14
const LIVING_MARGIN_M := 0.16
## Share of the voxel undulation the face follows before the material limit applies.
const LIVING_FOLLOW := 0.6
const LIVING_BLUR_VOXELS := 1.2
const LIVING_REACH_VOXELS := 10.0
const LIVING_CACHE_LIMIT := 6
static var _living_cache: Dictionary = {}
static var _living_field: Dictionary = {}
const LivingStorage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
static var living_disk_hits:=0
static var _boundary_displays:Dictionary={}


static func clear_living_cache() -> void:
	_living_cache.clear(); _living_field.clear()
	_boundary_displays.clear()

## Published volume arrays already contain the exact boundary and smooth form
## normals. A display switch does not need to scan the voxel grid a second time.
static func detailed_volume_from_boundary(boundary:ArrayMesh)->ArrayMesh:
	var key:=boundary.get_instance_id()
	if _boundary_displays.has(key):return _boundary_displays[key]
	var result:=ArrayMesh.new()
	for surface in boundary.get_surface_count():
		var arrays:=boundary.surface_get_arrays(surface)
		var custom:PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
		var normals:=PackedVector3Array();normals.resize(custom.size()/4)
		for i in normals.size():normals[i]=Vector3(custom[i*4],custom[i*4+1],custom[i*4+2])
		arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TANGENT]=null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},CUSTOM_FORMAT)
		result.surface_set_name(surface,boundary.surface_get_name(surface))
	for meta in boundary.get_meta_list():result.set_meta(meta,boundary.get_meta(meta))
	if _boundary_displays.size()>=6:_boundary_displays.erase(_boundary_displays.keys()[0])
	_boundary_displays[key]=result
	return result


## Pull limit in metres of every palette slot, read from the saved Patterns of the mesh materials.
static func living_pulls(material_ids: PackedStringArray) -> PackedFloat32Array:
	var materials=load("res://scripts/ember_voxel_surface_materials.gd")
	var result := PackedFloat32Array(); result.resize(material_ids.size())
	for slot in material_ids.size():
		if material_ids[slot].is_empty(): continue
		var pattern=materials.load_compact_terrain_variant(material_ids[slot])
		if pattern != null: result[slot] = pattern.form_pull_mm * 0.001
	return result


## Cached wrapper: the mesh depends on the Source, the object scale and the pull of every palette slot.
## Returns an empty mesh when no material asks for a pull.
static func living_mesh(model: Dictionary, unit_m: float, pulls: PackedFloat32Array) -> ArrayMesh:
	# Check the existing derived cache before rescanning every occupied cell.
	# Include topology: the same voxels can intentionally switch to a volume.
	var profile:Dictionary=model.get("solidSurface",{})
	var shape_key := "%d|%d|%d|%d|%s|%s|%d" % [hash(str(profile.get("parts",[]))), hash(VoxMesher.model_channel(model, "voxels")), hash(PackedInt32Array(model.get("voxelPartIds", []))), hash(str(profile.get("occupancy", ""))),str(profile.get("topology","hull")),str(VoxMesher.ember_grid_size(model)),VoxMesher.voxels_per_block(model)]
	var pull_key := ",".join(Array(pulls).map(func(value: float): return "%.4f" % value))
	var key := "%s|%.4f|%s" % [shape_key, unit_m, pull_key]
	if _living_cache.has(key): return _living_cache[key]
	# Edited volumes still own their exact boundary and physical surface.
	if uses_volume(model): return volume_mesh(model,true)
	var any := false
	for pull in pulls: any = any or pull > 0.0
	if not any or unit_m <= 0.0 or profile.is_empty(): return ArrayMesh.new()
	var storage:=LivingStorage.new();storage.directory="user://ember-solid-living-cache";storage.max_bytes=128*1024*1024
	var disk_key:=storage.digest([1,Engine.get_version_info().hex,LIVING_CONTRACT,FORM_CONTRACT,VoxMesher.ember_grid_size(model),VoxMesher.voxels_per_block(model),model.solidSurface,VoxMesher.model_channel(model,"voxels"),PackedInt32Array(model.get("voxelPartIds",[])),unit_m,pulls])
	var geometry:Dictionary=storage.read(disk_key).get("geometry",{})
	if geometry.get("arrays") is Array and geometry.arrays.size()==Mesh.ARRAY_MAX and geometry.get("stats") is Dictionary:
		living_disk_hits+=1
	else:
		if _living_field.get("key", "") != shape_key:
			var field := LivingFaces.new()
			field.prepare_field(model)
			_living_field = {"key": shape_key, "field": field}
		geometry=living_geometry(model,unit_m,pulls,_living_field.field)
		if not geometry.is_empty():storage.write(disk_key,{"geometry":geometry},func():return false);storage.trim()
	var mesh := _build_living(geometry,pulls)
	if _living_cache.size() >= LIVING_CACHE_LIMIT: _living_cache.erase(_living_cache.keys()[0])
	_living_cache[key] = mesh
	return mesh


static func _build_living(geometry:Dictionary,pulls:PackedFloat32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if geometry.is_empty(): return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry.arrays, [], {}, CUSTOM_FORMAT)
	mesh.surface_set_name(0, "solid_surface")
	mesh.set_meta("solid_surface_contract", CONTRACT)
	mesh.set_meta("solid_form_contract", FORM_CONTRACT)
	mesh.set_meta("solid_living_faces", LIVING_CONTRACT)
	mesh.set_meta("solid_living_pulls", pulls)
	mesh.set_meta("solid_living_stats", geometry.stats)
	return mesh


static func living_geometry(model: Dictionary, unit_m: float, pulls: PackedFloat32Array, worker: LivingFaces) -> Dictionary:
	var density := float(VoxMesher.voxels_per_block(model))
	var hull := hull_faces(model)
	var entries: Array = hull.faces
	# Hull fan (identical to build()) gives the form normal the low-poly look already uses; the living
	# vertices read it back by barycentric interpolation, so projection axis and rim choice do not change.
	var fan_vertices := PackedVector3Array(); var fan_normals := PackedVector3Array(); var starts: Array[int] = []
	for entry in entries:
		var face: PackedVector3Array = entry.face; var plane: Plane = entry.plane
		starts.append(fan_vertices.size())
		for i in range(1, face.size() - 1):
			if (face[i] - face[0]).cross(face[i + 1] - face[0]).length_squared() < 0.000001: continue
			for point in [face[0], face[i + 1], face[i]]:
				fan_vertices.append(point / density); fan_normals.append(plane.normal)
	starts.append(fan_vertices.size())
	var fan_custom := form_custom(fan_vertices, fan_normals, PackedInt32Array())
	worker.begin(unit_m / density, density, hull.planes)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var fan: Array = []
		for corner in range(starts[index], starts[index + 1], 3):
			var tri: Array = []
			for k in 3: tri.append(fan_vertices[corner + k] * density)
			for k in 3: tri.append(Vector3(fan_custom[(corner + k) * 4], fan_custom[(corner + k) * 4 + 1], fan_custom[(corner + k) * 4 + 2]))
			fan.append(tri)
		var slot: int = entry.slot
		var pull_m := pulls[slot] if slot < pulls.size() else 0.0
		if pull_m <= 0.0 or not worker.add_living_face(entry, pull_m / worker.voxel_m, fan):
			worker.add_flat_face(entry, fan)
	if worker.vertices.is_empty(): return {}
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = worker.vertices; arrays[Mesh.ARRAY_NORMAL] = worker.normals
	arrays[Mesh.ARRAY_COLOR] = worker.colours; arrays[Mesh.ARRAY_TEX_UV] = worker.uv; arrays[Mesh.ARRAY_TEX_UV2] = worker.uv2
	arrays[Mesh.ARRAY_CUSTOM0] = worker.custom
	attach_edge_frame(arrays, worker.vertices, worker.hull_normals)
	var geometry := {"arrays":arrays,"stats":worker.stats.duplicate()}
	worker.clear_output()
	return geometry



## Working state of one living-faces build (voxel units unless a name says metres).
class LivingFaces extends RefCounted:
	var origin := Vector3i.ZERO
	var extent := Vector3i.ZERO
	var field := PackedFloat32Array()
	var voxel_m := 0.0625
	var density := 16.0
	var planes: Array = []
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var hull_normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var custom := PackedFloat32Array()
	var stats := {}

	func begin(voxel_metres: float, voxels_per_block: float, part_planes: Array) -> void:
		voxel_m = voxel_metres; density = voxels_per_block; planes = part_planes
		clear_output()
		stats = {"faces": 0, "fallback": 0, "max_cm": 0.0, "sum_cm": 0.0, "points": 0}

	func clear_output() -> void:
		vertices = PackedVector3Array(); normals = PackedVector3Array(); hull_normals = PackedVector3Array()
		colours = PackedColorArray(); uv = PackedVector2Array(); uv2 = PackedVector2Array(); custom = PackedFloat32Array()

	## Occupancy of the Source blurred by ~1.2 voxels, stored only around the occupied cells.
	func prepare_field(model: Dictionary) -> void:
		var grid := VoxMesher.ember_grid_size(model)
		var voxels := VoxMesher.model_channel(model, "voxels")
		var low := grid; var high := Vector3i.ZERO
		for z in grid.z:
			for y in grid.y:
				for x in grid.x:
					if voxels[VoxMesher.cell_index(x, y, z, grid.x, grid.z)] == 0: continue
					low = low.min(Vector3i(x, y, z)); high = high.max(Vector3i(x + 1, y + 1, z + 1))
		if high.x <= low.x: return
		var pad := int(ceil(LIVING_BLUR_VOXELS * 2.5)) + 2
		origin = low - Vector3i.ONE * pad
		extent = high + Vector3i.ONE * pad - origin
		field = PackedFloat32Array(); field.resize(extent.x * extent.y * extent.z)
		for z in range(low.z, high.z):
			for y in range(low.y, high.y):
				for x in range(low.x, high.x):
					if voxels[VoxMesher.cell_index(x, y, z, grid.x, grid.z)] != 0:
						field[(x - origin.x) + extent.x * ((y - origin.y) + extent.y * (z - origin.z))] = 1.0
		field = _blur(field, LIVING_BLUR_VOXELS)

	## Separable gaussian; scatters only from non-zero cells because the field is mostly empty.
	func _blur(source: PackedFloat32Array, sigma: float) -> PackedFloat32Array:
		var radius := int(ceil(sigma * 2.5))
		var kernel := PackedFloat32Array(); var total := 0.0
		for i in range(-radius, radius + 1):
			var weight := exp(-0.5 * float(i * i) / (sigma * sigma)); kernel.append(weight); total += weight
		for i in kernel.size(): kernel[i] /= total
		var strides := [1, extent.x, extent.x * extent.y]
		var lengths := [extent.x, extent.y, extent.z]
		var current := source
		for axis in 3:
			var stride: int = strides[axis]; var length: int = lengths[axis]
			var out := PackedFloat32Array(); out.resize(current.size())
			for i in current.size():
				var value := current[i]
				if value == 0.0: continue
				var position: int = (i / stride) % length
				for k in range(-radius, radius + 1):
					var q := position + k
					if q < 0 or q >= length: continue
					out[i + k * stride] += value * kernel[k + radius]
			current = out
		return current

	func sample(p: Vector3) -> float:
		if field.is_empty(): return 0.0
		var q := p - Vector3(0.5, 0.5, 0.5) - Vector3(origin)
		var x0 := int(floor(q.x)); var y0 := int(floor(q.y)); var z0 := int(floor(q.z))
		var f := Vector3(q.x - x0, q.y - y0, q.z - z0)
		var result := 0.0
		for c in 8:
			var cx := x0 + (c & 1); var cy := y0 + ((c >> 1) & 1); var cz := z0 + ((c >> 2) & 1)
			if cx < 0 or cy < 0 or cz < 0 or cx >= extent.x or cy >= extent.y or cz >= extent.z: continue
			var weight := (f.x if (c & 1) == 1 else 1.0 - f.x) * (f.y if ((c >> 1) & 1) == 1 else 1.0 - f.y) * (f.z if ((c >> 2) & 1) == 1 else 1.0 - f.z)
			result += weight * field[cx + extent.x * (cy + extent.y * cz)]
		return result

	## Inward distance from a hull-plane point to the voxel surface; the reach if there is none.
	func depth_below(point: Vector3, n: Vector3) -> float:
		var t := 0.0
		while t < LIVING_REACH_VOXELS:
			if sample(point - n * t) >= 0.5: return t
			t += 0.25
		return LIVING_REACH_VOXELS

	## Smallest signed distance (voxels, lower bound) to the hulls of the other parts: < 0 means hidden inside one.
	func outside_others(part: int, p: Vector3) -> float:
		var best := INF
		for other in planes.size():
			if other == part: continue
			var inner := -INF
			for plane: Plane in planes[other]: inner = maxf(inner, plane.distance_to(p))
			best = minf(best, inner)
		return best

	func _key(p: Vector3) -> Vector3i:
		return Vector3i((p * 1000.0).round())

	func _in_convex(poly: Array, p: Vector2) -> bool:
		for k in poly.size():
			var a: Vector2 = poly[k]; var b: Vector2 = poly[(k + 1) % poly.size()]
			if (b - a).cross(p - a) < -1.0e-6: return false
		return true

	func _boundary_distance(poly: Array, p: Vector2) -> float:
		var best := INF
		for k in poly.size():
			var a: Vector2 = poly[k]; var b: Vector2 = poly[(k + 1) % poly.size()]
			var e := b - a
			best = minf(best, e.cross(p - a) / e.length())
		return best

	func _clip(poly: Array, a: float, b: float, c: float) -> Array:
		var out: Array = []
		for k in poly.size():
			var p: Vector2 = poly[k]; var q: Vector2 = poly[(k + 1) % poly.size()]
			var fp := a * p.x + b * p.y - c; var fq := a * q.x + b * q.y - c
			if fp <= 0.0: out.append(p)
			if (fp < 0.0 and fq > 0.0) or (fp > 0.0 and fq < 0.0): out.append(p + (q - p) * (fp / (fp - fq)))
		return out

	## Both faces sharing an edge must produce identical points: interpolate from the canonically smaller end.
	func _edge_points(a: Vector3, b: Vector3, spacing: float) -> Array[Vector3]:
		var ka := _key(a); var kb := _key(b)
		var forward := ka.x < kb.x or (ka.x == kb.x and (ka.y < kb.y or (ka.y == kb.y and ka.z < kb.z)))
		var p0 := a if forward else b; var p1 := b if forward else a
		var count := maxi(1, int(ceil(p0.distance_to(p1) / spacing)))
		var result: Array[Vector3] = []
		if forward:
			for i in range(0, count): result.append(p0.lerp(p1, float(i) / count))
		else:
			for i in range(count, 0, -1): result.append(p0.lerp(p1, float(i) / count))
		return result

	func _form_at(fan: Array, p: Vector3, fallback: Vector3) -> Vector3:
		var best := fallback; var best_score := -INF
		for tri: Array in fan:
			var a: Vector3 = tri[0]; var b: Vector3 = tri[1]; var c: Vector3 = tri[2]
			var v0 := b - a; var v1 := c - a; var v2 := p - a
			var d00 := v0.dot(v0); var d01 := v0.dot(v1); var d11 := v1.dot(v1); var d20 := v2.dot(v0); var d21 := v2.dot(v1)
			var denom := d00 * d11 - d01 * d01
			if absf(denom) < 1.0e-9: continue
			var w1 := (d11 * d20 - d01 * d21) / denom
			var w2 := (d00 * d21 - d01 * d20) / denom
			var w0 := 1.0 - w1 - w2
			var score := minf(w0, minf(w1, w2))
			if score > best_score:
				best_score = score
				var na: Vector3 = tri[3]; var nb: Vector3 = tri[4]; var nc: Vector3 = tri[5]
				best = na * w0 + nb * w1 + nc * w2
			if score >= -1.0e-4: break
		return best

	func _push(position: Vector3, normal: Vector3, hull_normal: Vector3, slot: int, form: Vector3) -> void:
		vertices.append(position / density); normals.append(normal); hull_normals.append(hull_normal)
		colours.append(Color(1, 0, 0, slot / 255.0)); uv.append(Vector2(slot, slot) / 255.0); uv2.append(Vector2(slot / 255.0, 0))
		custom.append(form.x); custom.append(form.y); custom.append(form.z); custom.append(1.0)

	## The hull face itself (fan of build()), used when a face has no pull or could not be re-triangulated.
	func add_flat_face(entry: Dictionary, fan: Array) -> void:
		var plane: Plane = entry.plane
		for tri: Array in fan:
			for k in 3: _push(tri[k], plane.normal, plane.normal, entry.slot, tri[3 + k])

	func add_living_face(entry: Dictionary, limit: float, fan: Array) -> bool:
		var part: int = entry.part; var plane: Plane = entry.plane; var face: PackedVector3Array = entry.face; var slot: int = entry.slot
		var n := plane.normal
		var centre := Vector3.ZERO
		for p in face: centre += p
		centre /= face.size()
		var u := (face[0] - centre).normalized(); var v := n.cross(u)
		var spacing := LIVING_SPACING_M / voxel_m
		var margin := LIVING_MARGIN_M / voxel_m
		var poly: Array = []
		for p in face: poly.append(Vector2((p - centre).dot(u), (p - centre).dot(v)))
		var area := 0.0
		for k in poly.size(): area += (poly[k] as Vector2).cross(poly[(k + 1) % poly.size()])
		area = absf(area) * 0.5
		# Hull edge points, shared exactly with the neighbouring face.
		var points2 := PackedVector2Array()
		for k in face.size():
			for p in _edge_points(face[k], face[(k + 1) % face.size()], spacing):
				points2.append(Vector2((p - centre).dot(u), (p - centre).dot(v)))
		var boundary_count := points2.size()
		# Creases where another part's hull cuts this face: the visible face meets that part along them.
		var curve: Array[Vector2] = []
		for other in planes.size():
			if other == part: continue
			var piece := poly
			for other_plane: Plane in planes[other]:
				piece = _clip(piece, other_plane.normal.dot(u), other_plane.normal.dot(v), other_plane.d - other_plane.normal.dot(centre))
				if piece.size() < 3: break
			if piece.size() < 3: continue
			for k in piece.size():
				var a: Vector2 = piece[k]
				var b: Vector2 = piece[(k + 1) % piece.size()]
				if _boundary_distance(poly, (a + b) * 0.5) < 0.02: continue
				var count := maxi(1, int(ceil(a.distance_to(b) / (spacing * 0.6))))
				for i in count:
					var candidate := a.lerp(b, float(i) / count)
					if _boundary_distance(poly, candidate) < spacing * 0.2: continue
					var duplicate := false
					for existing in curve:
						if existing.distance_squared_to(candidate) < spacing * spacing * 0.0625:
							duplicate = true
							break
					if not duplicate: curve.append(candidate)
		for candidate in curve: points2.append(candidate)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for p: Vector2 in poly:
			low = low.min(p)
			high = high.max(p)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i((centre * 4.0).round())) ^ (part * 7919)
		var y := low.y + spacing * 0.5
		while y < high.y:
			var x := low.x + spacing * 0.5
			while x < high.x:
				var candidate := Vector2(x, y) + Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.28, 0.28)) * spacing
				if _in_convex(poly, candidate) and _boundary_distance(poly, candidate) > spacing * 0.55:
					var visible := outside_others(part, centre + u * candidate.x + v * candidate.y)
					var near_curve := false
					for existing in curve:
						if existing.distance_squared_to(candidate) < spacing * spacing * 0.2:
							near_curve = true
							break
					if visible > spacing * 0.4 and not near_curve: points2.append(candidate)
				x += spacing
			y += spacing
		if points2.size() < 3: return false
		var triangles := Geometry2D.triangulate_delaunay(points2)
		var covered := 0.0
		for t in range(0, triangles.size(), 3):
			covered += absf((points2[triangles[t + 1]] - points2[triangles[t]]).cross(points2[triangles[t + 2]] - points2[triangles[t]])) * 0.5
		if triangles.is_empty() or covered < area * 0.995:
			# Delaunay left a gap (collinear boundary points): ear-clip the boundary ring, no interior points.
			stats.fallback += 1
			points2.resize(boundary_count)
			triangles = Geometry2D.triangulate_polygon(points2)
			if triangles.is_empty(): return false
		var raw := PackedFloat32Array(); raw.resize(points2.size())
		var weights := PackedFloat32Array(); weights.resize(points2.size())
		var mean := 0.0
		var counted := 0
		for i in points2.size():
			var p3 := centre + u * points2[i].x + v * points2[i].y
			var hidden := outside_others(part, p3)
			weights[i] = 0.0 if i < boundary_count else minf(smoothstep(0.0, margin, _boundary_distance(poly, points2[i])), smoothstep(0.0, margin, hidden))
			if hidden >= -0.0001:
				raw[i] = depth_below(p3, n)
				mean += raw[i]
				counted += 1
			else:
				raw[i] = -1.0
		mean /= maxf(counted, 1)
		var positions := PackedVector3Array(); positions.resize(points2.size())
		var flat := PackedVector3Array(); flat.resize(points2.size())
		for i in points2.size():
			var d := 0.0
			if raw[i] >= 0.0: d = clampf(LIVING_FOLLOW * (mean - raw[i]), -limit, limit) * weights[i]
			flat[i] = centre + u * points2[i].x + v * points2[i].y
			positions[i] = flat[i] + n * d
			stats.max_cm = maxf(stats.max_cm, absf(d) * voxel_m * 100.0)
			stats.sum_cm += absf(d) * voxel_m * 100.0
			stats.points += 1
		var accumulated := PackedVector3Array(); accumulated.resize(points2.size())
		var ordered: Array = []
		for t in range(0, triangles.size(), 3):
			var ia: int = triangles[t]
			var ib: int = triangles[t + 1]
			var ic: int = triangles[t + 2]
			if (points2[ib] - points2[ia]).cross(points2[ic] - points2[ia]) < 0.0:
				var swap := ib
				ib = ic
				ic = swap
			var g := (positions[ib] - positions[ia]).cross(positions[ic] - positions[ia])
			accumulated[ia] += g
			accumulated[ib] += g
			accumulated[ic] += g
			ordered.append([ia, ib, ic])
		var forms := PackedVector3Array(); forms.resize(points2.size())
		for i in points2.size(): forms[i] = _form_at(fan, flat[i], n)
		stats.faces += 1
		for tri: Array in ordered:
			# Counter-clockwise around +n seen from outside; Godot wants clockwise.
			for index: int in [tri[0], tri[2], tri[1]]:
				var vn := accumulated[index]
				_push(positions[index], vn.normalized() if vn.length_squared() > 1.0e-12 else n, n, slot, forms[index])
		return true


static var _volume_cache: Dictionary = {}
const VOLUME_EDGES := [[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]]
const VOLUME_FACES := [
	[Vector3i(1,0,0),Vector3i(0,1,0),Vector3i(0,0,1)],
	[Vector3i(-1,0,0),Vector3i(0,0,1),Vector3i(0,1,0)],
	[Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,0)],
	[Vector3i(0,-1,0),Vector3i(1,0,0),Vector3i(0,0,1)],
	[Vector3i(0,0,1),Vector3i(1,0,0),Vector3i(0,1,0)],
	[Vector3i(0,0,-1),Vector3i(0,1,0),Vector3i(1,0,0)]]

## Surface nets over occupied voxel centres, padded by empty space. One vertex
## per crossing cell; each exposed Source face owns a dual quad and its paint.
## Shared vertices keep the cavity closed across material/part boundaries.
## CPU arrays only; nothing here modifies the Source or creates a renderer.
static func volume_geometry(model: Dictionary) -> Array:
	var size := VoxMesher.ember_grid_size(model)
	var values := VoxMesher.model_channel(model,"voxels")
	var density := float(VoxMesher.voxels_per_block(model))
	var points := PackedVector3Array(); var sums := PackedVector3Array()
	var paint_masks:Array[Dictionary]=[]
	var point_cells:Array[Vector3i]=[];var links:=PackedInt32Array()
	var cells := {}; var triangles := PackedInt32Array(); var slots := PackedInt32Array()
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var cell := Vector3i(x,y,z)
				var slot := _volume_sample(values,size,cell)
				if slot==0: continue
				for face in VOLUME_FACES:
					var n:Vector3i=face[0];var u:Vector3i=face[1];var v:Vector3i=face[2]
					if _volume_sample(values,size,cell+n)!=0: continue
					var base := cell+Vector3i(mini(n.x,0),mini(n.y,0),mini(n.z,0))-u-v
					var corners := PackedInt32Array()
					for key:Vector3i in [base,base+u,base+u+v,base+v]:
						if not cells.has(key):
							cells[key]=points.size()
							points.append(_volume_point(values,size,key)/density)
							paint_masks.append({})
							point_cells.append(key)
							sums.append(Vector3.ZERO)
						corners.append(cells[key])
					# Vote once per incident surface quad, not per triangle: a
					# diagonal must not bias the painted boundary. Only connected
					# surface corners mix, never nearby faces across an empty gap.
					for index in corners:
						paint_masks[index][slot]=float(paint_masks[index].get(slot,0.0))+1.0
					# Only true net edges, never triangulation diagonals: the latter
					# would introduce a directional bias on an otherwise flat slope.
					for i in 4:links.append_array(PackedInt32Array([corners[i],corners[(i+1)%4]]))
					for order in [[0,2,1],[0,3,2]]:
						var a:=corners[order[0]];var b:=corners[order[1]];var c:=corners[order[2]]
						var normal:Vector3=(points[c]-points[a]).cross(points[b]-points[a])
						if normal.length_squared()<1e-16:continue
						triangles.append_array(PackedInt32Array([a,b,c]));slots.append(slot)
	if triangles.is_empty():return []
	points=_fair_volume_points(points,point_cells,links,density)
	# Both lighting variants and physics use the same relaxed positions.
	sums.fill(Vector3.ZERO)
	for i in range(0,triangles.size(),3):
		var a:=triangles[i];var b:=triangles[i+1];var c:=triangles[i+2]
		var normal:Vector3=(points[c]-points[a]).cross(points[b]-points[a])
		sums[a]+=normal;sums[b]+=normal;sums[c]+=normal
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colours:=PackedColorArray()
	var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var custom:=PackedFloat32Array()
	var paint_packing=load("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
	for t in slots.size():
		var a:=triangles[t*3];var b:=triangles[t*3+1];var c:=triangles[t*3+2]
		var normal:Vector3=(points[c]-points[a]).cross(points[b]-points[a]).normalized()
		var slot:=float(slots[t])/255.0
		var blended:=paint_masks[a].size()>1 or paint_masks[b].size()>1 or paint_masks[c].size()>1
		if blended:
			# Use the ground's existing three-slot packing/normalisation. The
			# band spans the two incident voxel rows (~12.5 cm at density16).
			paint_packing._emit_blended(
				[points[a],points[b],points[c]],[normal,normal,normal],
				[paint_masks[a],paint_masks[b],paint_masks[c]],slots[t],vertices,normals,colours,uv,uv2)
		for index in [a,b,c]:
			if not blended:
				vertices.append(points[index]);normals.append(normal)
				colours.append(Color(1,0,0,slot));uv.append(Vector2(slot,slot));uv2.append(Vector2(slot,0))
			var smooth:=sums[index].normalized()
			custom.append_array(PackedFloat32Array([smooth.x,smooth.y,smooth.z,1]))
		# Keep original Source face ownership in alpha for existing picking;
		# the shader reads the blended palette IDs from UV/UV2 instead.
		if blended:
			for index in range(colours.size()-3,colours.size()):colours[index].a=slot
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colours
	arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_CUSTOM0]=custom
	attach_edge_frame(arrays,vertices,normals)
	return arrays

## Constrained surface-net relaxation: remove voxel-frequency corrugation,
## without changing connectivity, paint ownership or the occupied Source.
## Four Jacobi passes; total movement <=0.35 voxel, model bounds stay exact.
static func _fair_volume_points(points:PackedVector3Array,cells:Array[Vector3i],links:PackedInt32Array,density:float)->PackedVector3Array:
	var original:=points.duplicate();var counts:=PackedInt32Array();counts.resize(points.size())
	var minimum:=Vector3(INF,INF,INF);var maximum:=-minimum
	for p in original:minimum=minimum.min(p);maximum=maximum.max(p)
	for i in range(0,links.size(),2):counts[links[i]]+=1;counts[links[i+1]]+=1
	for pass_index in 4:
		var sums:=PackedVector3Array();sums.resize(points.size())
		for i in range(0,links.size(),2):
			var a:=links[i];var b:=links[i+1];sums[a]+=points[b];sums[b]+=points[a]
		var next:=points.duplicate()
		for i in points.size():
			if counts[i]==0:continue
			var p:=points[i].lerp(sums[i]/float(counts[i]),0.5)
			var shift:=p-original[i]
			if shift.length()>0.35/density:p=original[i]+shift.limit_length(0.35/density)
			var lo:=(Vector3(cells[i])+Vector3.ONE*0.5001)/density
			var hi:=(Vector3(cells[i])+Vector3.ONE*1.4999)/density
			p=p.clamp(lo,hi)
			for axis in 3:
				if is_equal_approx(original[i][axis],minimum[axis]) or is_equal_approx(original[i][axis],maximum[axis]):p[axis]=original[i][axis]
			next[i]=p
		points=next
	return points

static func _volume_sample(values:PackedByteArray,size:Vector3i,cell:Vector3i)->int:
	if cell.x<0 or cell.y<0 or cell.z<0 or cell.x>=size.x or cell.y>=size.y or cell.z>=size.z:return 0
	return values[VoxMesher.cell_index(cell.x,cell.y,cell.z,size.x,size.z)]

static func _volume_point(values:PackedByteArray,size:Vector3i,cell:Vector3i)->Vector3:
	var occupied:=PackedByteArray();var corners:=PackedVector3Array()
	for i in 8:
		var offset:=Vector3i(i&1,(i>>1)&1,(i>>2)&1)
		occupied.append(1 if _volume_sample(values,size,cell+offset)>0 else 0)
		corners.append(Vector3(cell+offset)+Vector3.ONE*0.5)
	var point:=Vector3.ZERO;var count:=0
	for edge in VOLUME_EDGES:
		if occupied[edge[0]]!=occupied[edge[1]]:
			point+=(corners[edge[0]]+corners[edge[1]])*0.5;count+=1
	return point/float(count) if count>0 else Vector3(cell)+Vector3.ONE

## Flat and smooth lighting share identical positions. Cache only bounded
## derived geometry; colour is in the key, so repaint cannot reuse stale slots.
static func volume_mesh(model:Dictionary,smooth:=false)->ArrayMesh:
	var key:="%s|%s|%s|%s|%s"%[VOLUME_CONTRACT,VoxMesher.ember_grid_size(model),VoxMesher.voxels_per_block(model),hash(VoxMesher.model_channel(model,"voxels")),hash([model.get("palette",[]),model.solidSurface.roles,model.solidSurface.material_ids])]
	if not _volume_cache.has(key):
		if _volume_cache.size()>=3:_volume_cache.erase(_volume_cache.keys()[0])
		_volume_cache[key]={"arrays":volume_geometry(model)}
	var entry:Dictionary=_volume_cache[key]
	var look:="smooth" if smooth else "flat"
	if entry.has(look):return entry[look]
	var mesh:=ArrayMesh.new();var arrays:Array=entry.arrays.duplicate()
	if not arrays.is_empty():
		if smooth:
			var custom:PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
			var normals:=PackedVector3Array();normals.resize(custom.size()/4)
			for i in normals.size():normals[i]=Vector3(custom[i*4],custom[i*4+1],custom[i*4+2])
			arrays[Mesh.ARRAY_NORMAL]=normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},CUSTOM_FORMAT)
		mesh.surface_set_name(0,"solid_surface")
	mesh.set_meta("solid_surface_contract",CONTRACT);mesh.set_meta("solid_form_contract",FORM_CONTRACT)
	mesh.set_meta("solid_volume_boundary",true)
	entry[look]=mesh
	return mesh

## One flat quad per exposed Source face, using the same material renderer.
## Unedited objects keep hull physics; carved volumes follow their displayed boundary.
static func build_voxel_look(model: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := voxel_geometry(model)
	if arrays.is_empty(): return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, CUSTOM_FORMAT)
	mesh.surface_set_name(0, "solid_surface")
	mesh.set_meta("solid_form_contract", FORM_CONTRACT)
	mesh.set_meta("solid_pixel_cells", float(VoxMesher.voxels_per_block(model)))
	mesh.set_meta("solid_voxel_look", true)
	return mesh


static func voxel_geometry(model: Dictionary) -> Array:
	var size := VoxMesher.ember_grid_size(model)
	var voxels := VoxMesher.model_channel(model, "voxels")
	var density := float(VoxMesher.voxels_per_block(model))
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var colours := PackedColorArray()
	var uv := PackedVector2Array(); var uv2 := PackedVector2Array(); var custom := PackedFloat32Array()
	# normal, u, v with u x v = normal (corners counter-clockwise seen from outside).
	var faces := [
		[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)], [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0)],
		[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)], [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0)], [Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]]
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var slot := int(voxels[VoxMesher.cell_index(x, y, z, size.x, size.z)])
				if slot == 0: continue
				for face in faces:
					var n: Vector3i = face[0]
					var nx := x + n.x; var ny := y + n.y; var nz := z + n.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < size.x and ny < size.y and nz < size.z and voxels[VoxMesher.cell_index(nx, ny, nz, size.x, size.z)] != 0: continue
					var base := Vector3(x, y, z) + (Vector3(n) if n.x + n.y + n.z > 0 else Vector3.ZERO)
					var u := Vector3(face[1]); var v := Vector3(face[2])
					var c := [base, base + u, base + u + v, base + v]
					for corner in [0, 2, 1, 0, 3, 2]:
						vertices.append(c[corner] / density); normals.append(Vector3(n))
						colours.append(Color(1, 0, 0, slot / 255.0)); uv.append(Vector2(slot, slot) / 255.0); uv2.append(Vector2(slot / 255.0, 0))
						custom.append(n.x); custom.append(n.y); custom.append(n.z); custom.append(1.0)
	if vertices.is_empty(): return []
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uv; arrays[Mesh.ARRAY_TEX_UV2] = uv2; arrays[Mesh.ARRAY_CUSTOM0] = custom
	attach_edge_frame(arrays, vertices, normals)
	return arrays



## Convex-edge data for a non-indexed triangle list. CUSTOM1.xyz is the interpolated distance (model
## units) to the triangle's three edges, counted only for convex edges of the solid (flat interior and
## concave edges read 1e6). CUSTOM2.xyz / CUSTOM3.xyz and CUSTOM1.w, CUSTOM2.w, CUSTOM3.w hold the
## neighbouring facet normal across edge 0, 1 and 2 (zero for non-frame edges). The vertex shader turns
## this into a silhouette test: an edge frames the rim only when this facet faces the camera and its
## neighbour faces away, so the rim follows the outline of the shape and never crosses its surface.
static func attach_edge_frame(arrays: Array, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	var tri_count := vertices.size() / 3
	var weld := {}; var welded := PackedInt32Array(); welded.resize(vertices.size())
	for i in vertices.size():
		var key := Vector3i((vertices[i] * 1000.0).round())
		if not weld.has(key): weld[key] = weld.size()
		welded[i] = weld[key]
	var owners := {}
	for t in tri_count:
		for k in 3:
			var a := welded[t * 3 + (k + 1) % 3]; var b := welded[t * 3 + (k + 2) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not owners.has(key): owners[key] = []
			owners[key].append([t, k])
	var c1 := PackedFloat32Array(); c1.resize(vertices.size() * 4)
	var c2 := PackedFloat32Array(); c2.resize(vertices.size() * 4)
	var c3 := PackedFloat32Array(); c3.resize(vertices.size() * 4)
	for t in tri_count:
		var p := [vertices[t * 3], vertices[t * 3 + 1], vertices[t * 3 + 2]]
		var area2: float = ((p[1] - p[0]).cross(p[2] - p[0])).length()
		var n := normals[t * 3]
		var heights := [1.0e6, 1.0e6, 1.0e6]
		var neighbour: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		for k in 3:
			var a := welded[t * 3 + (k + 1) % 3]; var b := welded[t * 3 + (k + 2) % 3]
			var list: Array = owners[Vector2i(mini(a, b), maxi(a, b))]
			var edge_length: float = (p[(k + 1) % 3] - p[(k + 2) % 3]).length()
			var frame := false
			var other_normal := -n
			if list.size() == 2:
				var other: Array = list[0] if list[0][0] != t else list[1]
				other_normal = normals[other[0] * 3]
				if n.dot(other_normal) <= 0.99999:
					# Convex when the neighbour's far corner lies behind this facet's plane.
					var far: Vector3 = vertices[other[0] * 3 + other[1]]
					frame = (far - p[(k + 1) % 3]).dot(n) < -1.0e-5
			else: frame = true
			if frame and edge_length > 1.0e-9:
				heights[k] = area2 / edge_length; neighbour[k] = other_normal
		# Vertex k owns edge k (the opposite one): its distance there is the altitude, 0 on the others.
		for k in 3:
			var i := (t * 3 + k) * 4
			for j in 3:
				c1[i + j] = 1.0e6 if heights[j] >= 1.0e6 else (heights[j] if j == k else 0.0)
			c2[i] = neighbour[0].x; c2[i + 1] = neighbour[0].y; c2[i + 2] = neighbour[0].z
			c3[i] = neighbour[1].x; c3[i + 1] = neighbour[1].y; c3[i + 2] = neighbour[1].z
			c1[i + 3] = neighbour[2].x; c2[i + 3] = neighbour[2].y; c3[i + 3] = neighbour[2].z
	arrays[Mesh.ARRAY_CUSTOM1] = c1; arrays[Mesh.ARRAY_CUSTOM2] = c2; arrays[Mesh.ARRAY_CUSTOM3] = c3
