@tool
extends RefCounted
## Disposable compatibility probe, not a production mesh format or renderer.
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")

static func expanded(code: String) -> String:
	var text := ""
	for line in code.split("\n"):
		text += expanded(FileAccess.get_file_as_string(line.split('"')[1])) + "\n" if line.strip_edges().begins_with("#include ") else line + "\n"
	return text

static func material(original: ShaderMaterial) -> ShaderMaterial:
	var result: ShaderMaterial = original.duplicate()
	var shader := Shader.new()
	# CUSTOM0.w is not read by the normal/edge renderer. Preserve the other 15 components.
	shader.code = expanded(original.shader.code).replace("UV2.x", "(mod(CUSTOM0.w,256.0)/255.0)").replace("UV2.y", "floor(CUSTOM0.w/256.0)")
	result.shader = shader
	return result

static func unwrap(source: ArrayMesh, scale: Transform3D, texel: float) -> Dictionary:
	assert(source.get_surface_count() == 1)
	var original := source.surface_get_arrays(0)
	var n: int = original[Mesh.ARRAY_VERTEX].size()
	var input: Array = original.duplicate(true)
	var ids := PackedColorArray()
	for i in n:
		ids.append(Color(float(i & 255)/255.0,float((i>>8)&255)/255.0,float((i>>16)&255)/255.0,1.0))
	input[Mesh.ARRAY_COLOR] = ids
	# The stock unwrap does not forward custom channels. Retain original vertex IDs in COLOR.
	for channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:input[channel]=null
	var wrapped := ArrayMesh.new()
	wrapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,input)
	var started := Time.get_ticks_usec()
	var error := wrapped.lightmap_unwrap(scale,texel)
	if error != OK:return {"error":error}
	var mapped := wrapped.surface_get_arrays(0)
	var remap: Array[int] = []
	for color: Color in mapped[Mesh.ARRAY_COLOR]:
		remap.append(roundi(color.r*255.0)+(roundi(color.g*255.0)<<8)+(roundi(color.b*255.0)<<16))
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:
		var values: Variant = original[channel]
		if values == null or values.is_empty():continue
		if values is PackedByteArray:values=values.to_float32_array()
		var stride := 4 if channel == Mesh.ARRAY_TANGENT or channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3] else 1
		var restored: Variant = values.duplicate()
		restored.resize(remap.size()*stride)
		for i in remap.size():
			for j in stride:restored[i*stride+j]=values[remap[i]*stride+j]
		output[channel]=restored
	output[Mesh.ARRAY_INDEX]=mapped[Mesh.ARRAY_INDEX]
	output[Mesh.ARRAY_TEX_UV2]=mapped[Mesh.ARRAY_TEX_UV2]
	var custom: PackedFloat32Array = output[Mesh.ARRAY_CUSTOM0] if output[Mesh.ARRAY_CUSTOM0] != null else PackedFloat32Array()
	custom.resize(remap.size()*4)
	for i in remap.size():
		var old: Vector2 = original[Mesh.ARRAY_TEX_UV2][remap[i]]
		assert(old.y == roundf(old.y) and old.y >= 0 and old.y < 65536)
		custom[i*4+3]=roundf(old.x*255.0)+old.y*256.0
	output[Mesh.ARRAY_CUSTOM0]=custom
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,output,[],{},Solid.CUSTOM_FORMAT)
	result.lightmap_size_hint=wrapped.lightmap_size_hint
	result.surface_set_name(0,source.surface_get_name(0))
	for name in source.get_meta_list():result.set_meta(name,source.get_meta(name))
	var old_triangles: int = original[Mesh.ARRAY_INDEX].size()/3 if original[Mesh.ARRAY_INDEX] != null and not original[Mesh.ARRAY_INDEX].is_empty() else n/3
	return {"error":OK,"mesh":result,"vertices_before":n,"vertices_after":remap.size(),"triangles_before":old_triangles,"triangles_after":output[Mesh.ARRAY_INDEX].size()/3,"unwrap_ms":float(Time.get_ticks_usec()-started)/1000.0,"lightmap_hint":str(result.lightmap_size_hint),"lods_dropped_by_stock_unwrap":not source.get("_surfaces")[0].get("lods",{}).is_empty()}

static func rebuild_lods(source: ArrayMesh) -> Dictionary:
	var arrays:=source.surface_get_arrays(0)
	var custom:Variant=arrays[Mesh.ARRAY_CUSTOM0]
	if custom is PackedByteArray:custom=custom.to_float32_array()
	var importer:=ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},null,"",source.surface_get_format(0))
	importer.generate_lods(60.0,0.0,[])
	var generated:=importer.get_mesh()
	var generated_arrays:=generated.surface_get_arrays(0)
	for channel in Mesh.ARRAY_MAX:
		if channel not in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT] and arrays[channel]!=generated_arrays[channel]:
			return {"mesh":source,"levels":0,"triangles":[],"vertex_bytes_unchanged":false,"error":"native generation changed vertex IDs/attributes"}
	var next:Array=source.get("_surfaces").duplicate(true)
	var all_lods:Array=generated.get("_surfaces")[0].get("lods",[])
	var accepted:Array=[];var triangles:Array=[]
	for level in importer.get_surface_lod_count(0):
		var indices:=importer.get_surface_lod_indices(0,level)
		var valid:=true
		for i in range(0,indices.size(),3):
			var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
			# Repacked palette/face IDs must stay flat; native UV2 now owns the bake atlas.
			if arrays[Mesh.ARRAY_TEX_UV][a]!=arrays[Mesh.ARRAY_TEX_UV][b] or arrays[Mesh.ARRAY_TEX_UV][a]!=arrays[Mesh.ARRAY_TEX_UV][c] or custom[a*4+3]!=custom[b*4+3] or custom[a*4+3]!=custom[c*4+3]:valid=false;break
		if valid:
			accepted.append(all_lods[level*2]);accepted.append(all_lods[level*2+1]);triangles.append(indices.size()/3)
	next[0].lods=accepted
	var mesh:=ArrayMesh.new();mesh.set("_surfaces",next);mesh.lightmap_size_hint=source.lightmap_size_hint
	for key in source.get_meta_list():mesh.set_meta(key,source.get_meta(key))
	return {"mesh":mesh,"levels":accepted.size()/2,"triangles":triangles,"vertex_bytes_unchanged":next[0].get("vertex_data")==source.get("_surfaces")[0].get("vertex_data") and next[0].get("attribute_data")==source.get("_surfaces")[0].get("attribute_data")}
