extends RefCounted
## LAB pigment only. Shared scale and one master; no height/terrain ownership.
const Pigment=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const SPAN_M:=1.5
const PaintedEarth=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
const PAINTED_BASE_COLOR:=Color("b9a47c")

static func painted_image(size:=256) -> Image:
	# Same accepted painted earth family; the material owner applies road tint.
	# Keep colour_image() below intact for every earlier LAB and its A control.
	return PaintedEarth.colour_image(size)

static func painted_variants(master: Image) -> Array[Image]:
	# Calm tone without resampling the clear painted boundaries in the middle look.
	return [master,Bake.calm_variant(master,master.get_width(),0.65),TerrainLook.pixel_image(master,16)]

static func sample(p: Vector2,grain_strength:=1.0) -> Color:
	var warp:=Vector2(sin(TAU*p.y),cos(TAU*p.x))*0.045
	var broad:=Pigment.pigment_value(p+warp,3)*0.75+Pigment.pigment_value(p+warp+Vector2(0.17,0.06),5)*0.25
	var tone:=smoothstep(0.12,0.88,broad)
	var colour:=Color("c3aa78").lerp(Color("e3d09f"),0.18+0.64*tone)
	var cell:=Vector2i(floori(p.x*256.0+0.0001),floori(p.y*256.0+0.0001))
	var h:=posmod(cell.x,256)*374761393+posmod(cell.y,256)*668265263
	h=(h^(h>>13))*1274126177
	var grain:=(float((h^(h>>16))&65535)/65535.0-0.5)*0.012*grain_strength
	return Color(colour.r+grain,colour.g+grain,colour.b+grain,1)

static func colour_image(size:=256) -> Image:
	var image:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:image.set_pixel(x,y,sample(Vector2(x+0.5,y+0.5)/float(size)))
	image.generate_mipmaps();return image

static func variants(master: Image) -> Array[Image]:
	return [master,Bake.calm_variant(master,12,0.30),TerrainLook.pixel_image(master,16)]
