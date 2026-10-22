extends RefCounted
## LAB painted colour master. Existing optical/roughness channels stay separate.
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Pigment=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const SPAN_M:=0.6
const MASTER_PATH:="res://content/terrain_materials/textures/soil-painted-genshin-v4.png"
const CAMOUFLAGE_MASTER_PATH:="res://content/terrain_materials/textures/soil-cartoon-isometric-v3.png"
const PREVIOUS_MASTER_PATH:="res://content/terrain_materials/textures/soil-painted-v2.png"

static func sample(p: Vector2) -> Color:
	# Continuous periodic pigment, deliberately independent of the old 16-cell
	# canvas. Broad restrained strokes, fine low-contrast soil grain, no cracks.
	var warp:=Vector2(sin(TAU*p.y),cos(TAU*p.x))*0.025
	var broad:=Pigment.pigment_value(p+warp,3)*0.82+Pigment.pigment_value(p+warp+Vector2(0.12,0.07),6)*0.18
	var band:=broad*4.0
	var tone:=(floorf(band)+smoothstep(0.20,0.80,fposmod(band,1.0)))/4.0
	var grain:=(Pigment.pigment_value(p,53)-0.5)*0.008
	var colour:=Color("7d5c3e").lerp(Color("9a7955"),tone)
	return Color(colour.r+grain,colour.g+grain,colour.b+grain,1.0)

static func colour_image(size:=256,revision:=3) -> Image:
	if revision>0:
		# The generated albedo is an ordinary project asset. The existing bank
		# handles filtering/seams; it never becomes optical height in this trial.
		var path:=MASTER_PATH if revision>2 else (CAMOUFLAGE_MASTER_PATH if revision==2 else PREVIOUS_MASTER_PATH)
		var painted:=Image.load_from_file(path)
		assert(painted!=null and not painted.is_empty(),"missing painted soil master")
		painted.convert(Image.FORMAT_RGBA8)
		painted.resize(size,size,Image.INTERPOLATE_LANCZOS)
		painted.generate_mipmaps();return painted
	# Keep the previous procedural trial reproducible for direct A/B comparison.
	var image:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:image.set_pixel(x,y,sample(Vector2(x+0.5,y+0.5)/float(size)))
	image.generate_mipmaps();return image

static func colours(master: Image,previous:=false) -> Array[Image]:
	# Isometric readability: calm the tone without blurring the drawn boundaries.
	var calm:=Bake.calm_variant(master,12,0.35) if previous else Bake.calm_variant(master,master.get_width(),0.65)
	return [master,calm,TerrainLook.pixel_image(master,8)]

static func colour_row(atlas: Image,colour: Image,slot: int) -> Image:
	assert(colour.get_size()==Vector2i(16,16) and atlas.get_width()==16 and slot>=0 and slot*16+16<=atlas.get_height())
	var result:=atlas.duplicate() as Image
	for y in 16:
		for x in 16:
			var c:=colour.get_pixel(x,y);c.a=atlas.get_pixel(x,slot*16+y).a
			result.set_pixel(x,slot*16+y,c)
	return result
