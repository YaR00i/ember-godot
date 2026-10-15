extends RefCounted
## Derived LAB texture only; Recipe/Source/palette/occupancy remain authored owners.
const Bark = preload("res://addons/ember_import/ember_voxel_bark_pattern.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Profiles = preload("res://scripts/ember_voxel_material_profiles.gd")
const SOURCE_PATH = "res://content/voxel_models/vox_tree_1511837690.tres"
const RECIPE_PATH = "res://content/editor/voxel_generators/vox_tree_1511837690.tres"
const SETTINGS = {"bark_pattern":true,"bark_pattern_version":2,"bark_pattern_direction":1,"bark_pattern_length":14,"bark_pattern_density":45}

static func build_inputs() -> Dictionary:
	var source: EmberVoxelModelResource = load(SOURCE_PATH)
	var recipe: Resource = load(RECIPE_PATH).duplicate(true)
	var original := Generator.build(recipe,source.palette[2],source.material,"Bark LAB evidence")
	assert(not original.has("error"))
	assert(original.geometry.voxels==source.voxels and original.geometry.collision_voxels==source.collision_voxels)
	recipe.parameters.merge(SETTINGS,true)
	var patterned := Generator.build(recipe,source.palette[2],source.material,"Bark LAB pattern")
	assert(not patterned.has("error"))
	# Enabling bark marks only changes colour indices; occupied cells stay exact.
	for i in source.voxels.size():
		assert((source.voxels[i]>0)==(patterned.geometry.voxels[i]>0))
	assert(patterned.geometry.collision_voxels==source.collision_voxels)
	var private_source := source.duplicate_model()
	# Known generator palette roles, not a guess from RGB. Legacy leaves retain
	# their exact previous material response. No authoring Resource is saved.
	Profiles.assign(private_source.material,"legacy",{"1":"bark","2":"bark","3":"bark"})
	return {"source":source,"private_source":private_source,"recipe":recipe,
		"support":Bark.support_frames(patterned.bark_support_lines),"offset":Vector3(patterned.bark_support_offset),
		"settings":Bark.normalized(recipe.parameters),"grid":patterned.grid,
		"field_grid":Vector3i(patterned.grid.x*2,patterned.grid.y,patterned.grid.z*2),
		"support_count":patterned.bark_support_lines.size(),"mark_count":patterned.geometry.voxels.count(7)}

static func layer(inputs: Dictionary, z: int) -> Image:
	var grid: Vector3i = inputs.field_grid
	var image := Image.create(grid.x,grid.y,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new();noise.seed=inputs.recipe.seed+15485863
	noise.frequency=0.16
	var palette: PackedColorArray = inputs.source.palette
	for y in grid.y:
		for x in grid.x:
			var raw: Vector3 = Vector3((x+0.5)*0.5,y+0.5,(z+0.5)*0.5)-inputs.offset
			var uv := Bark.support_coordinates(raw,inputs.support)
			var distance := Bark.scattered_stroke_distance(uv[0],uv[1],uv[2],inputs.recipe.seed,inputs.settings)
			var groove := 1.0-smoothstep(-0.20,0.45,distance)
			var tone := noise.get_noise_3d(raw.x,raw.y*0.7,raw.z)
			var colour := palette[1].lerp(palette[2],smoothstep(-0.36,0.04,tone))
			colour = colour.lerp(palette[3],smoothstep(0.18,0.50,tone)*0.55)
			colour = colour.lerp(palette[2],0.35).darkened(groove*0.23)
			colour.a=0.5-groove*0.42
			image.set_pixel(x,y,colour)
	return image

static func texture(layers: Array[Image]) -> ImageTexture3D:
	var field := ImageTexture3D.new()
	assert(field.create(Image.FORMAT_RGBA8,layers[0].get_width(),layers[0].get_height(),layers.size(),false,layers)==OK)
	return field

static func shader() -> Shader:
	var result := Shader.new()
	result.code="#define EMBER_OBJECT_BARK_STUDY\n"+(load("res://shaders/ember_voxel_toon.gdshader") as Shader).code
	return result

static func material(field: Texture3D, inputs: Dictionary) -> ShaderMaterial:
	var result := EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	result.shader=shader()
	result.set_shader_parameter("bark_study_field",field)
	result.set_shader_parameter("bark_study_size_m",Vector3(inputs.grid)/16.0)
	result.set_shader_parameter("bark_study_base",inputs.source.palette[2])
	result.set_shader_parameter("surface_grain_scale",0.0)
	result.set_shader_parameter("material_depth_amplitude_m",0.012)
	return result

static func panel_mesh(inputs: Dictionary) -> ArrayMesh:
	# Existing BoxMesh as a flat diagnostic surface. No new object mesher.
	var box := BoxMesh.new();box.size=Vector3(0.875,1.75,0.4375)
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours := PackedColorArray();var custom := PackedFloat32Array()
	var center := Vector3(inputs.offset)/16.0+Vector3(0.0,0.875,0.0)
	for i in vertices.size():
		vertices[i]+=center;colours.append(inputs.source.palette[2])
		var profile: Vector4=Profiles.PROFILES.bark
		for channel in [profile.x,profile.y,profile.z,profile.w]:custom.append(channel)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colours
	arrays[Mesh.ARRAY_CUSTOM0]=custom
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh
