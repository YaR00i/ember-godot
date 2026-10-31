@tool
extends RefCounted
## Derived look bake, never a Source or a second tree generator. All sites,
## alpha artwork and pigment come from the accepted published tree layout.
const Surface=preload("res://scripts/ember_tree_surface.gd")
const Bark=preload("res://scripts/ember_tree_bark_surface.gd")
const Species=preload("res://scripts/ember_tree_species.gd")
const Geometry=preload("res://scripts/ember_tree_surface_geometry.gd")
const LeafShape=preload("res://scripts/ember_leaf_shape_mask.gd")
const CacheStorage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const CACHE_ROOT := "user://ember-tree-look-cache"
const CACHE_VERSION := 1
static var cache_directory := CACHE_ROOT
static var _ready_meshes: Dictionary = {}
static var _prepared_sources:Dictionary={}
static var _filesystem_hooked:=false
static var builds := 0
static var disk_hits := 0
static var _anomaly_meshes: Dictionary = {}
const CONTRACT:="oak-looks-study-v1"
const DIRECTIONS: Array[Vector3i]=[Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.BACK,Vector3i.FORWARD]


## Local fields keep closed wood topology; existing cards shrink into their
## authored anchors while the already baked voxel leaves grow as whole cells.
static func anomaly_meshes(model: Dictionary, detailed: ArrayMesh, voxel: ArrayMesh, host: Node) -> Dictionary:
	var key := CacheStorage.digest(["tree-anomaly-1",Engine.get_version_info().hex,model,detailed.surface_get_arrays(0),detailed.surface_get_arrays(1),voxel.surface_get_arrays(0),voxel.surface_get_arrays(1)])
	if _anomaly_meshes.has(key): return _anomaly_meshes[key]
	var cache := CacheStorage.new()
	cache.directory = "user://ember-anomaly-cache"
	cache.max_bytes = 128*1024*1024
	var saved := cache.read(key)
	if saved.get("tree_carriers") is Array and saved.tree_carriers.size() == 3:
		var restored: Dictionary = {}
		for i in 3:
			var mesh := ArrayMesh.new(); mesh.set("_surfaces",saved.tree_carriers[i])
			restored[["base","target","cells"][i]] = mesh
		restored.cells.surface_set_material(0,voxel.surface_get_material(1))
		if _anomaly_meshes.size() >= 8: _anomaly_meshes.erase(_anomaly_meshes.keys()[0])
		_anomaly_meshes[key] = restored
		return restored
	var correspondence = load("res://scripts/ember_anomaly_correspondence.gd")
	var wood := await correspondence.carrier(correspondence.surface_mesh(detailed,0),correspondence.surface_mesh(voxel,0),host) as ArrayMesh
	if wood == null: return {}
	var base := ArrayMesh.new(); correspondence.append_surface(base,wood,0); correspondence.append_surface(base,detailed,1)
	var target := ArrayMesh.new(); correspondence.append_surface(target,voxel,0)
	var arrays := detailed.surface_get_arrays(1)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var layout := Surface.leaf_layout(model)
	var roots: Array = layout.roots
	for index in roots.size():
		# Geometry's reference vertex is base+7 (the shoot attachment), not
		# the first vertex. Keep all twelve indexed vertices on one anchor.
		var begin := int(roots[index].vertex)-7
		var end := int(roots[index+1].vertex)-7 if index+1 < roots.size() else points.size()
		for i in range(begin,end): points[i] = roots[index].patch.anchor
	arrays[Mesh.ARRAY_VERTEX] = points
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},detailed.surface_get_format(1))
	var cells: ArrayMesh = correspondence.surface_mesh(voxel,1)
	var payload: Array = []
	for mesh: ArrayMesh in [base,target,cells]:
		var surfaces: Array = mesh.get("_surfaces").duplicate(true)
		for surface: Dictionary in surfaces: surface.erase("material")
		payload.append(surfaces)
	cache.write(key,{"tree_carriers":payload},func(): return not host.anomaly_preparation_valid())
	cache.trim(256*1024*1024)
	var result := {"base":base,"target":target,"cells":cells}
	if _anomaly_meshes.size() >= 8: _anomaly_meshes.erase(_anomaly_meshes.keys()[0])
	_anomaly_meshes[key] = result
	return result

static func cache_key(model: Dictionary, look: int) -> String:
	var kind: int = model.treeSurface.settings.tree_type
	var dependencies := []
	for path in ["res://scripts/ember_tree_look_bake.gd", "res://scripts/ember_tree_surface.gd",
		"res://scripts/ember_tree_surface_geometry.gd", "res://scripts/ember_tree_rounded_geometry.gd",
		"res://scripts/ember_tree_bark_surface.gd", "res://scripts/ember_tree_species.gd",
		"res://scripts/ember_leaf_shape_mask.gd", "res://scripts/vox_mesher.gd",
		"res://scripts/ember_voxel_material_profiles.gd", Surface.LEAF_BASE,
		Species.LEAF_ART[kind], Species.BARK_ART[kind]]:
		dependencies.append(FileAccess.get_sha256(path))
	return CacheStorage.digest([CACHE_VERSION, Engine.get_version_info().hex, look, model, dependencies])

static func _forget_source(id:int)->void:
	_prepared_sources.erase(id)

static func _forget_sources()->void:
	_prepared_sources.clear()

static func _watch_editor_sources()->void:
	if _filesystem_hooked or not Engine.is_editor_hint():return
	var editor:=Engine.get_singleton("EditorInterface")
	if editor==null:return
	var filesystem:Object=editor.call("get_resource_filesystem")
	if filesystem!=null:
		if not filesystem.is_connected("filesystem_changed",_forget_sources):filesystem.connect("filesystem_changed",_forget_sources)
		_filesystem_hooked=true

static func prepare(source: EmberVoxelModelResource, smooth: ArrayMesh) -> Dictionary:
	# Prepare when the map acquires its initial tree presentation, never in
	# the first interactive switch. Repeated instances share the same bake.
	_watch_editor_sources()
	var id:=source.get_instance_id()
	if _prepared_sources.has(id):
		var alive:Dictionary={}
		for look in _prepared_sources[id].meshes:
			var mesh:=(_prepared_sources[id].meshes[look] as WeakRef).get_ref() as ArrayMesh
			if mesh!=null:alive[look]=mesh
		if alive.size()==2:return alive
	var model: Dictionary = source.to_definition(true).model
	var result := {}
	for look in [1, 2]:
		var key := cache_key(model, look)
		var prepared:ArrayMesh=(_ready_meshes[key] as WeakRef).get_ref() as ArrayMesh if _ready_meshes.has(key) else null
		if prepared==null:
			var disk := CacheStorage.new()
			disk.directory = cache_directory
			disk.max_bytes = 128 * 1024 * 1024
			var saved := disk.read(key)
			var geometry: Dictionary
			if saved.get("version") == CACHE_VERSION and _valid_geometry(saved.get("geometry")):
				geometry = saved.geometry
				disk_hits += 1
			else:
				var atlas := artwork_image(Species.LEAF_ART[int(model.treeSurface.settings.tree_type)])
				var built: Dictionary = build_faceted(model, null, atlas, true) if look == 1 else build(model, 0.0625, null, atlas, true)
				geometry = built.geometry
				disk.write(key, {"version": CACHE_VERSION, "geometry": geometry}, func(): return false)
				disk.trim()
				builds += 1
			if _ready_meshes.size() >= 8: _ready_meshes.erase(_ready_meshes.keys()[0])
			prepared=publish_geometry(geometry, smooth, model, look)
			_ready_meshes[key] = weakref(prepared)
		# Geometry is immutable and shared. Instance lighting belongs to surface
		# overrides, not a second GPU allocation of every prepared tree look.
		result[look] = prepared
	# Resource.changed is the existing authoring invalidation boundary. Keep
	# four model sources (the same eight look entries), not a hash/copy per tree.
	if _prepared_sources.size()>=4:_prepared_sources.erase(_prepared_sources.keys()[0])
	# Live props own carriers; the disk cache covers later returns. Weak entries
	# preserve sharing without pinning inactive worlds after their last user.
	_prepared_sources[id]={"source":source,"smooth":smooth,"meshes":{1:weakref(result[1]),2:weakref(result[2])}}
	var invalidate:=_forget_source.bind(id)
	if not source.changed.is_connected(invalidate):source.changed.connect(invalidate)
	if not smooth.changed.is_connected(invalidate):smooth.changed.connect(invalidate)
	return result

static func _valid_geometry(value: Variant) -> bool:
	if not value is Dictionary or not value.get("wood") is Array or not value.get("leaves") is Array: return false
	if value.wood.size() != 1 or value.leaves.size() > 1: return false
	for surface in value.wood + value.leaves:
		if not surface is Dictionary or not surface.get("vertex_data") is PackedByteArray or int(surface.get("vertex_count", 0)) <= 0: return false
	return value.get("mask", {}) is Dictionary

static func pack_geometry(wood: ArrayMesh, leaves: ArrayMesh, mask: Image = null) -> Dictionary:
	return {"wood": wood.get("_surfaces"), "leaves": leaves.get("_surfaces"),
		"mask": {} if mask == null else {"width": mask.get_width(), "height": mask.get_height(),
			"mips": mask.has_mipmaps(), "format": mask.get_format(), "bytes": mask.get_data()}}

static func publish_geometry(data: Dictionary, smooth: ArrayMesh, model: Dictionary, look: int) -> ArrayMesh:
	var wood := ArrayMesh.new(); wood.set("_surfaces", data.wood)
	var leaves := ArrayMesh.new(); leaves.set("_surfaces", data.leaves)
	var result := ArrayMesh.new()
	var bark_material := smooth.surface_get_material(0).duplicate() as ShaderMaterial
	bark_material.set_shader_parameter("painted_bark_pixel_m", 0.0 if look == 1 else 1.0 / 16.0)
	Surface.append_surface(result, wood, "tree_bark", bark_material)
	if leaves.get_surface_count() > 0:
		var material := smooth.surface_get_material(1).duplicate() as ShaderMaterial
		material.shader = load("res://shaders/ember_tree_faceted_leaves.gdshader" if look == 1 else "res://shaders/ember_tree_voxel_leaves.gdshader")
		if look == 1:
			var mask: Dictionary = data.mask
			var image := Image.create_from_data(mask.width, mask.height, mask.mips, mask.format, mask.bytes)
			material.set_shader_parameter("faceted_leaf_shape", ImageTexture.create_from_image(image))
			material.set_shader_parameter("faceted_leaf_shape_amount", 0.0)
		Surface.append_surface(result, leaves, "tree_leaves", material)
	Surface.apply_materials(result, model.get("material", {}))
	if look == 2: result.set_meta("tree_surface_contract", CONTRACT)
	return result

static func artwork_image(path: String) -> Image:
	var image := (load(path) as Texture2D).get_image().duplicate() as Image
	if image.is_compressed(): image.decompress()
	return image

static func build(model: Dictionary,cell_m:=0.0625,prepared_smooth: ArrayMesh=null,prepared_atlas: Image=null,geometry_only:=false) -> Dictionary:
	assert(Surface.active(model))
	assert(cell_m in [0.0625,0.125])
	var started:=Time.get_ticks_usec()
	var smooth: ArrayMesh = null if geometry_only else prepared_smooth if prepared_smooth!=null else Surface.build(model)
	var layout:=Surface.leaf_layout(model)
	var data: Dictionary=model.treeSurface
	var atlas:=prepared_atlas if prepared_atlas!=null else artwork_image(Species.LEAF_ART[int(data.settings.tree_type)])
	var cells: Dictionary={};var puffs: Dictionary={}
	var arrays: Array=layout.mesh.surface_get_arrays(0) if layout.cards>0 else []
	for root: Dictionary in layout.roots:
		puffs[Geometry._crown_site_key(root)]=true
		var patch: Dictionary=root.patch
		var vertex:=int(root.vertex)
		var macro:=Vector3(arrays[Mesh.ARRAY_CUSTOM1][vertex*4],arrays[Mesh.ARRAY_CUSTOM1][vertex*4+1],arrays[Mesh.ARRAY_CUSTOM1][vertex*4+2])
		var nu:=maxi(2,ceili(float(patch.width)/(cell_m*0.45)))
		var nv:=maxi(2,ceili(float(patch.height)/(cell_m*0.45)))
		var patch_cells: Dictionary={}
		for y in nv:
			for x in nu:
				var uv:=Vector2((x+0.5)/nu,(y+0.5)/nv)
				var tex_uv: Vector2=(Vector2(int(patch.tile)%2,int(patch.tile)/2)+uv)*0.5
				var pixel:=atlas.get_pixel(clampi(int(tex_uv.x*atlas.get_width()),0,atlas.get_width()-1),clampi(int(tex_uv.y*atlas.get_height()),0,atlas.get_height()-1))
				var warp: float=sin(PI*uv.x)*sin(PI*uv.y)*patch.width*0.16-sin(PI*0.94)*patch.width*0.16
				var point: Vector3=patch.anchor+patch.side*(uv.x-0.5)*patch.width+patch.forward*(0.94-uv.y)*patch.height+patch.normal*warp
				# Small physical-looking thickness, decorative only. Shared cells are
				# unioned; hidden internal faces are never emitted.
				for depth in [-0.22,0.0,0.22]:
					var cell:=Vector3i(((point+patch.normal*cell_m*depth)/cell_m).floor())
					if not patch_cells.has(cell):patch_cells[cell]={"total":0,"covered":0,"uv":tex_uv}
					patch_cells[cell].total+=1
					if pixel.a>=0.40:
						patch_cells[cell].covered+=1;patch_cells[cell].uv=tex_uv
		# Coverage of the original patch, not "one tiny leaf touched the cell".
		# This avoids inflating every transparent atlas gap into a solid square.
		for cell: Vector3i in patch_cells:
			var coverage: Dictionary=patch_cells[cell]
			if float(coverage.covered)/coverage.total<0.4:continue
			if not cells.has(cell):cells[cell]={"uv":coverage.uv,"normal":macro,"owner":patch.owner,"pigment":arrays[Mesh.ARRAY_COLOR][vertex]}
	var leaves:=leaf_mesh(cells,cell_m)
	var wood:=wood_mesh(model)
	var geometry := pack_geometry(wood, leaves)
	if geometry_only: return {"geometry": geometry}
	var result := publish_geometry(geometry, smooth, model, 2)
	return {"mesh":result,"cells":cells.size(),"cell_m":cell_m,"puffs":puffs.keys(),"cards":layout.cards,
		"build_ms":(Time.get_ticks_usec()-started)/1000.0,"triangles":result.get_faces().size()/3}

static func wood_mesh(model: Dictionary) -> ArrayMesh:
	var data: Dictionary=model.treeSurface
	var reference:=model.duplicate(true)
	reference.voxels=data.paint_indices.decompress(PackedByteArray(model.voxels).size(),FileAccess.COMPRESSION_ZSTD)
	reference.palette=[]
	for colour: Color in data.paint_palette:reference.palette.append(colour.to_html(false))
	var raw:=VoxMesher.build_from_ember_model(reference,1.0/16.0)
	var size:=VoxMesher.ember_grid_size(model)
	var centre:=Vector3(size.x/2,0,size.z/2)/16.0
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in raw.get_surface_count():
		var a:=raw.surface_get_arrays(surface)
		for index in a[Mesh.ARRAY_INDEX]:
			st.set_normal(a[Mesh.ARRAY_NORMAL][index]);st.set_color(a[Mesh.ARRAY_COLOR][index])
			st.add_vertex(a[Mesh.ARRAY_VERTEX][index]-centre)
	var mapped:=Bark.mesh(st.commit(),data.structure,data.pivot)
	if PackedByteArray(model.voxels).hex_encode().sha256_text()!=str(data.paint_hash) or Surface.palette_changed(VoxMesher._model_colors(model),data.paint_palette):
		mapped=Surface.painted_wood(mapped,model,data)
	return mapped

static func build_faceted(model: Dictionary,prepared_smooth: ArrayMesh=null,prepared_atlas: Image=null,geometry_only:=false) -> Dictionary:
	# Same published branch paths and retained leaf sites; no voxel round-trip.
	var started:=Time.get_ticks_usec()
	var data: Dictionary=model.treeSurface
	var offset:=Vector3(data.pivot.x,0,data.pivot.y)
	var raw:=Geometry.wood_mesh(Geometry.branches(data.structure),offset,16.0,6)
	var faces:=raw.get_faces();var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a:=raw.surface_get_arrays(0)
	for i in range(0,faces.size(),3):
		var n: Vector3=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
		if n.dot(a[Mesh.ARRAY_NORMAL][i])<0:n=-n
		for j in 3:
			st.set_normal(n);st.set_color(Color("916044"));st.add_vertex(faces[i+j])
	var wood:=Bark.mesh(st.commit(),data.structure,data.pivot)
	if PackedByteArray(model.voxels).hex_encode().sha256_text()!=str(data.paint_hash) or Surface.palette_changed(VoxMesher._model_colors(model),data.paint_palette):
		wood=Surface.painted_wood(wood,model,data)
	var layout:=Surface.leaf_layout(model);var leaves:=faceted_leaves(layout)
	var smooth: ArrayMesh = null if geometry_only else prepared_smooth if prepared_smooth!=null else Surface.build(model)
	var atlas := prepared_atlas if prepared_atlas != null else artwork_image(Species.LEAF_ART[int(data.settings.tree_type)])
	var mask: Image = LeafShape.build(atlas).image if leaves.get_surface_count() > 0 else null
	var geometry := pack_geometry(wood, leaves, mask)
	if geometry_only: return {"geometry": geometry}
	var result := publish_geometry(geometry, smooth, model, 1)
	var puffs: Dictionary={}
	for root: Dictionary in layout.roots:puffs[Geometry._crown_site_key(root)]=true
	return {"mesh":result,"cells":0,"cards":layout.cards,"puffs":puffs.keys(),"triangles":result.get_faces().size()/3,"build_ms":(Time.get_ticks_usec()-started)/1000.0}

static func faceted_leaves(layout: Dictionary) -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	if layout.cards==0:return mesh
	var source: Array=layout.mesh.surface_get_arrays(0)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colours:=PackedColorArray()
	var uv:=PackedVector2Array();var roles:=PackedFloat32Array();var macro:=PackedFloat32Array()
	var role: Vector4=Geometry.Profiles.PROFILES.foliage
	var ring: Array[Vector2]=[Vector2(0.5,0),Vector2(1,0.5),Vector2(0.5,1),Vector2(0,0.5)]
	for root: Dictionary in layout.roots:
		var p: Dictionary=root.patch;var vertex:=int(root.vertex)
		var group:=Vector3(source[Mesh.ARRAY_CUSTOM1][vertex*4],source[Mesh.ARRAY_CUSTOM1][vertex*4+1],source[Mesh.ARRAY_CUSTOM1][vertex*4+2])
		for side in [-1.0,1.0]:
			for i in 4:
				var coords: Array[Vector2]=[Vector2(0.5,0.5),ring[i],ring[(i+1)%4]]
				var points: Array[Vector3]=[]
				for j in 3:
					var q:=coords[j]
					points.append(p.anchor+p.side*(q.x-0.5)*p.width+p.forward*(0.94-q.y)*p.height+p.normal*(side*p.width*0.12 if j==0 else 0.0))
				var n: Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
				if n.dot(p.normal)*side<0:n=-n
				var light_normal: Vector3=(group*0.75+n*0.25).normalized()
				for j in 3:
					vertices.append(points[j]);normals.append(n);colours.append(source[Mesh.ARRAY_COLOR][vertex])
					uv.append((Vector2(int(p.tile)%2,int(p.tile)/2)+coords[j].clamp(Vector2.ONE*0.002,Vector2.ONE*0.998))*0.5)
					roles.append_array(PackedFloat32Array([role.x,role.y,role.z,0]))
					macro.append_array(PackedFloat32Array([light_normal.x,light_normal.y,light_normal.z,float(p.owner)]))
	var a:=[];a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=vertices;a[Mesh.ARRAY_NORMAL]=normals;a[Mesh.ARRAY_COLOR]=colours;a[Mesh.ARRAY_TEX_UV]=uv
	a[Mesh.ARRAY_CUSTOM0]=roles;a[Mesh.ARRAY_CUSTOM1]=macro
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return mesh

static func leaf_mesh(cells: Dictionary,step: float) -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	if cells.is_empty():return mesh
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colours:=PackedColorArray()
	var uv:=PackedVector2Array();var custom:=PackedFloat32Array();var macro:=PackedFloat32Array();var form:=PackedFloat32Array()
	var role: Vector4=Geometry.Profiles.PROFILES.foliage
	for cell: Vector3i in cells:
		var sample: Dictionary=cells[cell]
		for direction: Vector3i in DIRECTIONS:
			if cells.has(cell+direction):continue
			var n:=Vector3(direction)
			var u:=Vector3.UP if direction.y==0 else Vector3.RIGHT
			var v:=n.cross(u)
			var centre: Vector3=(Vector3(cell)+Vector3.ONE*0.5+n*0.5)*step
			var points: Array[Vector3]=[centre+(-u-v)*step*0.5,centre+(u-v)*step*0.5,centre+(u+v)*step*0.5,centre+(-u+v)*step*0.5]
			# Godot front faces are clockwise. Each cell has constant pigment and
			# a discrete lighting normal; the accepted light bands/rim stay shared.
			var light_normal: Vector3=(n*0.65+sample.normal*0.35).normalized()
			for corner in [0,2,1,0,3,2]:
				vertices.append(points[corner]);normals.append(n);colours.append(sample.pigment);uv.append(sample.uv)
				custom.append_array(PackedFloat32Array([role.x,role.y,role.z,0.0]))
				macro.append_array(PackedFloat32Array([light_normal.x,light_normal.y,light_normal.z,float(sample.owner)]))
				form.append_array(PackedFloat32Array([sample.normal.x,sample.normal.y,sample.normal.z,0]))
	var a:=[];a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=vertices;a[Mesh.ARRAY_NORMAL]=normals;a[Mesh.ARRAY_COLOR]=colours;a[Mesh.ARRAY_TEX_UV]=uv
	a[Mesh.ARRAY_CUSTOM0]=custom;a[Mesh.ARRAY_CUSTOM1]=macro
	a[Mesh.ARRAY_CUSTOM2]=form
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
	return mesh
