extends RefCounted
## Derived look bake, never a Source or a second tree generator. All sites,
## alpha artwork and pigment come from the accepted published tree layout.
const Surface=preload("res://scripts/ember_tree_surface.gd")
const Bark=preload("res://scripts/ember_tree_bark_surface.gd")
const Species=preload("res://scripts/ember_tree_species.gd")
const Geometry=preload("res://scripts/ember_tree_surface_geometry.gd")
const LeafShape=preload("res://scripts/ember_leaf_shape_mask.gd")
static var leaf_shape_cache: Dictionary={}
const CONTRACT:="oak-looks-study-v1"
const DIRECTIONS: Array[Vector3i]=[Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.BACK,Vector3i.FORWARD]

static func build(model: Dictionary,cell_m:=0.0625) -> Dictionary:
	assert(Surface.active(model))
	assert(cell_m in [0.0625,0.125])
	var started:=Time.get_ticks_usec()
	var smooth:=Surface.build(model)
	var layout:=Surface.leaf_layout(model)
	var data: Dictionary=model.treeSurface
	var atlas:=Image.load_from_file(Species.LEAF_ART[int(data.settings.tree_type)])
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
	var result:=ArrayMesh.new()
	var bark_material:=smooth.surface_get_material(0).duplicate() as ShaderMaterial
	bark_material.set_shader_parameter("painted_bark_pixel_m",1.0/16.0)
	Surface.append_surface(result,wood,"tree_bark",bark_material)
	if leaves.get_surface_count()>0:
		var leaf_material:=smooth.surface_get_material(1).duplicate() as ShaderMaterial
		leaf_material.shader=load("res://shaders/ember_tree_voxel_leaves.gdshader")
		Surface.append_surface(result,leaves,"tree_leaves",leaf_material)
	Surface.apply_materials(result,model.get("material",{}))
	result.set_meta("tree_surface_contract",CONTRACT)
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

static func build_faceted(model: Dictionary) -> Dictionary:
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
	var smooth:=Surface.build(model);var result:=ArrayMesh.new()
	Surface.append_surface(result,wood,"tree_bark",smooth.surface_get_material(0).duplicate())
	result.surface_get_material(0).set_shader_parameter("painted_bark_pixel_m",0.0)
	if leaves.get_surface_count()>0:
		var material:=smooth.surface_get_material(1).duplicate() as ShaderMaterial
		material.shader=load("res://shaders/ember_tree_faceted_leaves.gdshader")
		var artwork: String=Species.LEAF_ART[int(data.settings.tree_type)]
		if not leaf_shape_cache.has(artwork):
			var mask:=LeafShape.build(Image.load_from_file(artwork))
			leaf_shape_cache[artwork]=ImageTexture.create_from_image(mask.image)
		material.set_shader_parameter("faceted_leaf_shape",leaf_shape_cache[artwork])
		material.set_shader_parameter("faceted_leaf_shape_amount",0.0)
		Surface.append_surface(result,leaves,"tree_leaves",material)
	Surface.apply_materials(result,model.get("material",{}))
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
