extends "res://scripts/prototypes/ember_material_shapes_study.gd"
## Three complete presentations of this dry fixture, not a runtime world API.
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const TerrainMesh=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
var coherent_ready:=false
var terrain_variants: Dictionary={}
var grass_scatter: Array[MultiMesh]=[]
var coarse_grass: ArrayMesh
var use_coarse_grass:=false
var geometry_stats: Dictionary={}

func prepare() -> void:
	await super.prepare()
	# Unrelated door-size probe is hidden consistently in all three frames.
	door.hide()
	var max_delta:=0.0
	var counts: Array[int]=[0,0,0]
	for key: Vector2i in _projection._tiles:
		var original: ArrayMesh=_projection._tiles[key].get_node("Ground").mesh
		var field: Dictionary=_projection._smooth_field(key)
		var faceted:=TerrainLook.faceted(original,field)
		var voxel: ArrayMesh=TerrainMesh.build_tile(_projection.document,key.x*64,key.y*64,64,0,false,PackedVector4Array(),{},true).terrain
		terrain_variants[key]=[original,faceted.mesh,voxel]
		max_delta=maxf(max_delta,faceted.max_delta_m)
		for i in 3:counts[i]+=terrain_variants[key][i].get_faces().size()/3
		await get_tree().process_frame
	var original_tuft: ArrayMesh=grass_variants[0]
	grass_variants[2]=StyleBake.grass_mesh(original_tuft,2,PaintedFixture.grass_tuft_outline(),{"pixel_m":0.0625,"coverage":true})
	coarse_grass=StyleBake.grass_mesh(original_tuft,1,PaintedFixture.grass_tuft_outline(),{"corners":7})
	# Prebake visual anchors. x/z, seed, density and physical field are unchanged.
	var original_scatter:=tuft_visual.multimesh
	for look in 3:
		var scatter:=original_scatter.duplicate() as MultiMesh
		scatter.mesh=grass_variants[look]
		if look>0:
			for i in scatter.instance_count:
				var transform:=scatter.get_instance_transform(i)
				var point:=tuft_visual.to_global(transform.origin)
				var p:=Vector2(point.x,point.z)*16.0
				var key:=Vector2i(floori(p.x/64),floori(p.y/64))
				if not terrain_variants.has(key):continue
				var field: Dictionary=_projection._smooth_field(key)
				var original_y:=TerrainLook.Smooth.sample(field,p)/16.0
				var visual_y: float=TerrainLook.plane(field,p).height/16.0 if look==1 else float(_projection.document.column_value("heights",_projection.document.column_index(floori(p.x),floori(p.y)))+_projection.document.origin_y)/16.0
				point.y+=visual_y-original_y
				transform.origin=tuft_visual.to_local(point);scatter.set_instance_transform(i,transform)
		grass_scatter.append(scatter)
	# Same automatic grid for colour and optical height, same common POM solver.
	var stone:=_stone.duplicate() as EmberCompactTerrainPattern
	var grass:=_grass.duplicate() as EmberCompactTerrainPattern
	stone.albedo_texture=ImageTexture.create_from_image(TerrainLook.pixel_image(_stone.albedo_texture.get_image()))
	grass.albedo_texture=ImageTexture.create_from_image(TerrainLook.pixel_image(_grass.albedo_texture.get_image()))
	var material:=material_variants[2]
	Materials.set_compact_terrain_roles(material,_projection.document.palette_surface_roles,_projection.document.palette_material_ids,_projection.document.palette,
		{"cartoon_stone":stone,"cartoon_sand":_depth_sand,"cartoon_grass":grass},PackedStringArray(["cartoon_stone","cartoon_grass"]))
	material.set_shader_parameter("png_mean_lookup",material_variants[0].get_shader_parameter("png_mean_lookup"))
	material.set_shader_parameter("material_depth_height",ImageTexture.create_from_image(TerrainLook.pixel_image(height_texture.get_image())))
	material.set_shader_parameter("smooth_surface_enabled",false)
	# Nearest magnification only in this private LAB variant. Mips remain active.
	var pixel_shader:=Shader.new()
	pixel_shader.code=depth_shader.code.replace("png_albedo_bank : source_color, filter_linear_mipmap_anisotropic","png_albedo_bank : source_color, filter_nearest_mipmap")
	pixel_shader.set_meta("ember_compact_terrain_shader",true);material.shader=pixel_shader
	geometry_stats={"triangles":counts,"faceted_max_delta_m":max_delta,"voxel_cell_m":0.0625,"grass_local_pixel_m":0.0625,"physical_surface":"original smooth field; presentation shell only"}
	coherent_ready=true;set_material_style(0)
	print("COHERENT_LOOKS_READY ",geometry_stats)

func set_material_style(index: int) -> void:
	if coherent_ready:tuft_visual.multimesh=grass_scatter[clampi(index,0,2)]
	super.set_material_style(index)
	if not coherent_ready:return
	for key: Vector2i in terrain_variants:_projection._tiles[key].get_node("Ground").mesh=terrain_variants[key][material_style]
	depth_material.set_shader_parameter("smooth_surface_enabled",material_style!=2)
	tuft_visual.multimesh=grass_scatter[material_style]
	tuft_visual.multimesh.mesh=coarse_grass if material_style==1 and use_coarse_grass else grass_variants[material_style]
	_sync_tuft_material()
	# Grass cards always carry the blended palette vertex layout, even over voxels.
	(tuft_visual.material_override as ShaderMaterial).set_shader_parameter("smooth_surface_enabled",true)
	style_label.text=["Детальный мир","Гранёный мир","Воксельный мир"][material_style]+" · форма + материал + трава\nОдна физическая поверхность · глубина 4 см\nLAB: формы запечены заранее"

func set_coarse_grass(enabled: bool) -> void:
	use_coarse_grass=enabled
	if coherent_ready:set_material_style(material_style)

func _build_style_controls() -> void:
	super._build_style_controls()
	var toggle:=CheckButton.new();toggle.text="Гранёная трава — грубее"
	style_label.get_parent().add_child(toggle);toggle.toggled.connect(set_coarse_grass)
