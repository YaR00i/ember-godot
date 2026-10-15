extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_smooth_tree_material_fixture.gd")
const BarkProjection=preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:
	var inputs:=Fixture.new().build()
	check(inputs.cloud_lobes==42 and inputs.hanging_leaves==109 and inputs.wood_segments==63,"same selected shape and seed")
	var original: ArrayMesh=inputs.meshes.wood
	var before:=original.surface_get_arrays(0)
	var mapped:=BarkProjection.mesh(original,inputs.structure,inputs.pivot_bias)
	var after:=mapped.surface_get_arrays(0)
	for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:
		check(before[attribute]==after[attribute],"UV binding preserves geometry/paint "+str(attribute))
	var normal_error:=0.0
	for i in (before[Mesh.ARRAY_NORMAL] as PackedVector3Array).size():
		normal_error=maxf(normal_error,before[Mesh.ARRAY_NORMAL][i].distance_to(after[Mesh.ARRAY_NORMAL][i]))
	check(normal_error<0.001,"normal directions preserved through ArrayMesh repacking")
	check(original.surface_get_arrays(0)==before,"original saved shape mesh immutable")
	var pairs: PackedFloat32Array=after[Mesh.ARRAY_CUSTOM1]
	for i in range(0,pairs.size(),12):
		for j in 3:
			for channel in 2:
				var index:=pairs[i+j*4+channel]
				check(index>=0 and index<inputs.wood_segments,"valid source support index")
				check(index==pairs[i+channel],"flat source support pair agrees across triangle")
	var repeated:=BarkProjection.mesh(original,inputs.structure,inputs.pivot_bias)
	check(repeated.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]==pairs,"stable derived mapping on repeat")
	check(not after[Mesh.ARRAY_CUSTOM0].is_empty(),"explicit bark role for existing object shader")
	check(FileAccess.file_exists(BarkProjection.ART),"project-owned painted texture exists")
	check(FileAccess.file_exists(BarkProjection.CALM_ART) and FileAccess.file_exists(BarkProjection.FOLIAGE_ART),"new coarse artwork is project owned")
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	var canopy: ArrayMesh=inputs.meshes.clouds
	var canopy_before:=canopy.surface_get_arrays(0)
	var foliage:=BarkProjection.foliage_material(canopy,profile)
	check(canopy.surface_get_arrays(0)==canopy_before,"foliage material creation preserves original positions, normals, UVs and paint")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(foliage.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"accepted light profile remains the owner "+key)
	var texture: Texture2D=foliage.get_shader_parameter("painted_foliage_albedo")
	check(texture.get_image().has_mipmaps(),"foliage artwork distance filtering")
	print("SMOOTH_BARK_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
