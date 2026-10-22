extends RefCounted
## Bounded artwork-specific valley selection; not colour -> physical geometry.
const MASTER:="res://content/material_studies/trees/bark_species_v1/oak-v3-painted.png"
const VERSION:="oak-v3-selected-valleys-1"
const CORRIDORS=[Vector2(0.0,0.19),Vector2(0.27,0.49),Vector2(0.60,0.80),Vector2(0.90,1.0)]
static var cache: Dictionary={}
static var bake_count:=0

static func mask_for(master: Image) -> Image:
	var key:=VERSION+master.get_data().hex_encode().sha256_text()
	if cache.has(key):return cache[key].duplicate() as Image
	var image:=master.duplicate() as Image
	image.convert(Image.FORMAT_RGB8);image.resize(256,256,Image.INTERPOLATE_LANCZOS)
	var field:=PackedFloat32Array();field.resize(256*256)
	for y in 256:
		for x in 256:
			var value:=0.0
			for dy in [-1,0,1]:
				for dx in [-1,0,1]:
					var c:=image.get_pixel(clampi(x+dx,0,255),clampi(y+dy,0,255))
					value+=(c.r*0.2126+c.g*0.7152+c.b*0.0722)*(2.0 if dx==0 else 1.0)*(2.0 if dy==0 else 1.0)/16.0
			field[x+y*256]=value
	var result:=Image.create(256,256,false,Image.FORMAT_R8)
	var peak:=0.0
	for y in 256:
		for x in 256:
			var uv:=Vector2((x+0.5)/256.0,(y+0.5)/256.0)
			var selected:=0.0
			for corridor: Vector2 in CORRIDORS:
				selected=maxf(selected,smoothstep(corridor.x,corridor.x+0.015,uv.x)*(1.0-smoothstep(corridor.y-0.015,corridor.y,uv.x)))
			var left:=0.0;var right:=0.0
			for offset in range(9,14):
				left+=field[clampi(x-offset,0,255)+y*256]/5.0
				right+=field[clampi(x+offset,0,255)+y*256]/5.0
			# Both flanks must be lighter: broad dark paint planes are not recesses.
			var valley:=minf(left,right)-field[x+y*256]
			var edge:=smoothstep(0.0,0.025,minf(minf(uv.x,1.0-uv.x),minf(uv.y,1.0-uv.y)))
			var depth:=smoothstep(0.028,0.095,valley)*selected*edge
			peak=maxf(peak,depth);result.set_pixel(x,y,Color(depth,0,0,1))
	if peak>0.2:
		for y in 256:
			for x in 256:result.set_pixel(x,y,Color(clampf(result.get_pixel(x,y).r/peak,0,1),0,0,1))
	result.generate_mipmaps();cache[key]=result.duplicate();bake_count+=1
	return result
