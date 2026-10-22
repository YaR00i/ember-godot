extends "res://scripts/prototypes/ember_coherent_looks_study.gd"
const RockRecipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
var rock_ready:=false
var plain_rock:=false
var rock_materials: Array[ShaderMaterial]=[]
var plain_materials: Array[ShaderMaterial]=[]
var saved_grass_materials: Array[ShaderMaterial]=[]
var rock_maps: Dictionary={}
var rock_stats: Dictionary={}
var original_grass_hashes: Array=[]

func prepare() -> void:
	await super.prepare()
	for look in 3:
		super.set_material_style(look)
		saved_grass_materials.append(tuft_visual.material_override)
		original_grass_hashes.append([hash(grass_scatter[look].buffer),hash(grass_variants[look].surface_get_arrays(0))])
	var largest:=0.0;var points:=0;var planes:=0
	for key: Vector2i in terrain_variants:
		var field: Dictionary=_projection._smooth_field(key)
		var begin:=key*64
		var bounds:=Rect2i(begin,Vector2i(mini(64,_projection.document.width-begin.x),mini(64,_projection.document.depth-begin.y)))
		var baked:=TerrainLook.rock_faceted(terrain_variants[key][0],terrain_variants[key][1],field,bounds)
		terrain_variants[key][1]=baked.mesh
		largest=maxf(largest,baked.max_error_m);points+=baked.control_points;planes+=baked.planes
		await get_tree().process_frame
	rock_maps=RockRecipe.maps()
	for look in 3:
		var grass:=_grass.duplicate() as EmberCompactTerrainPattern
		if look>0:grass.albedo_texture=ImageTexture.create_from_image(study_images[1].grass if look==1 else TerrainLook.pixel_image(_grass.albedo_texture.get_image()))
		for plain in [false,true]:
			var material:=material_variants[look].duplicate() as ShaderMaterial
			var stone:=_stone.duplicate() as EmberCompactTerrainPattern
			var colour: Image=rock_maps.colour
			var relief: Image=rock_maps.height
			if look==1:
				colour=StyleBake.image_variant(colour,1,{"cell":16,"min_cell":4,"strength":0.55,"tolerance":0.10,"periodic":true},relief).image
			elif look==2:
				colour=TerrainLook.pixel_image(colour,32);relief=TerrainLook.pixel_image(relief,32)
			if plain:
				colour=Image.create(16,16,false,Image.FORMAT_RGBA8);colour.fill(Color("94958f"));colour.generate_mipmaps()
			stone.albedo_texture=ImageTexture.create_from_image(colour)
			stone.base_color=Color("90938f");stone.pattern_size_m=RockRecipe.SPAN_M
			Materials.set_compact_terrain_roles(material,_projection.document.palette_surface_roles,_projection.document.palette_material_ids,_projection.document.palette,
				{"cartoon_stone":stone,"cartoon_sand":_depth_sand,"cartoon_grass":grass},PackedStringArray(["cartoon_stone","cartoon_grass"]))
			# Preserve the previous normalization for every non-rock palette slot.
			var old_mean: Image=material_variants[look].get_shader_parameter("png_mean_lookup").get_image()
			var new_mean: Image=material.get_shader_parameter("png_mean_lookup").get_image()
			for slot in new_mean.get_width():
				if slot!=1:new_mean.set_pixel(slot,0,old_mean.get_pixel(slot,0))
			material.set_shader_parameter("png_mean_lookup",ImageTexture.create_from_image(new_mean))
			material.set_shader_parameter("material_depth_height",ImageTexture.create_from_image(relief))
			material.set_shader_parameter("material_depth_enabled",not plain)
			if plain:plain_materials.append(material)
			else:rock_materials.append(material)
	rock_stats={"max_grid_error_m":largest,"tolerance_m":0.0375,"adaptive_points":points,"adaptive_planes":planes,"scope":"rock vertices only; original grass and colliders retained"}
	rock_ready=true;set_material_style(0);set_plain_rock(true);set_rock_view(1)
	print("NATURAL_ROCK_READY ",rock_stats)

func set_material_style(index: int) -> void:
	if rock_ready:material_variants=plain_materials if plain_rock else rock_materials
	super.set_material_style(index)
	if rock_ready:
		tuft_visual.material_override=saved_grass_materials[material_style]
		style_label.text=["Гладкий","Гранёный","Воксельный"][material_style]+(" · только форма" if plain_rock else " · природный камень")+"\nОбщий свет · трава прежняя"

func set_plain_rock(enabled: bool) -> void:
	plain_rock=enabled
	if rock_ready:set_material_style(material_style)

func set_rock_view(index: int) -> void:
	if index==0:set_study_view(0);return
	follow_camera.set_process(false)
	var camera: Camera3D=follow_camera._cam
	var target:=Vector3(3.65,1.55,3.95)
	camera.fov=40;camera.global_position=target+Vector3(2.9,2.5,5.8);camera.look_at(target)

func _build_style_controls() -> void:
	super._build_style_controls()
	var button:=CheckButton.new();button.text="Камень без текстуры";button.button_pressed=true
	style_label.get_parent().add_child(button);button.toggled.connect(set_plain_rock)
	var view:=Button.new();view.text="Камень целиком";style_label.get_parent().add_child(view);view.pressed.connect(set_rock_view.bind(1))
