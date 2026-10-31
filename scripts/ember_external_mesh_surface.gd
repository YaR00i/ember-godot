extends RefCounted
## Optional provenance and prepared appearances of the same editable voxel Source.
const CONTRACT := "external-static-mesh-v1"

static func fingerprint(source: EmberVoxelModelResource) -> String:
	# Include paint and grid frame: an unchanged occupancy alone is insufficient.
	return var_to_bytes([source.grid_size(),source.normalized_density(),source.voxels,source.palette,source.solid_surface.get("roles",PackedStringArray()),source.solid_surface.get("material_ids",PackedStringArray()),source.shine,source.emissive,source.transparency,source.transmittance,source.surface_fill_levels,source.surface_fill_materials,source.surface_fill_palette,JSON.stringify(source.material,"",true,true)]).hex_encode().sha256_text()

static func validation_errors(profile: Dictionary) -> Array[String]:
	var errors: Array[String]=[]
	if profile.get("version",0)!=1: errors.append("unsupported external mesh version")
	for key in ["original","detailed","low_poly"]:
		var path: Variant=profile.get(key,"")
		if not path is String or not path.begins_with("res://content/") or "/../" in path: errors.append("invalid external mesh path: "+key)
	for key in ["original_hash","voxel_baseline"]:
		var value: Variant=profile.get(key,"")
		if not value is String or value.length()!=64 or not value.is_valid_hex_number():errors.append("invalid external mesh hash: "+key)
	return errors

static func pristine(source: EmberVoxelModelResource) -> bool:
	return not source.external_surface.is_empty() and source.external_surface.get("voxel_baseline","")==fingerprint(source)

static func prepared(source: EmberVoxelModelResource, look: int) -> ArrayMesh:
	if look not in [0,1] or not pristine(source):return null
	return load(source.external_surface["detailed" if look==0 else "low_poly"]) as ArrayMesh

static func can_reprepare(source: EmberVoxelModelResource) -> bool:
	return source.external_surface.is_empty() or pristine(source)


## Disposable display adapter for the first opaque, UV/albedo rock. The
## StandardMaterial and its texture stay owned by the immutable prepared mesh.
static func anomaly_material(original: Material, voxel_material: ShaderMaterial) -> ShaderMaterial:
	if not original is StandardMaterial3D:return null
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/ember_external_surface.gdshader")
	material.set_shader_parameter("albedo",original.albedo_color)
	material.set_shader_parameter("texture_albedo",original.albedo_texture)
	material.set_shader_parameter("has_albedo_texture",original.albedo_texture!=null)
	material.set_shader_parameter("roughness",original.roughness)
	material.set_shader_parameter("metallic",original.metallic)
	material.set_shader_parameter("specular",original.metallic_specular)
	material.set_shader_parameter("uv1_scale",original.uv1_scale)
	material.set_shader_parameter("uv1_offset",original.uv1_offset)
	material.set_shader_parameter("palette_color_lookup",voxel_material.get_shader_parameter("palette_color_lookup"))
	return material
