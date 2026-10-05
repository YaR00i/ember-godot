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


static func set_compact_terrain_roles(material: ShaderMaterial, roles: PackedStringArray, material_ids := PackedStringArray()) -> void:
	if material == null or material.shader == null or material.shader.resource_path != TERRAIN_SHADER_PATH:
		return
	var lookup := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	var atlas := Image.create(16, 16 * 256, false, Image.FORMAT_RGBA8)
	var side_atlas := Image.create(16, 16 * 256, false, Image.FORMAT_RGBA8)
	var finish_lookup := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	finish_lookup.fill(Color(0.0, 0.0, 0.0, 1.0))
	var images: Dictionary = {}
	var side_images: Dictionary = {}
	var patterns: Dictionary = {}
	for index in mini(roles.size(), 256):
		var role := roles[index]
		if role.is_empty(): continue
		var id: String = material_ids[index] if index < material_ids.size() and not material_ids[index].is_empty() else role
		if not images.has(id):
			var pattern := load_compact_terrain_variant(id)
			if pattern != null and pattern.role_id == role and pattern.validation_errors().is_empty():
				var image := pattern.to_image()
				for y in 16:
					for x in 16:
						var color := image.get_pixel(x, y)
						color.a = [0.5, 1.0, 0.0][pattern.pixels[x + y * 16]]
						image.set_pixel(x, y, color)
				images[id] = image
				var side_image := pattern.to_image(true)
				var side_artwork := pattern.face_pixels(true)
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
		lookup.set_pixel(index, 0, Color8(1, 1 if not finish.side_pixels.is_empty() else 0, 0))
		atlas.blit_rect(tile, Rect2i(0, 0, 16, 16), Vector2i(0, index * 16))
		side_atlas.blit_rect(side_images[id], Rect2i(0, 0, 16, 16), Vector2i(0, index * 16))
		finish_lookup.set_pixel(index, 0, Color(finish.gloss, finish.sheen, finish.pixel_relief / 0.3, 1.0))
	material.set_shader_parameter("role_lookup", ImageTexture.create_from_image(lookup))
	material.set_shader_parameter("pattern_atlas", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter("side_pattern_atlas", ImageTexture.create_from_image(side_atlas))
	material.set_shader_parameter("finish_lookup", ImageTexture.create_from_image(finish_lookup))


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
