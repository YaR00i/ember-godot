extends RefCounted
## Derived solid-face buffers and material binding. Source and physical geometry stay unchanged.
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Vox=preload("res://scripts/vox_mesher.gd")
const LEAF="res://shaders/ember_solid_material_layers.gdshaderinc"
const MAX_EDGES:=32
static var _prepared:Dictionary={}
static var preparations:=0
static var preparation_usec:=0
static var _runtime_shader:Shader
static var _wear_mask:Texture2D

static func _forget_prepared(key:int)->void:
	_prepared.erase(key)

class PreparationJob extends RefCounted:
	var arrays: Array = []
	var model: Dictionary = {}
	var data: Dictionary = {}
	var builder: Callable
	var stale := false # Main-thread publication guard only.
	var us := 0
	func run() -> void:
		var started := Time.get_ticks_usec()
		data = builder.call(arrays, model)
		us = Time.get_ticks_usec() - started
		arrays = []
		model = {}

static func needs_preparation(source: ArrayMesh) -> bool:
	return not source.has_meta("solid_layer_faces") and not _prepared.has(source.get_instance_id())

static func preparation_job(source: ArrayMesh, model: Dictionary) -> PreparationJob:
	var job := PreparationJob.new()
	job.arrays = source.surface_get_arrays(0).duplicate(true)
	job.model = model
	job.builder = _prepare_data
	return job

## Same bounded CPU cache as the synchronous authoring path. No GPU allocation
## until prepared_mesh is consumed by a prop on the main thread.
static func publish_preparation(source: ArrayMesh, job: PreparationJob) -> void:
	if job.stale or job.data.is_empty(): return
	var key := source.get_instance_id()
	if not _prepared.has(key) and _prepared.size() >= 8: _prepared.erase(_prepared.keys()[0])
	_prepared[key] = {"mesh": null, "data": job.data}
	var invalidate := _forget_prepared.bind(key)
	if not source.changed.is_connected(invalidate): source.changed.connect(invalidate)
	preparations += 1
	preparation_usec += job.us

static func prepared_mesh(source:ArrayMesh,model:Variant)->ArrayMesh:
	if source.has_meta("solid_layer_faces"):return source
	var key:=source.get_instance_id()
	if _prepared.has(key):
		var reference := _prepared[key].mesh as WeakRef
		var alive := reference.get_ref() as ArrayMesh if reference != null else null
		if alive!=null:return alive
	var started:=Time.get_ticks_usec()
	var data:Dictionary
	if _prepared.has(key):data=_prepared[key].data
	else:
		if model is Callable:model=model.call()
		data=_prepare_data(source.surface_get_arrays(0),model)
		preparations+=1
	var result:=_publish(source,data)
	var mesh:ArrayMesh=result.mesh
	mesh.set_meta("solid_layer_faces",result.texture)
	if not _prepared.has(key) and _prepared.size()>=8:_prepared.erase(_prepared.keys()[0])
	# The prop owns its detailed carrier. A cache must not pin it after the
	# distance owner releases the last instance; live instances still share it.
	# Keep bounded CPU arrays/face pixels across distance returns. No GPU mesh
	# or texture is pinned by this entry after the final live carrier disappears.
	_prepared[key]={"mesh":weakref(mesh),"data":data}
	var invalidate:=_forget_prepared.bind(key)
	if not source.changed.is_connected(invalidate):source.changed.connect(invalidate)
	preparation_usec+=Time.get_ticks_usec()-started
	return mesh

static func bind(target:ShaderMaterial,mesh:ArrayMesh)->void:
	if not mesh.has_meta("solid_layer_faces"):return
	if _runtime_shader==null:
		_runtime_shader=Shader.new()
		_runtime_shader.code="#define EMBER_SOLID_MATERIAL_LAYERS\n"+Solid.solid_depth_shader().code
	target.shader=_runtime_shader
	target.set_meta("ember_solid_layers",true)
	if _wear_mask==null:_wear_mask=load("res://content/terrain_materials/textures/stone-weathering-mask.png")
	target.set_shader_parameter("stone_weathering_mask",_wear_mask)
	target.set_shader_parameter("stone_faces",mesh.get_meta("solid_layer_faces"))
	target.set_shader_parameter("stone_stage",2)
	target.set_shader_parameter("stone_profile_mode",true)
	var ids:PackedStringArray=mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	var image:=Image.create(256,2,false,Image.FORMAT_RGBAF)
	var materials=load("res://scripts/ember_voxel_surface_materials.gd")
	for slot in ids.size():
		if not ids[slot].is_empty():_write_profile(image,slot,materials.load_compact_terrain_variant(ids[slot]))
	var texture:=ImageTexture.create_from_image(image)
	target.set_meta("solid_layer_profiles",texture)
	target.set_meta("solid_layer_profile_image",image)
	target.set_shader_parameter("stone_profiles",texture)

static func _write_profile(image:Image,slot:int,pattern:Resource)->void:
	if pattern==null:return
	image.set_pixel(slot,0,Color(1.0 if pattern.stone_edges_enabled else 0.0,pattern.stone_edge_width_mm*0.001,pattern.stone_edge_strength,1.0 if pattern.stone_faces_enabled else 0.0))
	image.set_pixel(slot,1,Color(pattern.stone_face_pattern_variation,pattern.stone_face_tint_variation,1.0 if pattern.stone_weathering_enabled else 0.0,0))

static func update(target:ShaderMaterial,mesh:ArrayMesh,pattern:Resource,id:String)->void:
	if target==null or not target.has_meta("solid_layer_profiles"):return
	var ids:PackedStringArray=mesh.get_meta("solid_surface_material_ids",PackedStringArray())
	var texture:ImageTexture=target.get_meta("solid_layer_profiles")
	var image:Image=target.get_meta("solid_layer_profile_image")
	for slot in ids.size():
		if ids[slot]==id:_write_profile(image,slot,pattern)
	# Uniform lookup only. Sphere clones deliberately share this numeric table.
	texture.update(image)

static func sync_scale(target:ShaderMaterial,visual:Node3D)->void:
	if target==null or not target.get_meta("ember_solid_layers",false):return
	var scale:Vector3=visual.global_transform.basis.get_scale().abs()
	var metres:float=(scale.x+scale.y+scale.z)/(3.0*float(target.get_meta("ember_units_per_metre",1.0)))
	var current:Variant=target.get_shader_parameter("stone_model_scale")
	# The dummy rendering backend does not expose shader uniform defaults.
	# Bind the actual instance scale explicitly before comparing it.
	if current==null or not is_equal_approx(float(current),metres):target.set_shader_parameter("stone_model_scale",metres)

static func seam_segment(face:PackedVector3Array,cut:Plane,clip:Array)->PackedVector3Array:
	var hits:=PackedVector3Array()
	for i in face.size():
		var a:=face[i];var b:=face[(i+1)%face.size()]
		var da:=cut.distance_to(a);var db:=cut.distance_to(b)
		if absf(da)<0.001:hits.append(a)
		if da*db < -0.000001:hits.append(a.lerp(b,da/(da-db)))
	if hits.size()<2:return PackedVector3Array()
	var a:=hits[0];var b:=hits[hits.size()-1];var delta:=b-a
	var low:=0.0;var high:=1.0
	for plane:Plane in clip:
		var start:=plane.distance_to(a);var speed:=plane.normal.dot(delta)
		if absf(speed)<0.000001:
			if start>0.002:return PackedVector3Array()
			continue
		var t:float=-start/speed
		if speed>0:high=minf(high,t)
		else:low=maxf(low,t)
		if high<=low:return PackedVector3Array()
	if delta.length()*(high-low)<0.04:return PackedVector3Array()
	return PackedVector3Array([a+delta*low,a+delta*high])

static func prepare(source:ArrayMesh,model:Dictionary)->Dictionary:
	return _publish(source,_prepare_data(source.surface_get_arrays(0),model))

static func _prepare_data(arrays:Array,model:Dictionary)->Dictionary:
	var hull:Dictionary=Solid.hull_faces(model)
	var faces:Array=hull.faces
	var density:float=Vox.voxels_per_block(model)
	var data:=Image.create(96,maxi(1,faces.size()),false,Image.FORMAT_RGBAF)
	var descriptors:Array[Dictionary]=[]
	var seam_count:=0;var crack_count:=0
	for id in faces.size():
		var entry:Dictionary=faces[id];var plane:Plane=entry.plane;var polygon:PackedVector3Array=entry.face
		var centre:=Vector3.ZERO
		for point in polygon:centre+=point/density
		centre/=polygon.size()
		var u:=plane.normal.cross(Vector3.UP if absf(plane.normal.y)<0.95 else Vector3.FORWARD).normalized()
		var v:=plane.normal.cross(u).normalized()
		var seed_value:float=float(posmod(hash([id,entry.part,731]),10000))/10000.0
		data.set_pixel(0,id,Color(plane.normal.x,plane.normal.y,plane.normal.z,plane.d/density))
		data.set_pixel(1,id,Color(u.x,u.y,u.z,seed_value))
		data.set_pixel(2,id,Color(v.x,v.y,v.z,float(entry.part)))
		data.set_pixel(3,id,Color(centre.x,centre.y,centre.z,float(mini(MAX_EDGES,polygon.size()))))
		for edge in mini(MAX_EDGES,polygon.size()):
			var a:Vector3=polygon[edge]/density;var b:Vector3=polygon[(edge+1)%polygon.size()]/density
			var inward:=plane.normal.cross(b-a).normalized()
			if inward.dot(centre-a)<0:inward=-inward
			data.set_pixel(8+edge,id,Color(inward.x,inward.y,inward.z,inward.dot(a)))
		var segments:Array[PackedVector3Array]=[]
		for part in hull.planes.size():
			if part==entry.part:continue
			for other:Plane in hull.planes[part]:
				var segment:=seam_segment(polygon,other,hull.planes[part])
				if segment.is_empty() or segments.size()>=MAX_EDGES:continue
				segments.append(segment)
		for i in segments.size():
			var a:Vector3=segments[i][0]/density;var b:Vector3=segments[i][1]/density
			data.set_pixel(40+i,id,Color(u.dot(a),v.dot(a),u.dot(b),v.dot(b)))
		seam_count+=segments.size()
		var edge_index:=posmod(hash([id,921]),polygon.size())
		var start:Vector3=polygon[edge_index].lerp(polygon[(edge_index+1)%polygon.size()],0.35+seed_value*0.25)/density
		var length_m:=minf(0.38,start.distance_to(centre)*0.7)
		var crack:bool=seed_value>0.64 and length_m>0.09
		var direction:Vector3=(centre-start).normalized()
		var middle:Vector3=start+direction*length_m*0.52+u*(seed_value-0.5)*0.055
		var end:Vector3=start+direction*length_m
		data.set_pixel(4,id,Color(float(segments.size()),1.0 if crack else 0.0,0,0))
		data.set_pixel(5,id,Color(float(entry.slot),0,0,0))
		data.set_pixel(80,id,Color(u.dot(start),v.dot(start),u.dot(middle),v.dot(middle)))
		data.set_pixel(81,id,Color(u.dot(end),v.dot(end),0.004,0))
		if crack:crack_count+=1
		descriptors.append({"plane":Plane(plane.normal,plane.d/density),"part":entry.part})
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2].duplicate()
	# The solid hull carries the same palette slot in three redundant UV channels.
	# Reuse palette_slot's existing varying for the face ID; do not exceed Forward+'s budget.
	var slots:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	for i in uv.size():assert(is_equal_approx(slots[i].x,slots[i].y) and is_equal_approx(slots[i].x,uv[i].x),"Probe requires one palette slot per solid face")
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	assert(indices.is_empty(),"The accepted detailed rock is an unindexed mesh")
	for triangle in range(0,points.size(),3):
		var centre:Vector3=(points[triangle]+points[triangle+1]+points[triangle+2])/3.0
		var n:Vector3=(normals[triangle]+normals[triangle+1]+normals[triangle+2]).normalized()
		var best:=INF;var chosen:=0
		for id in descriptors.size():
			var face:Dictionary=descriptors[id];var plane:Plane=face.plane
			var outside:=0.0
			for bound:Plane in hull.planes[face.part]:outside=maxf(outside,bound.distance_to(centre*density)/density)
			var score:=absf(plane.distance_to(centre))+(1.0-plane.normal.dot(n))*0.08+outside*4.0
			if score<best:best=score;chosen=id
		for k in 3:uv[triangle+k].y=float(chosen)
	arrays[Mesh.ARRAY_TEX_UV2]=uv
	return {"arrays":arrays,"image":data,"faces":faces.size(),"seams":seam_count,"cracks":crack_count}

static func _publish(source:ArrayMesh,data:Dictionary)->Dictionary:
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.arrays,[],{},Solid.CUSTOM_FORMAT)
	mesh.surface_set_name(0,source.surface_get_name(0))
	for key in source.get_meta_list():mesh.set_meta(key,source.get_meta(key))
	return {"mesh":mesh,"texture":ImageTexture.create_from_image(data.image),"faces":data.faces,"seams":data.seams,"cracks":data.cracks}

static func material(original:ShaderMaterial,prepared:Dictionary)->ShaderMaterial:
	var result:ShaderMaterial=original.duplicate()
	# The comparison can also run after production layers have been enabled.
	var code:String=Solid.solid_depth_shader().code.replace("\r\n","\n")
	assert(code.contains("void fragment() {") and code.contains("void vertex() {"))
	code=code.replace("void vertex() {",FileAccess.get_file_as_string(LEAF)+"\nvoid vertex() {")
	code=code.replace("palette_slot = COLOR.a;","palette_slot = UV2.y;")
	code=code.replace("palette_slot * 255.0","smooth_slots.x")
	code=code.replace("vec3 ember_solid_local_rgb(int slot, float layer, float span_m) {", "vec3 ember_solid_local_rgb(int slot, float layer, float span_m) {\n if(stone_stage>=2)return stone_colour(terrain_position,layer,span_m);\n")
	var depth:String=FileAccess.get_file_as_string("res://shaders/ember_terrain_material_depth.gdshaderinc").replace("\r\n","\n")
	depth=depth.replace("float material_depth_height_at(vec3 p, vec3 n) {\n\tvec3 tile = solid_depth_tile_position(p);", "float material_depth_height_at(vec3 p, vec3 n) {\n if(stone_stage>=2){vec3 local=(solid_depth_world_to_local*vec4(p,1.0)).xyz;return clamp(material_depth_tile(stone_uv(local,material_depth_span()))-stone_crack(local)*0.22,0.0,1.0);}\n\tvec3 tile = solid_depth_tile_position(p);")
	depth=depth.replace("vec3 material_depth_albedo(vec3 p, vec3 n) {\n\tint slot = material_depth_current_slots().x;", "vec3 material_depth_albedo(vec3 p, vec3 n) {\n\tint slot = material_depth_current_slots().x;\n if(stone_stage>=2){vec3 stone_hit=(solid_depth_world_to_local*vec4(p,1.0)).xyz;vec4 png=texelFetch(png_lookup,ivec2(slot,0),0);vec3 rgb=stone_colour(stone_hit,png.r-1.0,material_depth_span());vec3 mean=texelFetch(png_mean_lookup,ivec2(slot,0),0).rgb;return texelFetch(png_tint_lookup,ivec2(slot,0),0).rgb*clamp(rgb/max(mean,vec3(0.001)),vec3(0.55),vec3(1.65));}\n")
	code=code.replace('#include "res://shaders/ember_terrain_material_depth.gdshaderinc"',depth)
	var finish:="""
	if(stone_stage>0){
	 vec4 edge=stone_edge(terrain_position);float aa=max(fwidth(edge.w),0.0005);
	 float wear=1.0-smoothstep(0.014-aa,0.022+aa,edge.w);
	 vec3 facet=stone_row(0).xyz;
	 vec3 bevel=normalize(mat3(VIEW_MATRIX)*MODEL_NORMAL_MATRIX*normalize(facet-edge.xyz*0.7));
	 NORMAL=normalize(mix(NORMAL,bevel,wear*0.55));
	 float seam=stone_seam(terrain_position);float seam_aa=max(fwidth(seam),0.0005);
	 float crevice=1.0-smoothstep(0.008-seam_aa,0.026+seam_aa,seam);
	 ALBEDO*=mix(1.0,1.10,wear)*(1.0-crevice*0.24);
	 if(stone_stage>=2){float seed=stone_row(1).w;ALBEDO*=mix(vec3(0.96,0.98,1.01),vec3(1.04,1.02,0.99),seed);}
	 if(stone_stage>=3){

	  vec2 p=stone_plane_uv(terrain_position);float patch=floor(p.x*5.0)+floor(p.y*5.0)*17.0+float(stone_face_id())*13.0;
	  float chips=step(0.83,fract(sin(patch*1.37)*43758.5453));
	  float chip=chips*(1.0-smoothstep(0.008-aa,0.032+aa,edge.w));
	  ALBEDO=mix(ALBEDO,ALBEDO*vec3(1.12,1.10,1.06),chip*0.65);
	 }
	}
"""
	code=code.replace("\n}\n\nvoid light() {",finish+"\n}\n\nvoid light() {")
	assert(code.contains("vec4 edge=stone_edge(terrain_position)"),"Probe finish hook missing")
	assert(code.contains("material_depth_tile(stone_uv(local"),"Probe shared height hook missing")
	var shader:=Shader.new();shader.code=code;result.shader=shader
	result.set_shader_parameter("stone_faces",prepared.texture)
	result.set_shader_parameter("stone_stage",1)
	result.set_shader_parameter("stone_profile_mode",false)
	return result
