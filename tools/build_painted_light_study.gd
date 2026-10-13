extends SceneTree
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
func _initialize() -> void:
	assert(ResourceSaver.save(Fixture.source(), "res://content/world_terrains/painted_light_study.res") == OK)
	var grass := Pattern.new()
	grass.role_id = "grass"; grass.pixels.resize(256)
	grass.grass_light_enabled = true
	grass.albedo_texture = ImageTexture.create_from_image(Fixture.grass_artwork())
	grass.pattern_size_m = 2.0; grass.pixel_relief = 0.0; grass.micro_relief = 0.0
	grass.base_color = Color("637f50")
	assert(ResourceSaver.save(grass, "res://content/terrain_materials/painted_light_grass.tres") == OK)
	# Quieter pigment, larger paired pattern. Sol's height image and 4cm amplitude
	# stay exact; the shared Pattern span scales colour and height together.
	var stone := Pattern.new(); stone.role_id = "stone"; stone.pixels.resize(256)
	stone.base_color = Color("898779"); stone.pattern_size_m = 1.8; stone.pixel_relief = 0.04
	var color := Image.load_from_file("res://content/terrain_materials/textures/material_depth_study/stone_color.png")
	for y in color.get_height():
		for x in color.get_width():
			color.set_pixel(x, y, Color("96907f").lerp(color.get_pixel(x, y), 0.12))
	color.generate_mipmaps(); stone.albedo_texture = ImageTexture.create_from_image(color)
	assert(ResourceSaver.save(stone, "res://content/terrain_materials/painted_light_stone.tres") == OK)
	print("PAINTED_FIXTURE PASS: independent Source and flat colour-only grass")
	quit()
