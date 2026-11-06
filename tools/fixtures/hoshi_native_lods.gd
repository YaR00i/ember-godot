extends RefCounted
## Offline native index LOD. The accepted vertex stream, skin and morph data stay authoritative.
static func prepare(source:ArrayMesh)->ArrayMesh:
	if source==null or source.get_blend_shape_count()>0:return source
	var stored:Array=source.get("_surfaces")
	for surface:Dictionary in stored:
		if not surface.get("lods",{}).is_empty():return source
	var importer:=ImporterMesh.new()
	for index in source.get_surface_count():
		if source.surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES:return source
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(index),[],{},source.surface_get_material(index),source.surface_get_name(index),source.surface_get_format(index))
	importer.generate_lods(60.0,0.0,[])
	var generated:=importer.get_mesh()
	if generated==null:return source
	var generated_surfaces:Array=generated.get("_surfaces")
	var next:Array=stored.duplicate(true)
	var levels:=0
	for index in source.get_surface_count():
		var before:=source.surface_get_arrays(index)
		var after:=generated.surface_get_arrays(index)
		# Native re-encoding can quantize normals/tangents a second time. Retain
		# their original packed bytes; indices are reusable only if vertex IDs,
		# positions, UVs, skin weights and the base triangles did not change.
		for channel in Mesh.ARRAY_MAX:
			if channel not in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT] and before[channel]!=after[channel]:return source
		if generated_surfaces[index].has("lods"):
			next[index].lods=generated_surfaces[index].lods
			levels+=importer.get_surface_lod_count(index)
	if levels==0:return source
	var result:=ArrayMesh.new()
	result.set("_surfaces",next)
	result.custom_aabb=source.custom_aabb
	result.resource_name=source.resource_name
	for key in source.get_meta_list():result.set_meta(key,source.get_meta(key))
	result.set_meta("ember_native_character_lod",1)
	return result
