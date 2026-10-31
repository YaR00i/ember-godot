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
const GRASS_SHADER_PATH := "res://shaders/ember_compact_grass.gdshader"
const FLOWER_SHADER_PATH := "res://shaders/ember_compact_flower.gdshader"
const GRASS_MATERIAL_PATH := "res://materials/ember_compact_grass.tres"
const FLOWER_MATERIAL_PATH := "res://materials/ember_compact_flower.tres"
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


static var _bank_depth_shader: Shader
static var _bank_far_shader: Shader
static var _grass_shader: Shader
static var _flower_shader: Shader
static var _bank_height_images := {}
const DEPTH_IMAGE_LIMIT := 16
const DEPTH_IMAGE_BYTES := 24 * 1024 * 1024
static var _depth_sources: Dictionary = {}
static var _depth_source_registrations := 0

static func _forget_depth_images(id: int) -> void:
	var prefix := str(id) + "|"
	for key: String in _bank_height_images.keys():
		if key.begins_with(prefix): _bank_height_images.erase(key)

static func _depth_pixels_changed(id: int) -> void:
	if _depth_sources.has(id): _depth_sources[id].revision += 1
	_forget_depth_images(id)

static func _depth_revision(texture: Texture2D) -> int:
	var id := texture.get_instance_id()
	if not _depth_sources.has(id):
		_depth_source_registrations += 1
		if _depth_source_registrations >= 16:
			_depth_source_registrations = 0
			for previous: int in _depth_sources.keys():
				if (_depth_sources[previous].source as WeakRef).get_ref() == null:
					_forget_depth_images(previous)
					_depth_sources.erase(previous)
		_depth_sources[id] = {"source": weakref(texture), "revision": 0}
		var changed := _depth_pixels_changed.bind(id)
		if not texture.changed.is_connected(changed): texture.changed.connect(changed)
	return int(_depth_sources[id].revision)

static func depth_cache_bytes() -> int:
	var bytes := 0
	for image: Image in _bank_height_images.values(): bytes += image.get_data_size()
	return bytes

static func _depth_image(key: String) -> Image:
	var image := _bank_height_images.get(key) as Image
	if image != null:
		_bank_height_images.erase(key)
		_bank_height_images[key] = image # LRU, only the main thread touches it.
	return image

static func _store_depth_image(key: String, image: Image) -> void:
	_bank_height_images.erase(key)
	if image.get_data_size() > DEPTH_IMAGE_BYTES: return
	_bank_height_images[key] = image
	while _bank_height_images.size() > DEPTH_IMAGE_LIMIT or depth_cache_bytes() > DEPTH_IMAGE_BYTES:
		_bank_height_images.erase(_bank_height_images.keys()[0])

static var _bank_height_textures := {}
static var _png_banks:Dictionary={}


## Only immutable artwork layers are shared. Every material still owns its
## editable slot/lighting/tint lookup textures and CPU preview images.
static func _clear_png_banks()->void:
	_png_banks.clear()


static func _png_bank(sources:Array[Texture2D])->Dictionary:
	var key:=PackedInt64Array()
	for source in sources:
		key.append(source.get_instance_id())
		if not source.changed.is_connected(_clear_png_banks):source.changed.connect(_clear_png_banks)
	var cached:Dictionary=_png_banks.get(key,{})
	var reference:WeakRef=cached.get("bank")
	var bank:Texture2DArray=reference.get_ref() if reference!=null else null
	if bank!=null:return {"bank":bank,"layers":cached.layers,"means":cached.means}
	var images:Array[Image]=[];var layers:Dictionary={};var means:Dictionary={}
	var max_size:=Vector2i.ONE
	for source in sources:
		var image:=source.get_image()
		if image==null:continue
		image=image.duplicate() as Image
		if image.is_compressed():image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var mean:=Color(0,0,0,0);var samples:=0
		for y in range(0,image.get_height(),16):
			for x in range(0,image.get_width(),16):mean+=image.get_pixel(x,y).srgb_to_linear();samples+=1
		var id:=source.get_instance_id()
		means[id]=mean/maxi(1,samples);layers[id]=images.size();images.append(image)
		max_size=Vector2i(maxi(max_size.x,image.get_width()),maxi(max_size.y,image.get_height()))
	if images.is_empty():
		var white:=Image.create(1,1,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE);images.append(white)
	for image in images:
		if image.get_size()!=max_size:image.resize(max_size.x,max_size.y,Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
	bank=Texture2DArray.new()
	if bank.create_from_images(images)!=OK:return {"bank":null,"layers":layers,"means":means}
	# Keep source identity stable while any consumer owns the derived bank.
	bank.set_meta("ember_png_sources",sources.duplicate())
	if _png_banks.size()>=16:_png_banks.erase(_png_banks.keys()[0])
	_png_banks[key]={"bank":weakref(bank),"layers":layers,"means":means}
	return {"bank":bank,"layers":layers,"means":means}

static func compact_grass_material() -> ShaderMaterial:
	var material:ShaderMaterial=load(GRASS_MATERIAL_PATH).duplicate()
	_grass_shader=material.shader
	_grass_shader.set_meta("ember_compact_terrain_shader",true)
	return material


static func compact_flower_material() -> ShaderMaterial:
	var material:ShaderMaterial=load(FLOWER_MATERIAL_PATH).duplicate()
	_flower_shader=material.shader
	_flower_shader.set_meta("ember_compact_terrain_shader",true)
	return material

# Scene/profile commands refresh these compiled features. Texture contents,
# light colours, fades and anomaly positions remain ordinary live uniforms.
const TERRAIN_FEATURE_FIELDS := ["grass_light_profiles_enabled", "style_rim_profiles_enabled", "independent_surface_enabled", "smooth_surface_enabled", "painterly_blades", "material_light_mode", "material_gray_preview", "voxel_light_enabled", "voxel_light_anomaly", "look_study_mode"]
const TERRAIN_FEATURE_PROGRAM_LIMIT := 32
static var _terrain_feature_programs: Dictionary = {}

static func refresh_existing_terrain_features(material: ShaderMaterial) -> void:
	if material != null and material.shader != null and material.shader.has_meta("ember_feature_base"):
		refresh_terrain_features(material)

## Finalize a published terrain/card binding, or refresh after its feature command.
## Original uniform declarations and values remain available to preview/save.
static func refresh_terrain_features(material: ShaderMaterial) -> void:
	if material == null or material.shader == null: return
	var base: Shader = material.shader.get_meta("ember_feature_base", material.shader)
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		if material.shader != base: material.shader = base
		return
	if base.resource_path not in [GRASS_SHADER_PATH, FLOWER_SHADER_PATH] and not base.get_meta("ember_terrain_cheap", false): return
	var declared: Dictionary = {}
	for entry in base.get_shader_uniform_list(): declared[str(entry.name)] = true
	var features: Dictionary = {}
	for field: String in TERRAIN_FEATURE_FIELDS:
		if not declared.has(field): continue
		var value: Variant = material.get_shader_parameter(field)
		if value == null: value = RenderingServer.shader_get_parameter_default(base.get_rid(), field)
		if not (value is bool or value is int):
			material.shader = base
			return
		features[field] = value
	var key := str(base.get_instance_id()) + ":" + str(base.code.hash()) + ":" + JSON.stringify(features)
	if material.shader.get_meta("ember_feature_key", "") == key: return
	var program: Shader = _terrain_feature_programs.get(key)
	if program == null:
		var code := _expand_terrain_feature_code(base.code)
		if code.is_empty():
			material.shader = base
			return
		var declarations: Dictionary = {}
		for field: String in features:
			var expression := RegEx.create_from_string("uniform\\s+(bool|int)\\s+" + field + "\\b[^;]*;")
			var found := expression.search(code)
			if found == null:
				material.shader = base
				return
			var marker := "EMBER_FEATURE_DECL_" + field
			declarations[marker] = found.get_string()
			code = expression.sub(code, marker, true)
		for field: String in features:
			var alias := "ember_fixed_" + field
			code = RegEx.create_from_string("\\b" + field + "\\b").sub(code, alias, true)
			var value: Variant = features[field]
			var type := "bool" if value is bool else "int"
			var literal := ("true" if value else "false") if value is bool else str(value)
			var marker := "EMBER_FEATURE_DECL_" + field
			code = code.replace(marker, declarations[marker] + "\nconst " + type + " " + alias + " = " + literal + ";")
		program = Shader.new()
		program.code = code
		for name in base.get_meta_list(): program.set_meta(name, base.get_meta(name))
		program.set_meta("ember_feature_base", base)
		program.set_meta("ember_feature_key", key)
		program.set_meta("ember_feature_values", features)
	else:
		_terrain_feature_programs.erase(key)
	_terrain_feature_programs[key] = program
	while _terrain_feature_programs.size() > TERRAIN_FEATURE_PROGRAM_LIMIT:
		_terrain_feature_programs.erase(_terrain_feature_programs.keys()[0])
	# ShaderMaterial retains its parameter cache and both programs declare the
	# same uniforms. No new textures, profile images or material copies here.
	material.shader = program

static func _expand_terrain_feature_code(code: String) -> String:
	var lines := PackedStringArray()
	for line in code.split("\n"):
		if line.strip_edges().begins_with("#include "):
			# ResourceLoader also follows imported/exported ShaderInclude paths.
			var included := load(line.get_slice('"', 1)) as ShaderInclude
			if included == null: return ""
			var expanded := _expand_terrain_feature_code(included.code)
			if expanded.is_empty() and not included.code.is_empty(): return ""
			lines.append(expanded)
		else: lines.append(line)
	return "\n".join(lines)

static func compact_terrain_bank_depth_shader() -> Shader:
	if _bank_depth_shader == null:
		_bank_depth_shader = Shader.new()
		_bank_depth_shader.code = "#define EMBER_TERRAIN_BANK_DEPTH\n#define EMBER_TERRAIN_MATERIAL_DEPTH\n#define EMBER_MATERIAL_LOOK_STUDY\n" + (load(TERRAIN_SHADER_PATH) as Shader).code
		_bank_depth_shader.set_meta("ember_compact_terrain_shader", true)
		_bank_depth_shader.set_meta("ember_terrain_bank_depth", true)
	return _bank_depth_shader


static func compact_terrain_bank_far_shader() -> Shader:
	if _bank_far_shader==null:
		_bank_far_shader=Shader.new()
		# The same artwork, blending and light implementation, without the
		# parallax feature or a manual DEPTH output. No second renderer.
		_bank_far_shader.code="#define EMBER_TERRAIN_CHEAP\n#define EMBER_TERRAIN_BANK_DEPTH\n#define EMBER_MATERIAL_LOOK_STUDY\n"+(load(TERRAIN_SHADER_PATH) as Shader).code
		_bank_far_shader.set_meta("ember_compact_terrain_shader",true)
		_bank_far_shader.set_meta("ember_terrain_cheap",true)
	return _bank_far_shader


static func compact_terrain_far_material(base:ShaderMaterial)->ShaderMaterial:
	var result:=base.duplicate() as ShaderMaterial
	result.shader=compact_terrain_bank_far_shader()
	# Assigning a shader must not rely on editor parameter-retention behaviour.
	var source_names:Dictionary={}
	for item in base.shader.get_shader_uniform_list():source_names[item.name]=true
	for item in result.shader.get_shader_uniform_list():
		if source_names.has(item.name):result.set_shader_parameter(item.name,base.get_shader_parameter(item.name))
	refresh_terrain_features(result)
	return result


## Per-material settings use the existing bounded parallax solver, not a second renderer.
const MaterialHeight = preload("res://scripts/ember_material_height.gd")

class DepthPreparationJob extends RefCounted:
	var recipes: Array[Dictionary] = []
	var images: Dictionary = {}
	var height_results: Array[Dictionary] = []
	var stale := false # Main-thread publication guard; no worker access.
	func run() -> void:
		for recipe: Dictionary in recipes:
			var image := recipe.image as Image
			if image.is_compressed(): image.decompress()
			image.resize(recipe.size, recipe.size, Image.INTERPOLATE_LANCZOS)
			if not recipe.explicit:
				var result := MaterialHeight.read_bake(image, recipe.softness, recipe.sharpness, recipe.directory)
				height_results.append(result)
				image = result.image.duplicate() as Image
			image.convert(Image.FORMAT_R8)
			image.generate_mipmaps()
			images[recipe.key] = image
		recipes.clear()

static func _depth_image_key(texture: Texture2D, pattern: TerrainPattern, bank_size: int) -> String:
	return "%d|%d|%.3f|%.3f|%s|%d" % [texture.get_instance_id(), _depth_revision(texture), pattern.depth_softness, pattern.depth_sharpness, str(pattern.depth_texture != null),bank_size]

## Snapshot textures on main. The job owns only private Images and numeric
## recipes; returned Resource references stay with the map's publication guard.
static func depth_preparation(roles: PackedStringArray, ids: PackedStringArray, bank_size := 1024) -> Dictionary:
	var job := DepthPreparationJob.new()
	var sources: Array[Texture2D] = []
	var queued := {}
	for slot in roles.size():
		var id: String = ids[slot] if slot < ids.size() and not ids[slot].is_empty() else roles[slot]
		var pattern := load_compact_terrain_variant(id) if not id.is_empty() else null
		if pattern == null or pattern.depth_mm <= 0 or pattern.albedo_texture == null: continue
		var texture := pattern.depth_texture if pattern.depth_texture != null else pattern.albedo_texture
		var key := _depth_image_key(texture, pattern, bank_size)
		if _bank_height_images.has(key) or queued.has(key): continue
		var image := texture.get_image()
		if image == null: continue
		queued[key] = true
		sources.append(texture)
		job.recipes.append({"key":key,"image":image.duplicate(),"size":bank_size,"explicit":pattern.depth_texture!=null,"softness":pattern.depth_softness,"sharpness":pattern.depth_sharpness,"directory":MaterialHeight.cache_directory})
	return {"job":job,"sources":sources}

static func publish_depth_preparation(job: DepthPreparationJob) -> void:
	if job.stale: return
	for key: String in job.images:
		if not _bank_height_images.has(key): _store_depth_image(key, job.images[key])
	for result: Dictionary in job.height_results: MaterialHeight.remember_bake(result)

## Only a changed height image uploads the bank; dragging amplitude updates the tiny lookup.
static func set_terrain_depth_profiles(material: ShaderMaterial, roles: PackedStringArray, ids: PackedStringArray, overrides := {}) -> void:
	if material == null or material.shader == null: return
	var solid:bool=material.get_meta("ember_detailed_depth",false)
	if not solid and not material.shader.get_meta("ember_terrain_bank_depth", false): return
	# Solids keep the previous detailed height resolution; ground keeps its bounded256px bank.
	var bank_size:=1024 if solid else 256
	var profiles := Image.create(256, 1, false, Image.FORMAT_RGBAF)
	var images: Array[Image] = []
	var keys: Array[String] = []
	var source_textures: Array[Texture2D] = []
	for slot in roles.size():
		var id: String = ids[slot] if slot < ids.size() and not ids[slot].is_empty() else roles[slot]
		var pattern: TerrainPattern = overrides.get(id)
		if pattern == null and not id.is_empty(): pattern = load_compact_terrain_variant(id)
		if pattern == null or pattern.depth_mm <= 0 or pattern.albedo_texture == null: continue
		var texture := pattern.depth_texture if pattern.depth_texture != null else pattern.albedo_texture
		var key := _depth_image_key(texture, pattern, bank_size)
		var ready_image := _depth_image(key)
		if ready_image == null:
			var image: Image = texture.get_image().duplicate()
			if image.is_compressed(): image.decompress()
			image.resize(bank_size, bank_size, Image.INTERPOLATE_LANCZOS)
			if pattern.depth_texture == null: image = preload("res://scripts/ember_material_height.gd").cached_bake(image, pattern.depth_softness, pattern.depth_sharpness)
			image.convert(Image.FORMAT_R8)
			image.generate_mipmaps()
			_store_depth_image(key, image)
			ready_image = image
		var layer := keys.find(key)
		if layer < 0:
			layer = keys.size()
			keys.append(key)
			images.append(ready_image)
			source_textures.append(texture)
		profiles.set_pixel(slot, 0, Color(layer+1, pattern.depth_mm*0.001, 0, 0))
	if images.is_empty():
		var image := Image.create(bank_size, bank_size, true, Image.FORMAT_R8)
		image.fill(Color(0.5, 0, 0))
		images.append(image)
	if not material.has_meta("ember_depth_keys") or keys != material.get_meta("ember_depth_keys"):
		# Identical recipes share immutable GPU layers; only numeric profiles are instance-local.
		var bank_key:="%d|%s" % [bank_size,";".join(keys)]
		var cached:WeakRef=_bank_height_textures.get(bank_key)
		var bank:Texture2DArray=cached.get_ref() if cached!=null else null
		if bank==null:
			bank=Texture2DArray.new()
			if bank.create_from_images(images)!=OK:return
			if _bank_height_textures.size()>=32:_bank_height_textures.erase(_bank_height_textures.keys()[0])
			_bank_height_textures[bank_key]=weakref(bank)
		material.set_shader_parameter("terrain_depth_bank", bank)
		material.set_meta("ember_depth_keys", keys)
	# The derived bank stores Images, so retain its source textures as well.
	# Otherwise unreferenced PNGs reload with new instance IDs on a size/amplitude
	# edit, invalidating unchanged height layers and forcing a complete re-upload.
	material.set_meta("ember_depth_source_textures", source_textures)
	var lookup := material.get_shader_parameter("terrain_depth_profiles") as ImageTexture
	if lookup == null: material.set_shader_parameter("terrain_depth_profiles", ImageTexture.create_from_image(profiles))
	else: lookup.update(profiles)
	material.set_meta("ember_depth_profiles", profiles)
	material.set_shader_parameter("material_depth_bank_enabled",true)
	material.set_shader_parameter("material_depth_enabled", not keys.is_empty())


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


static func compact_terrain_secondary_depth_shader(base: Shader) -> Shader:
	if base==null or not base.code.contains("#define EMBER_TERRAIN_MATERIAL_DEPTH"):return null
	var shader:=Shader.new()
	shader.code="#define EMBER_TERRAIN_SECONDARY_DEPTH\n"+base.code
	shader.set_meta("ember_compact_terrain_shader",true)
	shader.set_meta("ember_secondary_depth_shader",true)
	return shader


static func bind_compact_terrain_secondary_depth(material: ShaderMaterial,height: Texture2D,coverage: Texture2D,slots: Vector2i,amplitude_m: float,sun:=Vector3.UP) -> bool:
	if material==null or material.shader==null or not material.shader.get_meta("ember_secondary_depth_shader",false) or height==null or coverage==null:return false
	if slots.x<1 or slots.x>255 or slots.y<1 or slots.y>255 or not is_finite(amplitude_m) or amplitude_m<0.0 or amplitude_m>0.08 or not sun.is_finite() or sun.is_zero_approx():return false
	material.set_shader_parameter("material_depth_secondary_enabled",amplitude_m>0.00001)
	material.set_shader_parameter("material_depth_secondary_height",height)
	material.set_shader_parameter("material_depth_secondary_coverage",coverage)
	material.set_shader_parameter("material_depth_secondary_slots",slots)
	material.set_shader_parameter("material_depth_secondary_amplitude_m",amplitude_m)
	material.set_shader_parameter("material_depth_secondary_sun_direction",sun)
	return true


static func set_compact_terrain_roles(material: ShaderMaterial, roles: PackedStringArray, material_ids := PackedStringArray(), palette := PackedColorArray(), private_patterns := {}, periodic_material_ids := PackedStringArray()) -> void:
	if material == null or material.shader == null or (material.shader.resource_path != TERRAIN_SHADER_PATH and not material.shader.get_meta("ember_compact_terrain_shader", false)):
		return
	apply_prepared_terrain_roles(material,prepare_terrain_roles(roles,material_ids,palette,private_patterns,periodic_material_ids),false)


static func terrain_role_texture_revisions(patterns:Dictionary)->PackedInt64Array:
	var stamp:=PackedInt64Array()
	for pattern:TerrainPattern in patterns.values():
		for texture:Texture2D in [pattern.albedo_texture,pattern.depth_texture]:
			stamp.append(texture.get_instance_id() if texture!=null else 0)
			stamp.append(_depth_revision(texture) if texture!=null else 0)
	return stamp


static func prepare_terrain_roles(roles: PackedStringArray, material_ids := PackedStringArray(), palette := PackedColorArray(), private_patterns := {}, periodic_material_ids := PackedStringArray()) -> Dictionary:
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
	var rim_lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var has_rim:=false
	var png_mean:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var png_tint:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	var palette_lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	for i in mini(palette.size(),256): palette_lookup.set_pixel(i,0,palette[i])
	var png_sources:Array[Texture2D]=[]
	var png_slots:Array=[]
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
		if finish.style_rim_custom:
			has_rim=true
			rim_lookup.set_pixel(index,0,Color(1,1 if finish.style_rim_enabled else 0,finish.style_rim_strength,finish.style_rim_width_mm*0.001))
		if finish.grass_light_enabled:
			has_grass_light=true
			grass_light.set_pixel(index,0,Color(finish.grass_light_low,finish.grass_light_tint_strength,finish.grass_light_shadow_fill,1))
			grass_light.set_pixel(index,1,finish.grass_light_cool)
			grass_light.set_pixel(index,2,finish.grass_light_warm)
			# The unused lookup alpha carries the same metre span as the artwork.
			var shadow := finish.grass_light_shadow_color
			shadow.a = finish.pattern_size_m
			grass_light.set_pixel(index,3,shadow)
		if finish.albedo_texture != null:
			if not finish.albedo_texture in png_sources:png_sources.append(finish.albedo_texture)
			var png_role:=float(TerrainPattern.ROLE_IDS.find(role)+1)
			png_slots.append({"slot":index,"source":finish.albedo_texture.get_instance_id(),"size":finish.pattern_size_m,"role":png_role if finish.albedo_relief_enabled else -png_role,"periodic":1.0 if finish.albedo_periodic or id in periodic_material_ids else 0.0,"tint":finish.base_color.srgb_to_linear()})
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
	var png_bank:=_png_bank(png_sources)
	for entry:Dictionary in png_slots:
		if not png_bank.layers.has(entry.source):continue
		# Signed role preserves the colour-only PNG/optical-height contract.
		png_lookup.set_pixel(entry.slot,0,Color(png_bank.layers[entry.source]+1,entry.size,entry.role,entry.periodic))
		png_mean.set_pixel(entry.slot,0,png_bank.means[entry.source])
		png_tint.set_pixel(entry.slot,0,entry.tint)
	return {"images":{"png_lookup":png_lookup,"grass_light_lookup":grass_light,"style_rim_lookup":rim_lookup,"png_mean_lookup":png_mean,"png_tint_lookup":png_tint,"palette_color_lookup":palette_lookup,"role_lookup":lookup,"pattern_atlas":atlas,"side_pattern_atlas":side_atlas,"finish_lookup":finish_lookup,"detail_lookup":detail_lookup,"surface_lookup":surface_lookup,"roughness_atlas":rough_atlas,"side_roughness_atlas":side_rough_atlas},"png_bank":png_bank.bank,"png_sources":png_sources,"has_grass_light":has_grass_light,"has_rim":has_rim}


static func apply_prepared_terrain_roles(material:ShaderMaterial,prepared:Dictionary,private_images:=true)->void:
	if material==null or material.shader==null or (material.shader.resource_path!=TERRAIN_SHADER_PATH and not material.shader.get_meta("ember_compact_terrain_shader",false)):return
	# Every binding owns its textures. Only these four CPU images are editable
	# through live profile APIs; never let one binding mutate the saved payload.
	var metadata:Dictionary={"grass_light_lookup":"ember_grass_light_image","png_lookup":"ember_png_lookup_image","surface_lookup":"ember_surface_lookup_image","style_rim_lookup":"ember_style_rim_image"}
	for uniform:String in prepared.images:
		var image:Image=prepared.images[uniform]
		if metadata.has(uniform):
			if private_images:image=image.duplicate() as Image
			material.set_meta(metadata[uniform],image)
		material.set_shader_parameter(uniform,ImageTexture.create_from_image(image))
	var bank:=prepared.png_bank.get_ref() as Texture2DArray if prepared.png_bank is WeakRef else prepared.png_bank as Texture2DArray
	if bank==null:bank=_png_bank(prepared.png_sources).bank
	if bank!=null:
		material.set_shader_parameter("png_albedo_bank",bank)
		# Saved CPU packing must not retain a large GPU bank after its last
		# consumer leaves. The existing shared bank owner already uses weak refs.
		prepared.png_bank=weakref(bank)
	material.set_shader_parameter("material_grass_coverage",load("res://content/terrain_materials/textures/grass-edge-coverage.png"))
	material.set_shader_parameter("grass_light_profiles_enabled",prepared.has_grass_light)
	material.set_shader_parameter("style_rim_profiles_enabled",prepared.has_rim)
	material.set_shader_parameter("independent_surface_enabled",true)
	refresh_existing_terrain_features(material)


static func update_grass_light_profile(material: ShaderMaterial, slot: int, pattern: TerrainPattern) -> void:
	if material==null or slot<1 or slot>255 or pattern==null or not pattern.validation_errors().is_empty():return
	var image: Image=material.get_meta("ember_grass_light_image",null)
	var texture: ImageTexture=material.get_shader_parameter("grass_light_lookup")
	if image==null or texture==null:return
	image.set_pixel(slot,0,Color(pattern.grass_light_low,pattern.grass_light_tint_strength,pattern.grass_light_shadow_fill,1.0 if pattern.grass_light_enabled else 0.0))
	image.set_pixel(slot,1,pattern.grass_light_cool);image.set_pixel(slot,2,pattern.grass_light_warm)
	var shadow := pattern.grass_light_shadow_color
	shadow.a = pattern.pattern_size_m
	image.set_pixel(slot,3,shadow)
	texture.update(image)
	# Live grass-size preview must agree with save/reload for colour and POM too.
	# Keep CPU lookup images beside the existing grass lookup, avoiding GPU readback.
	if pattern.role_id == "grass":
		for spec in [["png_lookup", "ember_png_lookup_image", 1], ["surface_lookup", "ember_surface_lookup_image", 0]]:
			var lookup_image: Image = material.get_meta(spec[1], null)
			var lookup_texture: ImageTexture = material.get_shader_parameter(spec[0])
			if lookup_image == null or lookup_texture == null: continue
			var entry := lookup_image.get_pixel(slot, 0)
			entry[spec[2]] = pattern.pattern_size_m
			lookup_image.set_pixel(slot, 0, entry)
			lookup_texture.update(lookup_image)
	var enabled:=false
	for i in 256:
		if image.get_pixel(i,0).a>0.5:enabled=true;break
	material.set_shader_parameter("grass_light_profiles_enabled",enabled)
	refresh_existing_terrain_features(material)


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


static func update_style_rim_profile(material: ShaderMaterial, slot: int, pattern: TerrainPattern) -> void:
	if material==null or slot<1 or slot>255 or pattern==null or not pattern.validation_errors().is_empty(): return
	var image: Image=material.get_meta("ember_style_rim_image",null)
	var texture: ImageTexture=material.get_shader_parameter("style_rim_lookup")
	if image==null or texture==null: return
	image.set_pixel(slot,0,Color(1 if pattern.style_rim_custom else 0,1 if pattern.style_rim_enabled else 0,pattern.style_rim_strength,pattern.style_rim_width_mm*0.001))
	texture.update(image)
	var enabled:=false
	for i in 256:
		if image.get_pixel(i,0).r>0.5: enabled=true;break
	material.set_shader_parameter("style_rim_profiles_enabled",enabled)
	refresh_existing_terrain_features(material)
