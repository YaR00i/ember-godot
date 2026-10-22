extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	# Deliberately bind the same authored pair to two different roles and slots.
	# The renderer must not depend on the word "stone" or palette slot 1.
	for role in ["stone","grass"]:
		var pattern=Materials.load_compact_terrain_variant("cartoon_stone").duplicate(true)
		pattern.role_id=role;pattern.pattern_size_m=1.35
		pattern.albedo_texture=load("res://content/terrain_materials/textures/material_depth_study/stone_color.png")
		# Isolate the explicit periodic-ID argument from authored sand defaults.
		var sand=Materials.load_compact_terrain_variant("cartoon_sand").duplicate(true)
		sand.albedo_periodic=false
		var material=Materials.compact_terrain_material()
		material.shader=Materials.compact_terrain_depth_shader()
		Materials.set_compact_terrain_roles(material,PackedStringArray(["","sand",role]),PackedStringArray(["","cartoon_sand","test_pair"]),PackedColorArray(),{"test_pair":pattern,"cartoon_sand":sand},PackedStringArray(["test_pair"]))
		var entry=(material.get_shader_parameter("png_lookup") as Texture2D).get_image().get_pixel(2,0)
		assert(entry.r>0.5 and is_equal_approx(entry.g,1.35) and entry.a==1.0)
		assert((material.get_shader_parameter("png_lookup") as Texture2D).get_image().get_pixel(1,0).a==0.0)
		var height: Texture2D=load("res://content/terrain_materials/textures/material_depth_study/stone_height.png")
		var coverage=Image.create(1,1,false,Image.FORMAT_RF);coverage.fill(Color(1,0,0))
		assert(Materials.bind_compact_terrain_depth(material,height,ImageTexture.create_from_image(coverage),Vector2i(2,1),0.025,48))
		assert(material.get_shader_parameter("material_depth_slots")==Vector2i(2,1))
		assert(is_equal_approx(material.get_shader_parameter("material_depth_amplitude_m"),0.025))
		assert(not Materials.bind_compact_terrain_depth(material,height,null,Vector2i(2,1),0.025))
		assert(not Materials.bind_compact_terrain_depth(material,height,ImageTexture.create_from_image(coverage),Vector2i(2,1),NAN))
		# Save authored Pattern, not a derived GPU texture bank. Headless has
		# no GPU readback for serializing ImageTextureLayered images.
		assert(ResourceSaver.save(pattern,"user://texture-pair-pattern.tres")==OK)
		var reopened=ResourceLoader.load("user://texture-pair-pattern.tres","",ResourceLoader.CACHE_MODE_IGNORE)
		assert(reopened.role_id==role and is_equal_approx(reopened.pattern_size_m,1.35))
		assert(reopened.albedo_texture.resource_path==pattern.albedo_texture.resource_path)
		assert(reopened.validation_errors().is_empty())
	print("MATERIAL_TEXTURE_MAPPING PASS shared roles/slots/scale/repeat/binding/validation/save-reopen")
	quit()
