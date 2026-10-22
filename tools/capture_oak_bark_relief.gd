extends "res://tools/capture_oak_bark_painted.gd"
const BarkRelief=preload("res://scripts/prototypes/ember_painted_bark_relief_recipe.gd")
const RANGES=[0.0,0.003,0.006]
var relief_shaders: Dictionary={}
var original_bark_shaders: Dictionary={}
var frozen_bark_shader: Shader
var zero_checked: Dictionary={}
var mask_bakes:=0
var relief_returns:=0

func junctions_only() -> bool:
	return OS.get_cmdline_user_args().has("--junctions-only")

func review_camera_indices() -> Array:
	if not junctions_only():return [0,4,5]
	if review_views.size()==6:
		var bounds: AABB=scene.look_bounds
		var target: Vector3=scene.look_prop.to_global(Vector3(0,bounds.position.y+bounds.size.y*0.30,0))
		add_camera("junction",target,Vector3(-1.2,0.15,3.0))
	return [6]

func prepare_materials() -> void:
	super.prepare_materials()
	if not relief_shaders.is_empty():return
	var mask:=BarkRelief.mask_for(Image.load_from_file(BarkRelief.MASTER));mask_bakes=BarkRelief.bake_count
	mask.save_png(output.path_join("recess-mask.png"))
	var texture:=ImageTexture.create_from_image(mask)
	var previous_body:=FileAccess.get_file_as_string(output.path_join("before/shaders/ember_voxel_toon_body.gdshaderinc"))
	var previous_bark:=FileAccess.get_file_as_string(output.path_join("before/shaders/ember_painted_bark_study.gdshaderinc"))
	frozen_bark_shader=Shader.new()
	frozen_bark_shader.code="shader_type spatial;\n#define EMBER_OBJECT_PAINTED_BARK_STUDY\n"+previous_body.replace('#include "res://shaders/ember_painted_bark_study.gdshaderinc"',previous_bark)
	for material in bark_materials:
		var id:=material.get_instance_id()
		original_bark_shaders[id]=material.shader
		var shader:=Shader.new();shader.code="#define EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY\n"+material.shader.code
		relief_shaders[id]=shader;material.shader=shader
		material.set_shader_parameter("painted_bark_recess_mask",texture)
		material.set_shader_parameter("material_depth_steps",16)
		material.set_shader_parameter("material_depth_shadows",false)
	bind_relief(2)

func shader_parameters(material: ShaderMaterial,exclude_bark: bool) -> Dictionary:
	var parameters:=super.shader_parameters(material,exclude_bark)
	# Only these private LAB inputs are new; every existing wood/leaf setting is guarded.
	for key in parameters.keys():
		if str(key).begins_with("shader_parameter/material_depth_") or str(key).begins_with("shader_parameter/painted_bark_relief_") or key=="shader_parameter/painted_bark_recess_mask":parameters.erase(key)
	return parameters

func bind_relief(revision: int) -> void:
	for material in bark_materials:
		material.shader=relief_shaders[material.get_instance_id()]
		material.set_shader_parameter("painted_bark_albedo",bark_candidate)
		material.set_shader_parameter("painted_bark_relief_enabled",true)
		material.set_shader_parameter("material_depth_amplitude_m",RANGES[revision])

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if not relief_shaders.is_empty():bind_relief(2)

func capture(name: String) -> Image:
	# The supplementary junction run needs the lighting matrix, not a second game sweep.
	if junctions_only() and name.begins_with("motion-"):return root.get_texture().get_image()
	var paired:=name.begins_with("view-") or name.begins_with("motion-") or name.begins_with("return-")
	if not paired or relief_shaders.is_empty():return await take(name)
	var leaf_clip_states: Array=[]
	if OS.get_cmdline_user_args().has("--bark-only"):
		for guard: Dictionary in tree_guards:
			var leaf: ShaderMaterial=guard.leaf
			leaf_clip_states.append({"leaf":leaf,"enabled":leaf.get_shader_parameter("object_look_clip_enabled"),"plane":leaf.get_shader_parameter("object_look_plane"),"positive":leaf.get_shader_parameter("object_look_positive")})
			leaf.set_shader_parameter("object_look_clip_enabled",true)
			leaf.set_shader_parameter("object_look_plane",Vector4(1,0,0,1000))
			leaf.set_shader_parameter("object_look_positive",true)
	var images: Array[Image]=[]
	for revision in 3:
		bind_relief(revision)
		var image:=await take(name+("-rev-%d"%revision if revision<2 else ""));images.append(image)
	if name.begins_with("view-"):
		for revision in 3:
			bind_relief(revision);await frames()
			check(images[revision].get_data()==root.get_texture().get_image().get_data(),"bark relief exact local return "+str(revision))
			relief_returns+=1
		var key:="%s-%d"%[name.get_slice("-",1),scene.material_style]
		if not zero_checked.has(key):
			for material in bark_materials:material.shader=frozen_bark_shader
			var frozen:=await take("legacy-zero-"+key)
			check(frozen.get_data()==images[0].get_data(),"zero relief matches frozen accepted pigment "+key)
			bind_relief(0)
			for material in bark_materials:material.set_shader_parameter("painted_bark_relief_enabled",false)
			check(images[0].get_data()==(await take("disabled-zero-"+key)).get_data(),"disabled relief matches zero range "+key)
			zero_checked[key]=true
	elif name.begins_with("return-"):
		var parts:=name.split("-")
		for revision in 2:
			var first:=Image.load_from_file(output.path_join("view-%s-preset-%s-light-%s-look-0-rev-%d.png"%[parts[1],parts[2],parts[3],revision]))
			check(first.get_data()==images[revision].get_data(),"flat/shallow bark smooth return exact")
	if name.begins_with("motion-1-1-"):
		var camera: Camera3D=scene.follow_camera._cam;var pose:=camera.global_transform;var fov:=camera.fov
		camera_view(5);camera.global_position+=camera.global_basis.x*((int(name.get_slice("-",4))/9.0-0.5)*0.30)
		for revision in 3:
			bind_relief(revision);await take("close-motion-%d-%d-%s"%[scene.material_style,revision,name.get_slice("-",4)])
		camera.global_transform=pose;camera.fov=fov
	if name.begins_with("view-5-preset-1-light-1-"):
		var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun");var basis:=sun.global_basis
		scene.set_sun_pose(0);var start:=sun.global_basis
		scene.set_sun_pose(1);var end:=sun.global_basis
		for frame in 8:
			sun.global_basis=start.slerp(end,frame/7.0);bind_stone(painted_stone,scene.material_style)
			for revision in 3:
				bind_relief(revision);await take("sun-%d-%d-%02d"%[scene.material_style,revision,frame])
		sun.global_basis=basis;bind_stone(painted_stone,scene.material_style)
	bind_relief(2)
	for state: Dictionary in leaf_clip_states:
		state.leaf.set_shader_parameter("object_look_clip_enabled",state.enabled)
		state.leaf.set_shader_parameter("object_look_plane",state.plane)
		state.leaf.set_shader_parameter("object_look_positive",state.positive)
	return images[2]

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	check(BarkRelief.bake_count==mask_bakes,"mask cached across light/camera/profile switches")
	for material in bark_materials:
		material.set_shader_parameter("painted_bark_relief_enabled",false)
		material.set_shader_parameter("material_depth_amplitude_m",0.0)
		material.shader=original_bark_shaders[material.get_instance_id()]
	result.erase("bark")
	result["bark_relief"]={"master":BarkRelief.MASTER,"mask_version":BarkRelief.VERSION,"actual_max_recess_m":[0,0.0015,0.003],"trace_ranges_m":RANGES,"ray_steps":16,"height":"0.5 - 0.5 * selected recess mask; inward only","local_exact_returns":relief_returns,"cross_look_returns":18 if junctions_only() else 54,"zero_cases":zero_checked.size(),"stills":54 if junctions_only() else 162,"game_motion_frames":0 if junctions_only() else 540,"close_motion_frames":0 if junctions_only() else 90,"sun_motion_frames":0 if junctions_only() else 72,"mask_bakes":mask_bakes,"rim":"original macro normal retained","shadows":"existing real receive; no LIGHT_VERTEX or additional self-shadow modification"}
	result["scope"]="accepted oak-v3 pigment fixed; selected shallow optical recesses only; geometry, Source/paint, foliage B, common light, terrain and physics unchanged"
	result["technical_bark_only"]=OS.get_cmdline_user_args().has("--bark-only")
	result["manual_acceptance"]="OPEN: choose flat /1.5mm /3mm; no main-editor transfer; earlier stone/soil depth decisions remain deferred"
	return result
