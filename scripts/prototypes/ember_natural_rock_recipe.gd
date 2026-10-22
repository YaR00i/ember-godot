extends RefCounted
## Deterministic periodic colour/height pair for continuous bedrock, not paving.
const SPAN_M:=2.4
const PAINTED_MASTER_PATH:="res://content/terrain_materials/textures/rock-painted-calm-v2.png"
const PAINT_RELIEF_RANGE_M:=0.006 # height .25..75 => actual 3mm span.
static var structure_bake_count:=0
static var _structure_cache: Dictionary={}

static func painted_image(size:=256) -> Image:
	var image:=Image.load_from_file(PAINTED_MASTER_PATH)
	assert(image!=null and not image.is_empty(),"missing painted stone master")
	image.convert(Image.FORMAT_RGBA8);image.resize(size,size,Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps();return image

static func painted_structure(master: Image) -> Image:
	# Artistic first-pass guide, not recovered physical shape: separate broad warm
	# and cool mineral regions, rather than treating brightness as absolute height.
	var key: String="warmth32-v1-"+master.get_data().hex_encode().sha256_text()
	if _structure_cache.has(key):return _structure_cache[key].duplicate() as Image
	var coarse:=master.duplicate() as Image;coarse.clear_mipmaps()
	coarse.resize(32,32,Image.INTERPOLATE_LANCZOS)
	var field:=PackedFloat32Array();field.resize(32*32)
	for y in 32:
		for x in 32:
			var value:=0.0
			for dy in range(-1,2):
				for dx in range(-1,2):
					var colour:=coarse.get_pixel(posmod(x+dx,32),posmod(y+dy,32))
					var weight: float=(2.0 if dx==0 else 1.0)*(2.0 if dy==0 else 1.0)
					value+=(colour.r-colour.b)*weight/16.0
			field[x+y*32]=value
	var sorted:=field.duplicate();sorted.sort()
	var lo:=sorted[102];var hi:=sorted[921]
	var result:=Image.create(master.get_width(),master.get_height(),false,Image.FORMAT_R8)
	for y in result.get_height():
		for x in result.get_width():
			var uv:=Vector2((x+0.5)*32.0/result.get_width()-0.5,(y+0.5)*32.0/result.get_height()-0.5)
			var cell:=Vector2i(floori(uv.x),floori(uv.y));var f:=uv-Vector2(cell)
			var values:=PackedFloat32Array()
			for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
				var c:=cell+offset;var t:=0.5
				if hi-lo>0.002:
					t=clampf((field[posmod(c.x,32)+posmod(c.y,32)*32]-lo)/(hi-lo),0,1)
					var band:=t*2.0;t=(floorf(band)+smoothstep(0.15,0.85,fposmod(band,1.0)))/2.0
				values.append(0.25+0.5*t)
			var h:=lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)
			result.set_pixel(x,y,Color(h,0,0,1))
	result.generate_mipmaps();_structure_cache[key]=result.duplicate();structure_bake_count+=1
	return result

static func pigment_value(p: Vector2,grid: int) -> float:
	# Periodic piecewise-linear pigment: angular paint masses, not round clouds.
	var q:=p*grid;var cell:=Vector2i(floori(q.x),floori(q.y));var f:=q-Vector2(cell)
	var values:=PackedFloat32Array()
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		var c:=cell+offset;var h:=posmod(c.x,grid)*374761393+posmod(c.y,grid)*668265263
		h=(h^(h>>13))*1274126177
		values.append(float((h^(h>>16))&65535)/65535.0)
	return values[0]+(values[1]-values[0])*f.x+(values[2]-values[0])*f.y if f.x+f.y<=1.0 else values[3]+(values[2]-values[3])*(1.0-f.x)+(values[1]-values[3])*(1.0-f.y)

static func painted_pigment(p: Vector2) -> Color:
	# Broad mineral/brush masses. Narrow soft shoulders retain a drawn boundary,
	# without the old fine tessellation or a blurred cloud over the rock faces.
	var warp:=Vector2(sin(TAU*p.y),cos(TAU*p.x))*0.008
	var paint:=pigment_value(p+warp+Vector2(0.07,0.11),3)*0.80+pigment_value(p+warp,5)*0.20
	var band:=paint*5.0
	var tone:=(floorf(band)+smoothstep(0.44,0.56,fposmod(band,1.0)))/5.0
	return Color("737f8a").lerp(Color("a0a196"),clampf(tone,0.0,1.0))

static func maps(size:=256,revision:=1) -> Dictionary:
	var colour:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	var height:=Image.create(size,size,false,Image.FORMAT_R8)
	var artwork: Image
	if revision>1:
		artwork=Image.load_from_file(PAINTED_MASTER_PATH)
		assert(artwork!=null and not artwork.is_empty(),"missing painted stone master")
		artwork.convert(Image.FORMAT_RGBA8);artwork.resize(size,size,Image.INTERPOLATE_LANCZOS)
	# Open, broken fractures. No closed Voronoi cells or masonry joints.
	var paths: Array[PackedVector2Array]=[
		PackedVector2Array([Vector2(0.08,0.18),Vector2(0.29,0.23),Vector2(0.42,0.19),Vector2(0.55,0.28)]),
		PackedVector2Array([Vector2(0.68,0.12),Vector2(0.75,0.31),Vector2(0.72,0.40)]),
		PackedVector2Array([Vector2(0.15,0.57),Vector2(0.27,0.52),Vector2(0.36,0.58)]),
		PackedVector2Array([Vector2(0.44,0.77),Vector2(0.59,0.71),Vector2(0.80,0.77),Vector2(0.90,0.73)]),
		PackedVector2Array([Vector2(0.92,0.41),Vector2(1.08,0.44),Vector2(1.18,0.38)]),
		PackedVector2Array([Vector2(0.36,0.93),Vector2(0.40,1.07)])]
	for y in size:
		for x in size:
			var p:=Vector2(float(x)/size,float(y)/size)
			var broad:=0.5+0.24*sin(TAU*(p.x+p.y))*cos(TAU*p.y)+0.16*cos(TAU*(2.0*p.x-p.y)+0.7)
			var paint:=pigment_value(p,5)*0.78+pigment_value(p,13)*0.22
			var tone:=floorf(paint*6.0)/5.0
			var pigment:=Color("77808a").lerp(Color("979a94"),clampf(tone,0,1))
			if revision==1:pigment=painted_pigment(p)
			elif revision>1:pigment=artwork.get_pixel(x,y)
			var closest:=1.0
			for path in paths:
				for j in path.size()-1:
					var a:=path[j];var b:=path[j+1];var centre:=(a+b)*0.5
					var q:=p+Vector2(roundf(centre.x-p.x),roundf(centre.y-p.y))
					var t:=clampf((q-a).dot(b-a)/(b-a).length_squared(),0,1)
					closest=minf(closest,q.distance_to(a+(b-a)*t))
			var fracture:=1.0-smoothstep(0.002,0.016,closest)
			var core:=1.0-smoothstep(0.001,0.005,closest)
			var h:=0.80+0.10*(broad-0.5)-0.68*fracture
			if revision==0:pigment=pigment.lerp(Color("535b65"),core*0.60)
			elif revision==1:pigment=pigment.lerp(Color("56626c"),core*0.32+fracture*0.08)
			else:pigment=pigment.lerp(Color("68737b"),core*0.22+fracture*0.04)
			colour.set_pixel(x,y,pigment);height.set_pixel(x,y,Color(h,0,0,1))
	colour.generate_mipmaps();height.generate_mipmaps()
	return {"colour":colour,"height":height}
