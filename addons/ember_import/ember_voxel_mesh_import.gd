extends RefCounted
## Bounded authoring preparation. No source assets are written by plan().
const External=preload("res://scripts/ember_external_mesh_surface.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const MAX_TRIANGLES:=20000
const MAX_CELLS:=262144

static func plan(path:String, model_id:String, previous:EmberVoxelModelResource=null)->Dictionary:
	if not model_id.is_valid_identifier():return {"error":"Некорректный ID модели."}
	if previous!=null and previous.external_surface.is_empty():return {"error":"Этот ID уже занят нативным воксельным объектом."}
	if previous!=null and not External.can_reprepare(previous):return {"error":"Модель изменена лепкой или покраской. Повторная подготовка не заменяет ручные правки."}
	if path.get_extension().to_lower()!="glb":return {"error":"Первый импорт поддерживает один статичный GLB."}
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var code:=document.append_from_file(path,state)
	if code!=OK:return {"error":"Не удалось прочитать GLB: "+error_string(code)}
	var scene:=document.generate_scene(state)
	if scene==null:return {"error":"GLB не создал сцену."}
	var candidates:Array[MeshInstance3D]=[]
	for node in scene.find_children("*","MeshInstance3D",true,false):candidates.append(node)
	if scene is MeshInstance3D:candidates.append(scene)
	if candidates.size()!=1 or candidates[0].skin!=null or candidates[0].mesh.get_blend_shape_count()>0:
		scene.free();return {"error":"Для первого среза нужен один статичный меш без skin/blend shapes."}
	var instance:MeshInstance3D=candidates[0];var source_mesh:Mesh=instance.mesh
	var transform:=instance.transform;var parent:=instance.get_parent()
	while parent!=null and parent!=scene.get_parent():
		transform=parent.transform*transform if parent is Node3D else transform;parent=parent.get_parent()
	if source_mesh.get_surface_count()!=1:scene.free();return {"error":"Первый срез поддерживает одну поверхность с одним материалом."}
	var bounds:=transform*source_mesh.get_aabb()
	if bounds.size.x<=0.01 or bounds.size.y<=0.01 or bounds.size.z<=0.01 or bounds.size.length()>8.0:
		scene.free();return {"error":"Нужен объёмный предмет до8м в метрическом масштабе."}
	var density:=16
	var grid:=Vector3i(ceili((bounds.size.x+0.125))*density,ceili(bounds.size.y*density)+1,ceili(bounds.size.z+0.125)*density)
	if grid.x*grid.y*grid.z>MAX_CELLS:scene.free();return {"error":"Предмет превышает бюджет первого импорта."}
	var offset:=Vector3(float(grid.x)/density*0.5-bounds.get_center().x,-bounds.position.y,float(grid.z)/density*0.5-bounds.get_center().z)
	var detailed:=ArrayMesh.new();var low:=ArrayMesh.new();var triangles:Array[Dictionary]=[]
	for surface in source_mesh.get_surface_count():
		if source_mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:scene.free();return {"error":"Поддерживаются треугольные поверхности."}
		var arrays:=source_mesh.surface_get_arrays(surface).duplicate(true)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():vertices[i]=transform*vertices[i]+offset
		for i in normals.size():normals[i]=(transform.basis.inverse().transposed()*normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in indices.size():indices[i]=i
			arrays[Mesh.ARRAY_INDEX]=indices
		if triangles.size()+indices.size()/3>MAX_TRIANGLES:scene.free();return {"error":"Слишком много треугольников."}
		var mat:=source_mesh.surface_get_material(surface)
		if not mat is StandardMaterial3D:scene.free();return {"error":"Первый импорт сохраняет StandardMaterial3D."}
		detailed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);detailed.surface_set_material(surface,mat)
		# Existing Godot meshoptimizer path. Select an explicit representation, not distance LOD.
		var importer:=ImporterMesh.new();importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mat)
		importer.generate_lods(91.0,0.0,[])
		var selected:=indices
		for level in importer.get_surface_lod_count(0):
			var candidate:=importer.get_surface_lod_indices(0,level)
			if candidate.size()>=maxi(36,indices.size()/5):selected=candidate
		var coarse:=arrays.duplicate(true);coarse[Mesh.ARRAY_INDEX]=selected
		var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		for t in range(0,selected.size(),3):
			var n:Vector3=(vertices[selected[t+1]]-vertices[selected[t]]).cross(vertices[selected[t+2]]-vertices[selected[t]]).normalized()
			if normals.size()==vertices.size() and n.dot(normals[selected[t]]+normals[selected[t+1]]+normals[selected[t+2]])<0.0:n=-n
			for k in 3:
				tool.set_normal(n)
				if uvs.size()==vertices.size():tool.set_uv(uvs[selected[t+k]])
				tool.add_vertex(vertices[selected[t+k]])
		var flat:=tool.commit();low.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,flat.surface_get_arrays(0));low.surface_set_material(surface,mat)

		var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var image:Image=mat.albedo_texture.get_image() if mat.albedo_texture!=null else null
		if image!=null and image.is_compressed():image.decompress()
		for i in range(0,indices.size(),3):
			var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
			triangles.append({"a":vertices[a],"b":vertices[b],"c":vertices[c],"uv":PackedVector2Array([uv[a],uv[b],uv[c]]) if uv.size()==vertices.size() else PackedVector2Array(),"color":mat.albedo_color,"image":image})
	if triangles.size()>MAX_TRIANGLES:scene.free();return {"error":"Слишком много треугольников для первого среза."}
	var source:=EmberVoxelModelResource.new();source.model_id=model_id;source.display_name="Внешний прибрежный камень"
	source.size_blocks=Vector3i(grid.x/density,ceili(float(grid.y)/density),grid.z/density);source.height_voxels=grid.y
	source.palette=PackedColorArray([Color.TRANSPARENT]);source.voxels.resize(grid.x*grid.y*grid.z);source.voxel_part_ids.resize(source.voxels.size())
	source.merge_parts=PackedStringArray(["Импортированный объём"]);source.tags=PackedStringArray(["imported","rock","environment"])
	var palette:Dictionary={};var odd_rows:=0
	# Even-odd closed-mesh fill, bounded by Y/Z triangle bins. Supports side recesses.
	var bins:Dictionary={};var references:=0
	for triangle in triangles:
		var lo:Vector3=triangle.a.min(triangle.b).min(triangle.c);var hi:Vector3=triangle.a.max(triangle.b).max(triangle.c)
		for z in range(maxi(0,floori(lo.z*density)),mini(grid.z,ceili(hi.z*density)+1)):
			for y in range(maxi(0,floori(lo.y*density)),mini(grid.y,ceili(hi.y*density)+1)):
				var key:=Vector2i(y,z)
				if not bins.has(key):bins[key]=[]
				bins[key].append(triangle);references+=1
				if references>2000000:scene.free();return {"error":"Слишком сложная пространственная разбивка."}
	for key:Vector2i in bins:
		var ray:=Vector3(-1,(key.x+0.5)/density,(key.y+0.5)/density);var hits:Array[Dictionary]=[]
		for triangle:Dictionary in bins[key]:
			var point:Variant=Geometry3D.ray_intersects_triangle(ray,Vector3.RIGHT,triangle.a,triangle.b,triangle.c)
			if point!=null:hits.append({"x":point.x,"point":point,"triangle":triangle})
		hits.sort_custom(func(a,b):return a.x<b.x)
		var unique:Array[Dictionary]=[]
		for hit in hits:
			if unique.is_empty() or absf(unique[-1].x-hit.x)>0.00001:unique.append(hit)
		if unique.size()%2!=0:odd_rows+=1;continue
		for h in range(0,unique.size(),2):
			for x in range(maxi(0,ceili(unique[h].x*density-0.5)),mini(grid.x,ceili(unique[h+1].x*density-0.5))):
				var near:Dictionary=unique[h] if absf((x+0.5)/density-unique[h].x)<absf((x+0.5)/density-unique[h+1].x) else unique[h+1]
				var color:=_hit_color(near)
				var rgb:=Vector3i(roundi(color.r*31),roundi(color.g*31),roundi(color.b*31))
				if not palette.has(rgb):
					if source.palette.size()<256:palette[rgb]=source.palette.size();source.palette.append(Color(rgb.x/31.0,rgb.y/31.0,rgb.z/31.0))
					else:palette[rgb]=_closest(source.palette,color)
				var index:=VoxMesher.cell_index(x,key.x,key.y,grid.x,grid.z)
				source.voxels[index]=palette[rgb];source.voxel_part_ids[index]=1
	scene.free()
	if odd_rows>0:return {"error":"Незамкнутый или неоднозначный меш: строк %d."%odd_rows}
	if source.voxels.count(0)==source.voxels.size():return {"error":"Меш не образует объём."}
	var roles:=PackedStringArray();roles.resize(source.palette.size());var ids:=roles.duplicate()
	source.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"occupancy":Solid.occupancy_hash(source.voxels),"roles":roles,"material_ids":ids}
	return {"source":source,"detailed":detailed,"low_poly":low,"original_hash":FileAccess.get_sha256(path),"triangles":triangles.size(),"grid":grid}

static func _hit_color(hit:Dictionary)->Color:
	var triangle:Dictionary=hit.triangle;var color:Color=triangle.color
	if triangle.image==null or triangle.uv.is_empty():return color
	var v0:Vector3=triangle.b-triangle.a;var v1:Vector3=triangle.c-triangle.a;var v2:Vector3=hit.point-triangle.a
	var d00:=v0.dot(v0);var d01:=v0.dot(v1);var d11:=v1.dot(v1);var d20:=v2.dot(v0);var d21:=v2.dot(v1)
	var denominator:=d00*d11-d01*d01
	if absf(denominator)<0.0000001:return color
	var v:float=(d11*d20-d01*d21)/denominator;var w:float=(d00*d21-d01*d20)/denominator
	var uv:Vector2=triangle.uv[0]*(1.0-v-w)+triangle.uv[1]*v+triangle.uv[2]*w
	var image:Image=triangle.image
	return color*image.get_pixel(clampi(int(fposmod(uv.x,1.0)*image.get_width()),0,image.get_width()-1),clampi(int(fposmod(uv.y,1.0)*image.get_height()),0,image.get_height()-1))

static func _closest(palette:PackedColorArray,color:Color)->int:
	var best:=1;var distance:=INF
	for i in range(1,palette.size()):
		var c:=palette[i];var d:=Vector3(c.r-color.r,c.g-color.g,c.b-color.b).length_squared()
		if d<distance:distance=d;best=i
	return best
