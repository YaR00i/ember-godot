extends "res://tools/capture_rock_painted_refinement.gd"
## One oak colour trial. Existing bark projection, Source and look bake own all math.
const BARK_PAINTED_PATH:="res://content/material_studies/trees/bark_species_v1/oak-v3-painted.png"
var bark_candidate: Texture2D
var bark_controls: Dictionary={}
var bark_materials: Array[ShaderMaterial]=[]
var tree_guards: Array=[]
var bark_exact_returns:=0

func review_camera_indices() -> Array:
	return [0,4,5]

func prepare_materials() -> void:
	super.prepare_materials()
	if bark_candidate!=null:return
	bark_candidate=scene.LookBake.Bark.artwork(BARK_PAINTED_PATH)
	check(bark_candidate!=null and bark_candidate.get_image().has_mipmaps(),"new bark has existing artwork cache and mips")
	for visual in [scene.smooth_visual,scene.faceted_visual,scene.voxel_visual]:
		var wood: ShaderMaterial=visual.mesh.surface_get_material(0)
		var leaf: ShaderMaterial=visual.mesh.surface_get_material(1)
		bark_materials.append(wood)
		bark_controls[wood.get_instance_id()]=wood.get_shader_parameter("painted_bark_albedo")
		tree_guards.append({"visual":visual,"mesh":visual.mesh,"wood":wood,"leaf":leaf,
			"wood_arrays":hash(visual.mesh.surface_get_arrays(0)),"leaf_arrays":hash(visual.mesh.surface_get_arrays(1)),
			"wood_parameters":shader_parameters(wood,true),"leaf_parameters":shader_parameters(leaf,false)})
	bark_controls[bark_materials[0].get_instance_id()].get_image().save_png(output.path_join("bark-A.png"))
	bark_candidate.get_image().save_png(output.path_join("bark-B.png"))
	check(ResourceSaver.save(scene.look_source,output.path_join("common-oak-source.res"))==OK,"save original oak Source")
	var reopened=ResourceLoader.load(output.path_join("common-oak-source.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	# Resource paths legitimately differ between the authoring library and QA copy.
	check(hash(reopened.to_definition().model)==hash(scene.look_source.to_definition().model) and reopened.schema_version==scene.look_source.schema_version,"oak Source authoring data save/reopen exact")

func shader_parameters(material: ShaderMaterial,exclude_bark: bool) -> Dictionary:
	var parameters: Dictionary={}
	for property in material.get_property_list():
		var key:=str(property.name)
		if key.begins_with("shader_parameter/") and not (exclude_bark and key=="shader_parameter/painted_bark_albedo"):
			parameters[key]=material.get(key)
	return parameters

func bind_bark(revision: int) -> void:
	for material in bark_materials:
		material.set_shader_parameter("painted_bark_albedo",bark_controls[material.get_instance_id()] if revision==0 else bark_candidate)

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if bark_candidate!=null:bind_bark(1)

func capture(name: String) -> Image:
	# Bypass the inherited stone comparison: stone stays at that trial's A control.
	# Both columns share exactly the same environment/materials, only oak albedo changes.
	var paired:=name.begins_with("view-") or name.begins_with("motion-") or name.begins_with("return-")
	if paired and bark_candidate!=null:
		bind_bark(0)
		var control:=await take(name+"-rev-0")
		bind_bark(1)
		var painted:=await take(name)
		if name.begins_with("view-"):
			bind_bark(0);await frames()
			check(control.get_data()==root.get_texture().get_image().get_data(),"bark A returns pixel-exact "+name)
			bark_exact_returns+=1
			bind_bark(1);await frames()
			check(painted.get_data()==root.get_texture().get_image().get_data(),"bark B returns pixel-exact "+name)
			bark_exact_returns+=1
		elif name.begins_with("return-"):
			var parts:=name.split("-")
			var baseline:=Image.load_from_file(output.path_join("view-%s-preset-%s-light-%s-look-0-rev-0.png"%[parts[1],parts[2],parts[3]]))
			check(control.get_data()==baseline.get_data(),"bark A smooth look returns exactly")
		return painted
	return await take(name)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	bind_bark(0)
	for guard: Dictionary in tree_guards:
		check(guard.visual.mesh==guard.mesh,"same tree mesh instance")
		check(hash(guard.mesh.surface_get_arrays(0))==guard.wood_arrays and hash(guard.mesh.surface_get_arrays(1))==guard.leaf_arrays,"all wood and foliage arrays unchanged")
		check(guard.mesh.surface_get_material(0)==guard.wood and guard.mesh.surface_get_material(1)==guard.leaf,"same tree material instances")
		check(shader_parameters(guard.wood,true)==guard.wood_parameters,"bark projection scale, paint, light, rim and pixel sampling unchanged")
		check(shader_parameters(guard.leaf,false)==guard.leaf_parameters,"all foliage B shader parameters unchanged")
		check(guard.wood.get_shader_parameter("painted_bark_albedo")==bark_controls[guard.wood.get_instance_id()],"original bark restored")
	check(bark_materials[0].get_shader_parameter("painted_bark_pixel_m")==0.0,"smooth bark has no pixel grid")
	check(bark_materials[1].get_shader_parameter("painted_bark_pixel_m")==0.0,"faceted bark has no pixel grid")
	check(is_equal_approx(bark_materials[2].get_shader_parameter("painted_bark_pixel_m"),1.0/16.0),"voxel bark keeps existing 6.25cm Source grid")
	result.erase("rock_pigment")
	result["bark"]={"master":BARK_PAINTED_PATH,"control":"accepted oak-v2-calm C","matrix_pairs":review_records.size(),"motion_frames":360,"exact_local_returns":bark_exact_returns,"smooth_cross_look_returns":36,"period_m":3.0,"voxel_pixel_m":1.0/16.0,"scope":"oak albedo only, shared unchanged master for all looks; existing branch projection and voxel sampling"}
	result["scope"]="one oak bark A/B in fixed environment; stone control A from paint-relief report, road B, soil v4, grass B; original tree geometry, foliage and common light"
	result["manual_acceptance"]="OPEN; bark B candidate only; stone flat/3mm and soil depth deferred"
	return result
