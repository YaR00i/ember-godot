extends Node3D
## The QA renderer owns the three meshes, their deformation, LOD classification
## and indirect commands. Terrain3D supplies a bounded window of root positions.
const Study = preload("tuft_study.gd")
const SIDE := 7
var factory = Study.new()
var state = factory.state
var heights: Texture2D
var mask: Texture2D
var count: int
var base_count: int
var dense_reserved := false
var limits: Vector2
var seed_value: int
var cell := Vector2i(-999,-999)
var style := 0
var density := 1.0
var width := 1.0
var height_scale := 1.0
var gloss := 0.4
var wind := 1.0
var wind_speed:=1.0
var wind_degrees:=0.0
var clumping:=0.0
var patch_metres:=2.0
var tint_color:=Color.WHITE
var tint_mix:=0.0
var sun_shadows:=true
var tuft_lod := true
var root_shader := RID()
var root_pipeline := RID()
var root_set := RID()
var sampler := RID()
var last_data := PackedByteArray()
var ready_field := false

func setup(spec: Dictionary, h: Texture2D, m: Texture2D, color: Texture2D) -> void:
	heights=h
	mask=m
	limits=Vector2(spec.height_min_m,spec.height_max_m)
	seed_value=int(spec.seed)
	count=maxi(1,ceili(256*float(spec.grass_max_per_m2)))
	base_count=count
	var paint := preload("res://content/terrain_materials/cartoon_grass.tres")
	var source := ShaderMaterial.new()
	source.shader=preload("meadow_material.gdshader")
	source.set_shader_parameter("grass_paint",paint.albedo_texture)
	source.set_shader_parameter("paint_period",paint.pattern_size_m)
	source.set_shader_parameter("zone_color",color)
	source.set_shader_parameter("field_height",h)
	factory.make_material(source)
	for item: ShaderMaterial in factory.study_materials:
		var shader := Shader.new()
		var code := item.shader.code.strip_edges()
		if item==factory.study_materials[1]:
			code=code.replace("void fragment() {","uniform sampler2D tuft_atlas : source_color,filter_linear_mipmap,repeat_disable;\nvoid fragment() {\n vec4 tuft=texture(tuft_atlas,UV); ALPHA=tuft.a; ALPHA_SCISSOR_THRESHOLD=0.55;")
		code=code.replace("vec4(0.0,1.0,0.0,0.0)","vec4(ground_normal,0.0)")
		code=code.replace("ATTENUATION","(LIGHT_IS_DIRECTIONAL && !sun_shadows ? 1.0 : ATTENUATION)")
		# Add adjustable transmission from the low sun to the QA material B.
		shader.code=code.left(code.rfind("}"))+"\n SPECULAR_LIGHT += LIGHT_COLOR*(LIGHT_IS_DIRECTIONAL && !sun_shadows ? 1.0 : ATTENUATION)*gloss*mix(0.12,1.,blade_tip)*pow(max(dot(-LIGHT,VIEW),0.),8.);\n}"
		item.shader=shader
		if item==factory.study_materials[1]:
			item.set_shader_parameter("tuft_atlas",preload("res://scripts/ember_grass_patch.gd").GRASS_CARD_ATLAS)
		item.set_shader_parameter("qa_wind_speed",1.)
		item.set_shader_parameter("qa_wind_direction",Vector2.RIGHT)
	state.native_arrays=preload("res://scripts/ember_grass_patch.gd").GRASS_CARD_MESH.surface_get_arrays(0)
	# Each atlas plane owns six indices. Preserve the two crossing planes
	# (0 and 2) in the far field, and all original UVs, roots and wind.
	for planes in [[0,1,2,3],[0,1,2],[0,2]]:
		var arrays: Array=state.native_arrays.duplicate()
		var indices:=PackedInt32Array()
		for plane: int in planes:
			indices.append_array(state.native_arrays[Mesh.ARRAY_INDEX].slice(plane*6,plane*6+6))
		arrays[Mesh.ARRAY_INDEX]=indices
		state.tuft_meshes.append(arrays)
	RenderingServer.call_on_render_thread(initialize.bind(get_world_3d().scenario,base_count))
	while not ready_field and state.error.is_empty():await get_tree().process_frame
	if not state.error.is_empty():push_error(state.error)
	configure()

func initialize(scenario: RID, capacity_per_tile: int) -> void:
	var roots := PackedByteArray()
	var tiles := PackedByteArray()
	roots.resize(capacity_per_tile*SIDE*SIDE*32)
	tiles.resize(SIDE*SIDE*32)
	state.pool_capacity=capacity_per_tile*SIDE*SIDE
	state.dispatch_roots=state.pool_capacity
	state.initialize(roots,tiles,[],RID(),scenario)
	if not state.initialized:return
	state.extent(state.pool_capacity,AABB(Vector3(-1,limits.x-2,-1),Vector3(1002,limits.y-limits.x+5,1002)))
	var rd: RenderingDevice=state.rd
	var source := RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://kilometre/meadow_roots.glsl").replace("#[compute]","")
	var compiled := rd.shader_compile_spirv_from_source(source)
	state.error=compiled.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not state.error.is_empty():return
	root_shader=rd.shader_create_from_spirv(compiled)
	root_pipeline=rd.compute_pipeline_create(root_shader)
	var sampling := RDSamplerState.new()
	sampling.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampling.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler=rd.sampler_create(sampling)
	var uniforms: Array[RDUniform]=[]
	for i in 4:
		var u:=RDUniform.new()
		u.binding=i
		if i<2:
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(state.buffers[i])
		else:
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			u.add_id(sampler)
			u.add_id(RenderingServer.texture_get_rd_texture((heights if i==2 else mask).get_rid()))
		uniforms.append(u)
	root_set=rd.uniform_set_create(uniforms,root_shader,0)
	ready_field=true

func configure() -> void:
	if not ready_field:return
	last_data=PackedByteArray()
	var multiple:=maxf(1.0,density)
	# At full density patch grouping still needs spare candidate roots.
	if clumping>0. and density>=1.:multiple=2.
	var next_count:=ceili(base_count*multiple)
	if style!=3 and next_count>base_count and not dense_reserved:
		dense_reserved=true
		RenderingServer.call_on_render_thread(reserve_dense.bind(get_world_3d().scenario))
	if next_count!=count:
		count=next_count
		cell=Vector2i(-999,-999)
	for item: ShaderMaterial in factory.study_materials:
		item.set_shader_parameter("qa_width_multiplier",width)
		item.set_shader_parameter("qa_height_multiplier",height_scale)
		item.set_shader_parameter("gloss",gloss)
		item.set_shader_parameter("qa_wind",wind)
		item.set_shader_parameter("qa_wind_direction",Vector2.from_angle(deg_to_rad(wind_degrees)))
		item.set_shader_parameter("qa_wind_speed",wind_speed)
		item.set_shader_parameter("tint_color",tint_color)
		item.set_shader_parameter("tint_mix",tint_mix)
		item.set_shader_parameter("sun_shadows",sun_shadows)
	RenderingServer.call_on_render_thread(state.settings.bind(PackedFloat32Array([density*base_count/count,clumping,patch_metres,mini(style,2),width,height_scale,float(tuft_lod),0])))

func reserve_dense(scenario: RID) -> void:
	# Only pay the second pool's VRAM cost when requested in the look panel.
	release()
	state.released=false
	state.initialized=false
	initialize(scenario,base_count*2)

func follow(point: Vector3,camera: Camera3D) -> void:
	if not ready_field or not camera:return
	if style==3:
		if last_data.is_empty():
			RenderingServer.call_on_render_thread(state.update.bind(PackedByteArray(),false))
			last_data=PackedByteArray([1])
		return
	var next := Vector2i(floori(point.x/16.),floori(point.z/16.))
	if next!=cell:
		cell=next
		RenderingServer.call_on_render_thread(fill.bind(cell,count))
	var params := PackedFloat32Array()
	for plane in camera.get_frustum():params.append_array(PackedFloat32Array([plane.x,plane.y,plane.z,plane.d]))
	var eye:=camera.global_position
	var forward:=-camera.global_basis.z
	var focal: float=get_viewport().size.y*absf(camera.get_camera_projection().y.y)*0.5
	params.append_array(PackedFloat32Array([eye.x,eye.y,eye.z,0,point.x,point.y,point.z,0,1,29,40,0,forward.x,forward.y,forward.z,focal,40,20,absf(camera.global_basis.y.y),0]))
	var data:=params.to_byte_array()
	if data==last_data:return
	last_data=data
	factory.study_materials[style].set_shader_parameter("field_anchor",point)
	RenderingServer.call_on_render_thread(state.update.bind(data,true))

func fill(center: Vector2i,active_count: int) -> void:
	var rd: RenderingDevice=state.rd
	state.dispatch_roots=active_count*SIDE*SIDE
	var push:=PackedInt32Array([center.x-SIDE/2,center.y-SIDE/2,active_count,SIDE]).to_byte_array()
	push.append_array(PackedFloat32Array([limits.x,limits.y,0,0]).to_byte_array())
	push.encode_u32(28,seed_value&0xffffffff)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,root_pipeline)
	rd.compute_list_bind_uniform_set(list,root_set,0)
	rd.compute_list_set_push_constant(list,push,32)
	rd.compute_list_dispatch(list,ceili(float(active_count*SIDE*SIDE)/64),1,1)
	rd.compute_list_end()

func release() -> void:
	for rid in [root_set,root_pipeline,root_shader,sampler]:
		if rid.is_valid():state.rd.free_rid(rid)
	state.release()

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(release)
	factory.free()
