extends "res://scripts/prototypes/ember_oak_looks_study.gd"
## Material recipe pilot, not the production world switch. Terrain geometry and
## physics stay fixed across views; oak shells reuse the already reviewed bake.
const StyleBake=preload("res://scripts/ember_material_look_bake.gd")
var styles_ready:=false
var material_style:=0
var material_variants: Array[ShaderMaterial]=[]
var grass_variants: Array[ArrayMesh]=[]
var leaf_textures: Array[Texture2D]=[]
var study_images: Dictionary={}
var style_stats: Array=[]
var study_bake_count:=0
var original_depth_shader: Shader
var style_label: Label

func apply_depth() -> void:
	super.apply_depth()
	if depth_material!=null:depth_material.set_shader_parameter("smooth_surface_enabled",true)

func prepare() -> void:
	await super.prepare()
	set_alternate_look(1)
	original_depth_shader=depth_shader
	var shape_shader:=Shader.new();shape_shader.code="#define EMBER_MATERIAL_SHAPE_STUDY\n"+depth_shader.code
	shape_shader.set_meta("ember_compact_terrain_shader",true)
	var original_leaf: Texture2D=smooth_visual.mesh.surface_get_material(1).get_shader_parameter("painted_leaf_card_albedo")
	var leaf_image:=original_leaf.get_image()
	var source_stone:=_stone.albedo_texture.get_image()
	var source_grass:=_grass.albedo_texture.get_image()
	var source_height:=height_texture.get_image()
	var source_tuft: ArrayMesh=tuft_visual.multimesh.mesh
	for look in 3:
		var stone:=StyleBake.image_variant(source_stone,look,{"cell":32,"min_cell":8,"tolerance":0.055,"strength":0.88,"periodic":true},source_height)
		var grass:=StyleBake.image_variant(source_grass,look,{"cell":32,"min_cell":16,"tolerance":0.06,"strength":0.9,"periodic":true})
		var leaves:=StyleBake.image_variant(leaf_image,look,{"resolution":512,"cell":16 if look==1 else 8,"min_cell":4,"tolerance":0.15,"strength":0.85})
		study_images[look]={"stone":stone.image,"grass":grass.image,"leaf":leaves.image}
		style_stats.append({"look":look,"stone_regions":stone.regions,"grass_regions":grass.regions,"leaf_regions":leaves.regions,"image_bake_ms":stone.build_ms+grass.build_ms+leaves.build_ms})
		leaf_textures.append(original_leaf if look==0 else ImageTexture.create_from_image(leaves.image))
		var material:=depth_material.duplicate() as ShaderMaterial
		material.shader=shape_shader;material.set_shader_parameter("material_shape_mode",look)
		if look!=0:
			var stone_pattern:=_stone.duplicate() as EmberCompactTerrainPattern
			var grass_pattern:=_grass.duplicate() as EmberCompactTerrainPattern
			stone_pattern.albedo_texture=ImageTexture.create_from_image(stone.image)
			grass_pattern.albedo_texture=ImageTexture.create_from_image(grass.image)
			Materials.set_compact_terrain_roles(material,_projection.document.palette_surface_roles,_projection.document.palette_material_ids,_projection.document.palette,
				{"cartoon_stone":stone_pattern,"cartoon_sand":_depth_sand,"cartoon_grass":grass_pattern},PackedStringArray(["cartoon_stone","cartoon_grass"]))
			material.set_shader_parameter("png_mean_lookup",depth_material.get_shader_parameter("png_mean_lookup"))
		material_variants.append(material)
		grass_variants.append(StyleBake.grass_mesh(source_tuft,look,PaintedFixture.grass_tuft_outline()))
		study_bake_count+=1
		await get_tree().process_frame
	depth_shader=shape_shader;base_shader=shape_shader
	faceted_visual.mesh.surface_get_material(1).set_shader_parameter("painted_leaf_card_albedo",leaf_textures[1])
	voxel_visual.mesh.surface_get_material(1).set_shader_parameter("painted_leaf_card_albedo",leaf_textures[2])
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	_build_style_controls()
	styles_ready=true;set_material_style(0);set_study_view(0)
	print("MATERIAL_SHAPES_READY ",style_stats)

func set_material_style(index: int) -> void:
	material_style=clampi(index,0,2)
	depth_material=material_variants[material_style]
	depth_material.set_shader_parameter("material_depth_sun_direction",get_node("Map/Look/Sun").global_basis.z)
	for tile in _projection._tiles.values():tile.get_node("Ground").material_override=depth_material
	tuft_visual.multimesh.mesh=grass_variants[material_style]
	_sync_tuft_material()
	if material_style==0:set_look_fraction(0)
	else:
		set_alternate_look(1 if material_style==1 else 0);set_look_fraction(1)
		if material_style==1:set_leaf_shape_kind(0);set_leaf_shape(0.7)
	if style_label!=null:style_label.text=["Гладкая подача","Гранёная подача","Воксельная подача"][material_style]+" · материал + листва\nОдна физика · глубина камня 4 см\nГеометрия земли здесь постоянна"

func set_study_view(index: int) -> void:
	if index==0:set_look_view(0);return
	if index==1:set_look_view(2);return
	if index==3:set_look_view(1);return
	follow_camera.set_process(false)
	var target:=Vector3(3.8,1.2,4.8)
	var camera: Camera3D=follow_camera._cam
	camera.fov=40;camera.global_position=target+Vector3(2.0,1.8,3.3);camera.look_at(target)

func _build_style_controls() -> void:
	var panel:=PanelContainer.new();panel.position=Vector2(18,18);get_node("Instructions").add_child(panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=330;panel.add_child(column)
	style_label=Label.new();column.add_child(style_label)
	for i in 3:
		var button:=Button.new();button.text=["Гладкий","Гранёный","Воксельный"][i];column.add_child(button);button.pressed.connect(set_material_style.bind(i))
	for item in [["Игровая камера",0],["Листья ближе",1],["Камень и трава",2],["Дерево целиком",3]]:
		var button:=Button.new();button.text=item[0];column.add_child(button);button.pressed.connect(set_study_view.bind(item[1]))
	for item in [["День",1],["Вечер",0],["Ночь",2]]:
		var button:=Button.new();button.text=item[0];column.add_child(button);button.pressed.connect(set_lighting_preset.bind(item[1]))
	var sun:=Button.new();sun.text="Боковой / контровой свет";column.add_child(sun);sun.pressed.connect(func():set_sun_pose(1-_sun_pose))
	var hint:=Label.new();hint.text="F1 — панели · настройки пробы временные";column.add_child(hint)
