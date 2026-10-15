extends RefCounted
## Derived LAB support pairs. The generator's existing coordinate leaf owns
## branch frames and their phase. Source/shape/indices/palette are immutable.
const Bark=preload("res://addons/ember_import/ember_voxel_bark_pattern.gd")
const Profiles=preload("res://scripts/ember_voxel_material_profiles.gd")
const ART="res://content/material_studies/trees/painterly_bark_v2.png"
const CALM_ART="res://content/material_studies/trees/painterly_bark_v3_calm.png"
const FOLIAGE_ART="res://content/material_studies/trees/painterly_foliage_v1.png"
const LEAF_CARD_ART="res://content/material_studies/trees/leaf_card_sprig_v1.png"
static var _art_textures: Dictionary={}

static func artwork(path: String, alpha_edges:=false) -> ImageTexture:
	var key:=path+"|alpha_edges" if alpha_edges else path
	if not _art_textures.has(key):
		var image:=Image.load_from_file(ProjectSettings.globalize_path(path))
		assert(image!=null)
		if alpha_edges and image.detect_alpha()!=Image.ALPHA_NONE:
			image=_alpha_safe_mips(image)
		else:
			var mip_error:=image.generate_mipmaps()
			assert(mip_error==OK)
		_art_textures[key]=ImageTexture.create_from_image(image)
	return _art_textures[key]

static func _alpha_safe_mips(image: Image) -> Image:
	# Runtime preparation only: artist PNG and all alpha levels stay unchanged.
	# Plain RGB averaging mixes transparent black into leaves. Weight mip colour
	# by opacity, then store straight RGB for the existing source_color sampler.
	assert(image.get_format()==Image.FORMAT_RGBA8)
	image.fix_alpha_edges()
	var base:=image.get_data()
	var weighted:=image.duplicate() as Image
	weighted.premultiply_alpha()
	var mip_error:=weighted.generate_mipmaps()
	assert(mip_error==OK)
	var pixels:=weighted.get_data()
	for i in range(base.size(),pixels.size(),4):
		var alpha:=int(pixels[i+3])
		if alpha>0:
			for channel in 3:pixels[i+channel]=mini(255,roundi(float(pixels[i+channel])*255.0/alpha))
	# Keep the authored base (apart from transparent-border colour padding).
	pixels=base+pixels.slice(base.size())
	var levels:=Image.create_from_data(image.get_width(),image.get_height(),true,Image.FORMAT_RGBA8,pixels)
	var padded:=PackedByteArray()
	for level in range(levels.get_mipmap_count()+1):
		var start:=levels.get_mipmap_offset(level)
		var width:=maxi(1,image.get_width()>>level)
		var height:=maxi(1,image.get_height()>>level)
		var mip:=Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,pixels.slice(start,start+width*height*4))
		mip.fix_alpha_edges();padded.append_array(mip.get_data())
	return Image.create_from_data(image.get_width(),image.get_height(),true,Image.FORMAT_RGBA8,padded)

static func mesh(original: ArrayMesh, structure: Dictionary, pivot: Vector2i) -> ArrayMesh:
	var arrays:=original.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var support:=Bark.support_frames(structure.lines)
	var offset:=Vector3(pivot.x,0,pivot.y)
	var custom:=PackedFloat32Array();custom.resize(vertices.size()*4)
	var frame_pairs:=PackedFloat32Array();frame_pairs.resize(vertices.size()*4)
	for start in range(0,vertices.size(),3):
		var centre: Vector3=(vertices[start]+vertices[start+1]+vertices[start+2])/3.0
		var centre_coordinates:=Bark.support_coordinates(centre*16.0-offset,support)
		var frame:=int(centre_coordinates[3])
		assert(frame>=0)
		var second:=frame;var second_distance:=INF
		var raw_centre:=centre*16.0-offset
		for index in support.buckets.get(Bark._bucket(raw_centre),[]):
			if index==frame:continue
			var f: Dictionary=support.frames[index]
			var relative: Vector3=raw_centre-f.start
			var projection:=clampf(relative.dot(f.axis),0.0,f.length)
			var radius:=maxf(0.65,lerpf(f.r0,f.r1,projection/f.length))
			var distance: float=(relative-f.axis*projection).length_squared()/(radius*radius)
			if distance<second_distance:second_distance=distance;second=index
		for j in 3:
			var i:=start+j
			var profile: Vector4=Profiles.PROFILES.bark
			custom[i*4]=profile.x;custom[i*4+1]=profile.y;custom[i*4+2]=profile.z;custom[i*4+3]=0.0
			frame_pairs[i*4]=frame;frame_pairs[i*4+1]=second
	arrays[Mesh.ARRAY_CUSTOM0]=custom;arrays[Mesh.ARRAY_CUSTOM1]=frame_pairs
	var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return result

static func leaf_cards_material(reference: ArrayMesh, light_profile: Resource, coloured: bool, art_path := LEAF_CARD_ART) -> ShaderMaterial:
	var result:=foliage_material(reference,light_profile)
	var shader:=Shader.new()
	shader.code="#define EMBER_OBJECT_LEAF_CARDS_STUDY\n"+result.shader.code
	result.shader=shader
	result.set_shader_parameter("painted_leaf_card_albedo",artwork(art_path))
	result.set_shader_parameter("painted_leaf_card_coloured",coloured)
	result.set_shader_parameter("painted_leaf_card_cutoff",0.40)
	result.set_shader_parameter("surface_response_enabled",false)
	return result

static func material(structure: Dictionary, pivot: Vector2i, art_path: String=ART) -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="#define EMBER_OBJECT_PAINTED_BARK_STUDY\n"+(load("res://shaders/ember_voxel_toon.gdshader") as Shader).code
	var result:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	result.shader=shader
	result.set_shader_parameter("painted_bark_albedo",artwork(art_path))
	var frames: Array=Bark.support_frames(structure.lines).frames
	var table:=Image.create(4,frames.size(),false,Image.FORMAT_RGBAF)
	var offset:=Vector3(pivot.x,0,pivot.y)
	for i in frames.size():
		var f: Dictionary=frames[i]
		var start: Vector3=(f.start+offset)/16.0
		table.set_pixel(0,i,Color(start.x,start.y,start.z,f.length/16.0))
		table.set_pixel(1,i,Color(f.axis.x,f.axis.y,f.axis.z,f.r0/16.0))
		table.set_pixel(2,i,Color(f.u.x,f.u.y,f.u.z,f.r1/16.0))
		table.set_pixel(3,i,Color(f.v.x,f.v.y,f.v.z,f.origin/16.0))
	result.set_shader_parameter("painted_bark_supports",ImageTexture.create_from_image(table))
	result.set_shader_parameter("painted_bark_period_m",3.0)
	result.set_shader_parameter("surface_grain_scale",0.0)
	return result

static func foliage_material(original: ArrayMesh, light_profile: Resource) -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="#define EMBER_OBJECT_PAINTED_FOLIAGE_STUDY\n"+(load("res://shaders/ember_voxel_toon.gdshader") as Shader).code
	var result:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	result.shader=shader
	result.set_shader_parameter("painted_foliage_albedo",artwork(FOLIAGE_ART))
	result.set_shader_parameter("painted_foliage_period_m",3.5)
	# Preserve Source paint as a relative multiplier around the saved canopy's
	# mean pigment. Only this derived LAB material adopts the new painted base.
	var colors: PackedColorArray=original.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var mean:=Vector3.ZERO
	for color in colors:
		var linear:=color.srgb_to_linear();mean+=Vector3(linear.r,linear.g,linear.b)
	mean/=maxi(colors.size(),1)
	result.set_shader_parameter("painted_foliage_paint_reference",mean)
	result.set_shader_parameter("surface_grain_scale",0.0)
	result.set_shader_parameter("painterly_enabled",true)
	result.set_shader_parameter("painterly_grass_masses",true)
	result.set_shader_parameter("painterly_rim_enabled",false)
	for pair in [["low","low"],["cool","cool"],["warm","warm"],["tint_strength","tint_strength"],["shadow_color","shadow_color"],["shadow_fill","shadow_fill"]]:
		result.set_shader_parameter("painterly_grass_"+pair[0],light_profile.get("grass_light_"+pair[1]))
	return result
