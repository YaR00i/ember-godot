@tool
class_name EmberVoxelSurfaceMaterials
extends RefCounted
## Surface-only material ownership. Generic transparent voxel props keep using
## EmberVoxelPrefab; terrain water gets a world-locked stylized shader.

const VoxelPrefab = preload("res://scripts/ember_voxel_prefab.gd")
const WATER_MATERIAL_PATH := "res://materials/ember_voxel_surface_water.tres"
const FOAM_MATERIAL_PATH := "res://materials/ember_voxel_surface_foam.tres"
const CONTACT_MATERIAL_PATH := "res://materials/ember_water_contact.tres"
const WAKE_MATERIAL_PATH := "res://materials/ember_water_wake.tres"
const TERRAIN_SHADER_PATH := "res://shaders/ember_compact_terrain_textured.gdshader"
const TerrainPattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const TERRAIN_PATTERN_DIR := "res://content/terrain_materials"
const TERRAIN_PATTERN_PATHS := {
	"soil": "res://content/terrain_materials/soil.tres",
	"grass": "res://content/terrain_materials/grass.tres",
	"sand": "res://content/terrain_materials/sand.tres",
	"stone": "res://content/terrain_materials/stone.tres",
}


static func opaque_material() -> ShaderMaterial:
	return VoxelPrefab.voxel_material()


static func compact_terrain_material() -> ShaderMaterial:
	var shader := load(TERRAIN_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Ember Surface: compact terrain shader is missing")
		return opaque_material()
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


static func compact_terrain_depth_shader() -> Shader:
	# The same terrain renderer with an optional material-depth feature.
	# No role or prototype-specific shader implementation.
	var shader := Shader.new()
	shader.code = "#define EMBER_TERRAIN_MATERIAL_DEPTH\n" + (load(TERRAIN_SHADER_PATH) as Shader).code
	shader.set_meta("ember_compact_terrain_shader", true)
	return shader


static func bind_compact_terrain_depth(material: ShaderMaterial, height: Texture2D, coverage: Texture2D, slots: Vector2i, amplitude_m: float, steps := 32, fade_m := Vector2(6,14), origin_m := Vector2.ZERO, sun := Vector3.UP) -> bool:
	if material == null or material.shader == null or height == null or coverage == null or not material.shader.get_meta("ember_compact_terrain_shader", false): return false
	if slots.x < 1 or slots.x > 255 or slots.y < 1 or slots.y > 255 or not is_finite(amplitude_m) or amplitude_m < 0.0 or amplitude_m > 0.08: return false
	if not fade_m.is_finite() or fade_m.x < 0.0 or fade_m.y <= fade_m.x or not origin_m.is_finite() or not sun.is_finite() or sun.is_zero_approx(): return false
	material.set_shader_parameter("material_depth_enabled", amplitude_m > 0.00001)
	material.set_shader_parameter("material_depth_height", height)
	material.set_shader_parameter("material_depth_coverage", coverage)
	material.set_shader_parameter("material_depth_slots", slots)
	material.set_shader_parameter("material_depth_amplitude_m", amplitude_m)
	material.set_shader_parameter("material_depth_steps", clampi(steps,8,64))
	material.set_shader_parameter("material_depth_fade_near_m", fade_m.x)
	material.set_shader_parameter("material_depth_fade_far_m", fade_m.y)
	material.set_shader_parameter("material_depth_origin_m", origin_m)
	material.set_shader_parameter("material_depth_sun_direction", sun)
	return true


static func set_compact_terrain_roles(material: ShaderMaterial, roles: PackedStringArray, material_ids := PackedStringArray(), palette := PackedColorArray(), private_patterns := {}, periodic_material_ids := PackedStringArray()) -> void:
	if material == null or material.shader == null or (material.shader.resource_path != TERRAIN_SHADER_PATH and not material.shader.get_meta("ember_compact_terrain_shader", false)):
		return
	var lookup := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	var atlas := Image.create(16, 16 * 256, false, Image.FORMAT_RGBA8)
	var side_atlas := Image.create(16, 16 * 256, false, Image.FORMAT_RGBA8)
	var finish_lookup := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	finish_lookup.fill(Color(0.0, 0.0, 0.0, 1.0))
	var detail_lookup := Image.create(256, 1, false, Image.FORMAT_RGBAF)
	detail_lookup.fill(Color(0.0,0.09,0.0,0.0))
	var images: Dictionary = {}
	var png_lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var grass_light:=Image.create(256,4,false,Image.FORMAT_RGBAF)
	var has_grass_light:=false
	var png_mean:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var png_tint:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var palette_lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	for i in mini(palette.size(),256): palette_lookup.set_pixel(i,0,palette[i])
	var png_images: Array[Image]=[]
	var png_layers: Dictionary={}
	var png_means: Dictionary={}
	var max_size:=Vector2i.ONE
	var side_images: Dictionary = {}
	var patterns: Dictionary = {}
	var surface_lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF); surface_lookup.fill(Color(4,0,0,0))
	var rough_atlas:=Image.create(16,16*256,false,Image.FORMAT_R8); rough_atlas.fill(Color(0.5,0,0))
	var side_rough_atlas:=Image.create(16,16*256,false,Image.FORMAT_R8); side_rough_atlas.fill(Color(0.5,0,0))
	for index in mini(roles.size(), 256):
		var role := roles[index]
		if role.is_empty(): continue
		var id: String = material_ids[index] if index < material_ids.size() and not material_ids[index].is_empty() else role
		if not images.has(id):
			var pattern: TerrainPattern = private_patterns.get(id)
			if pattern == null: pattern = load_compact_terrain_variant(id)
			if pattern != null and pattern.role_id == role and pattern.validation_errors().is_empty():
				var image := pattern.to_image()
				var top_relief:=pattern.surface_pixels("relief")
				for y in 16:
					for x in 16:
						var color := image.get_pixel(x, y)
						color.a = [0.5, 1.0, 0.0][top_relief[x + y * 16]]
						image.set_pixel(x, y, color)
				images[id] = image
				var side_image := pattern.to_image(true)
				var side_artwork := pattern.surface_pixels("relief",true)
				for y in 16:
					for x in 16:
						var color := side_image.get_pixel(x, y)
						color.a = [0.5, 1.0, 0.0][side_artwork[x + y * 16]]
						side_image.set_pixel(x, y, color)
				side_images[id] = side_image
				patterns[id] = pattern
			else:
				images[id] = null
		var tile := images[id] as Image
		if tile == null: continue
		var finish := patterns[id] as TerrainPattern
		if finish.grass_light_enabled:
			has_grass_light=true
			grass_light.set_pixel(index,0,Color(finish.grass_light_low,finish.grass_light_tint_strength,finish.grass_light_shadow_fill,1))
			grass_light.set_pixel(index,1,finish.grass_light_cool)
			grass_light.set_pixel(index,2,finish.grass_light_warm)
			grass_light.set_pixel(index,3,finish.grass_light_shadow_color)
		if finish.albedo_texture != null:
			var texture_key:=finish.albedo_texture.get_instance_id()
			if not png_layers.has(texture_key):
				var png:=finish.albedo_texture.get_image()
				if png != null:
					if png.is_compressed(): png.decompress()
					png.convert(Image.FORMAT_RGBA8)
					var mean:=Color(0,0,0,0);var samples:=0
					for y in range(0,png.get_height(),16):
						for x in range(0,png.get_width(),16): mean+=png.get_pixel(x,y).srgb_to_linear();samples+=1
					png_means[texture_key]=mean/maxi(1,samples)
					png_layers[texture_key]=png_images.size()
					png_images.append(png)
					max_size=Vector2i(maxi(max_size.x,png.get_width()),maxi(max_size.y,png.get_height()))
			if png_layers.has(texture_key):
				# Alpha is derived sampling metadata, not a second material owner.
				png_lookup.set_pixel(index,0,Color(png_layers[texture_key]+1,finish.pattern_size_m,TerrainPattern.ROLE_IDS.find(role)+1,1.0 if id in periodic_material_ids else 0.0))
				png_mean.set_pixel(index,0,png_means[texture_key])
				png_tint.set_pixel(index,0,finish.base_color.srgb_to_linear())
		lookup.set_pixel(index, 0, Color8(1, 1 if not finish.side_pixels.is_empty() or not finish.relief_pixels.is_empty() or not finish.side_relief_pixels.is_empty() else 0, 1 if finish.role_id == "grass" else 2 if finish.role_id == "soil" else 0))
		atlas.blit_rect(tile, Rect2i(0, 0, 16, 16), Vector2i(0, index * 16))
		side_atlas.blit_rect(side_images[id], Rect2i(0, 0, 16, 16), Vector2i(0, index * 16))
		finish_lookup.set_pixel(index, 0, Color(finish.gloss, finish.sheen, finish.pixel_relief / 0.3, 1.0))
		detail_lookup.set_pixel(index,0,Color(finish.micro_relief,finish.micro_size_m,finish.micro_roughness,0.0))
		var custom:=not finish.relief_pixels.is_empty() or not finish.side_relief_pixels.is_empty() or not finish.roughness_pixels.is_empty() or not finish.side_roughness_pixels.is_empty() or not is_equal_approx(finish.pattern_size_m,4)
		surface_lookup.set_pixel(index,0,Color(finish.pattern_size_m,finish.roughness_variation,1.0 if custom else 0.0,0))
		for side in [false,true]:
			var rough:=finish.surface_image("roughness",side); rough.convert(Image.FORMAT_R8)
			(side_rough_atlas if side else rough_atlas).blit_rect(rough,Rect2i(0,0,16,16),Vector2i(0,index*16))
	if png_images.is_empty():
		var white:=Image.create(1,1,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE);png_images.append(white)
	for png: Image in png_images:
		if png.get_size()!=max_size: png.resize(max_size.x,max_size.y,Image.INTERPOLATE_LANCZOS)
		png.generate_mipmaps()
	var bank:=Texture2DArray.new()
	if bank.create_from_images(png_images)==OK: material.set_shader_parameter("png_albedo_bank",bank)
	material.set_shader_parameter("png_lookup",ImageTexture.create_from_image(png_lookup))
	material.set_shader_parameter("grass_light_lookup",ImageTexture.create_from_image(grass_light))
	material.set_shader_parameter("grass_light_profiles_enabled",has_grass_light)
	material.set_meta("ember_grass_light_image",grass_light)
	material.set_shader_parameter("png_mean_lookup",ImageTexture.create_from_image(png_mean))
	material.set_shader_parameter("png_tint_lookup",ImageTexture.create_from_image(png_tint))
	material.set_shader_parameter("palette_color_lookup",ImageTexture.create_from_image(palette_lookup))
	material.set_shader_parameter("role_lookup", ImageTexture.create_from_image(lookup))
	material.set_shader_parameter("pattern_atlas", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter("side_pattern_atlas", ImageTexture.create_from_image(side_atlas))
	material.set_shader_parameter("finish_lookup", ImageTexture.create_from_image(finish_lookup))
	material.set_shader_parameter("detail_lookup", ImageTexture.create_from_image(detail_lookup))
	material.set_shader_parameter("surface_lookup",ImageTexture.create_from_image(surface_lookup))
	material.set_shader_parameter("roughness_atlas",ImageTexture.create_from_image(rough_atlas))
	material.set_shader_parameter("side_roughness_atlas",ImageTexture.create_from_image(side_rough_atlas))
	material.set_shader_parameter("independent_surface_enabled",true)


static func update_grass_light_profile(material: ShaderMaterial, slot: int, pattern: TerrainPattern) -> void:
	if material==null or slot<1 or slot>255 or pattern==null or not pattern.validation_errors().is_empty():return
	var image: Image=material.get_meta("ember_grass_light_image",null)
	var texture: ImageTexture=material.get_shader_parameter("grass_light_lookup")
	if image==null or texture==null:return
	image.set_pixel(slot,0,Color(pattern.grass_light_low,pattern.grass_light_tint_strength,pattern.grass_light_shadow_fill,1.0 if pattern.grass_light_enabled else 0.0))
	image.set_pixel(slot,1,pattern.grass_light_cool);image.set_pixel(slot,2,pattern.grass_light_warm);image.set_pixel(slot,3,pattern.grass_light_shadow_color)
	texture.update(image)
	var enabled:=false
	for i in 256:
		if image.get_pixel(i,0).a>0.5:enabled=true;break
	material.set_shader_parameter("grass_light_profiles_enabled",enabled)


static func load_compact_terrain_pattern(role: String) -> TerrainPattern:
	if not TERRAIN_PATTERN_PATHS.has(role):
		return null
	return load_compact_terrain_variant(role)


static func variant_path(id: String) -> String:
	return "%s/%s.tres" % [TERRAIN_PATTERN_DIR, id] if id.is_valid_identifier() else ""


static func load_compact_terrain_variant(id: String) -> TerrainPattern:
	var path := variant_path(id)
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as TerrainPattern


static func variants_for_role(role: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(TERRAIN_PATTERN_DIR)
	if directory == null: return result
	for filename in directory.get_files():
		if not filename.ends_with(".tres"): continue
		var id := filename.get_basename()
		var pattern := load_compact_terrain_variant(id)
		if pattern != null and pattern.role_id == role and pattern.validation_errors().is_empty():
			result.append(id)
	result.sort()
	return result


static func water_material() -> ShaderMaterial:
	var material := load(WATER_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: water material is missing; using generic transparency")
	return VoxelPrefab.voxel_transparent_material()


static func foam_material() -> ShaderMaterial:
	var material := load(FOAM_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: foam material is missing; using water material")
	return water_material()


static func contact_material() -> ShaderMaterial:
	var material := load(CONTACT_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: contact material is missing; using foam material")
	return foam_material()


static func wake_material() -> ShaderMaterial:
	var material := load(WAKE_MATERIAL_PATH) as ShaderMaterial
	if material != null:
		return material
	push_warning("Ember Surface: water wake material is missing; using contact material")
	return contact_material()
