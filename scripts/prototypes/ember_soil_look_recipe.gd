extends RefCounted
## LAB painted colour master. Existing optical/roughness channels stay separate.
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Pigment=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const SPAN_M:=0.6
const LOOSE_SPAN_M:=2.4
const MASTER_PATH:="res://content/terrain_materials/textures/soil-painted-genshin-v4.png"
const CAMOUFLAGE_MASTER_PATH:="res://content/terrain_materials/textures/soil-cartoon-isometric-v3.png"
const PREVIOUS_MASTER_PATH:="res://content/terrain_materials/textures/soil-painted-v2.png"

## Draft loose-earth recipe: colour and explicit optical height from the same
## periodic aggregates. Prepared once for a comparison, never evaluated per frame.
## Existing accepted artwork/default colour_image remains unchanged.
static func loose_hash(cell:Vector2i,grid:int,seed:int)->float:
	var h:=(posmod(cell.x,grid)*374761393+posmod(cell.y,grid)*668265263+seed*1447)&0x7fffffff
	h=((h^(h>>13))*1274126177)&0x7fffffff
	return float((h^(h>>16))&65535)/65535.0

static func loose_noise(p:Vector2,grid:int,seed:int)->float:
	var q:=p*grid;var c:=Vector2i(floori(q.x),floori(q.y));var f:=q-Vector2(c)
	f=f*f*(Vector2.ONE*3.0-f*2.0)
	return lerpf(lerpf(loose_hash(c,grid,seed),loose_hash(c+Vector2i.RIGHT,grid,seed),f.x),lerpf(loose_hash(c+Vector2i.DOWN,grid,seed),loose_hash(c+Vector2i.ONE,grid,seed),f.x),f.y)

static func loose_features(seed:int)->Array[Dictionary]:
	var random:=RandomNumberGenerator.new();random.seed=seed
	var result:Array[Dictionary]=[]
	# No feature lattice: sizes, angle, spacing and sign belong to each clod.
	# Broad overlap leaves some unbroken earth rather than a network of joints.
	for i in 42:
		result.append({"at":Vector2(random.randf(),random.randf()),
			"radius":Vector2(random.randf_range(0.035,0.105),random.randf_range(0.025,0.070)),
			"angle":random.randf_range(-PI,PI),"phase":random.randf_range(-PI,PI),
			"amount":random.randf_range(0.12,0.28)*(-0.65 if i%5==0 else 1.0)})
	return result

static func loose_sample(p:Vector2,seed:=17,features:Array[Dictionary]=[])->Vector2:
	if features.is_empty():features=loose_features(seed)
	var warp:=Vector2(loose_noise(p,5,seed+2)-0.5,loose_noise(p,5,seed+7)-0.5)*0.085
	var q:=p+warp
	var masses:=0.0
	for feature:Dictionary in features:
		var d:=q-(feature.at as Vector2)
		d=Vector2(fposmod(d.x+0.5,1.0)-0.5,fposmod(d.y+0.5,1.0)-0.5)
		d=d.rotated(feature.angle)/(feature.radius as Vector2)
		var angle:=atan2(d.y,d.x)
		var contour:=1.0+0.25*sin(angle*3.0+feature.phase)+0.16*sin(angle*5.0-feature.phase*1.7)
		var r2:=d.length_squared()/(contour*contour)
		if r2<5.0:masses+=smoothstep(0.20,0.72,exp(-r2*1.6))*feature.amount
	var broad:=loose_noise(p,3,seed+5)-0.5
	var grain:=loose_noise(q,83,seed+11)-0.5
	var shoulder:=loose_noise(q,13,seed+19)-0.5
	var fragments:=loose_noise(q,33,seed+23)-0.5
	var height:=clampf(0.38+masses+broad*0.08+shoulder*0.04+fragments*0.055+grain*0.012,0.18,0.84)
	var tone:=clampf(0.44+masses*0.60+broad*0.12+shoulder*0.07+fragments*0.10+grain*0.018,0.0,1.0)
	return Vector2(tone,height)
static func loose_channels(size:=256,seed:=17)->Dictionary:
	var colour:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	var height:=Image.create(size,size,false,Image.FORMAT_R8)
	var features:=loose_features(seed)
	for y in size:
		for x in size:
			var v:=loose_sample(Vector2(x+0.5,y+0.5)/float(size),seed,features)
			colour.set_pixel(x,y,Color("67462e").lerp(Color("ab875b"),v.x))
			height.set_pixel(x,y,Color(v.y,0,0))
	colour.generate_mipmaps();height.generate_mipmaps()
	return {"colour":colour,"height":height}

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
